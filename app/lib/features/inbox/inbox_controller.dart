import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_client.dart';
import '../../models/email_message.dart';
import '../../models/mail_folder.dart';
import '../auth/auth_controller.dart';

/// Egy mappa (illetve AI-kategória szűrő) levelei.
///
/// A Piszkozatok/Elküldött nézetek a TaskMail saját nyilvántartásából
/// olvasnának, ami a 4-5. fázisban készül el — addig üres listát adnak,
/// nem hibát: a mappa létezik, csak még nincs benne semmi.
final mailboxMessagesProvider =
    FutureProvider.autoDispose.family<List<EmailMessage>, MailFolder>((ref, folder) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  if (!folder.readsInbox) return const [];

  var query = supabase.from('taskmail_email_messages').select().eq('user_id', user.id);

  final category = folder.aiCategory;
  if (category != null) {
    query = query.eq('ai_category', category.dbValue);
  }

  final rows = await query.order('received_at', ascending: false).limit(100);

  return (rows as List).map((e) => EmailMessage.fromJson(e as Map<String, dynamic>)).toList();
});

/// A Bejövő mappa levelei — a keskeny (telefon) nézet és a levél-részlet
/// képernyő használja, ahol nincs mappaválasztó.
final inboxMessagesProvider = FutureProvider.autoDispose<List<EmailMessage>>(
  (ref) => ref.watch(mailboxMessagesProvider(MailFolder.inbox).future),
);

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
