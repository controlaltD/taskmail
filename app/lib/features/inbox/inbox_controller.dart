import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_client.dart';
import '../../models/email_message.dart';
import '../auth/auth_controller.dart';

/// A bejelentkezett user leveleit adja vissza, AI kategorizálással —
/// a `sync-emails` Edge Function tölti fel/frissíti a sorokat a háttérben.
final inboxMessagesProvider = FutureProvider.autoDispose<List<EmailMessage>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];

  final rows = await supabase
      .from('taskmail_email_messages')
      .select()
      .eq('user_id', user.id)
      .order('received_at', ascending: false)
      .limit(100);

  return (rows as List).map((e) => EmailMessage.fromJson(e as Map<String, dynamic>)).toList();
});

/// Melyik levél van éppen kinyitva a listában. `null`, ha egyik sem.
final expandedMessageIdProvider = StateProvider.autoDispose<String?>((ref) => null);

/// Egy levél teljes tartalma, igény szerint letöltve.
///
/// A `family` kulcsa a levél azonosítója, így minden levél külön tölt be, és
/// a már letöltött tartalom a képernyőn maradva nem kérdeződik le újra.
/// Szándékosan NEM `autoDispose`: a felhasználó gyakran nyit-zár leveleket,
/// és bosszantó lenne, ha a becsukott levél tartalma azonnal elveszne.
final messageBodyProvider = FutureProvider.family<EmailMessage, EmailMessage>((ref, message) async {
  if (message.hasBody) return message;

  final response = await supabase.functions.invoke(
    'fetch-email-body',
    body: {'messageId': message.id},
  );

  final data = response.data as Map?;
  if (data == null || data['error'] != null) {
    throw MessageBodyException(data?['error'] as String?);
  }

  return message.withBody(
    bodyText: data['bodyText'] as String?,
    bodyHtml: data['bodyHtml'] as String?,
    bodyFetchedAt: DateTime.now(),
    toAddresses: (data['toAddresses'] as List?)?.map((e) => e as String).toList() ?? const [],
    ccAddresses: (data['ccAddresses'] as List?)?.map((e) => e as String).toList() ?? const [],
  );
});

/// A szerver rövid hibakódot ad vissza (a nyers hibaszöveg tartalmazhatna
/// tokent tartalmazó URL-t), ezt fordítjuk olvasható üzenetre.
class MessageBodyException implements Exception {
  const MessageBodyException(this.code);

  final String? code;

  String get message => switch (code) {
        'auth_expired' => 'A postafiók kapcsolata lejárt. Kösd össze újra a Fiókok fülön.',
        'account_not_connected' => 'Ehhez a levélhez nincs élő postafiók-kapcsolat.',
        'not_found' => 'A levél nem található.',
        _ => 'A levél tartalmát nem sikerült betölteni.',
      };

  @override
  String toString() => message;
}
