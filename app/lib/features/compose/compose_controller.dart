import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_client.dart';
import '../../models/email_account.dart';
import '../../models/email_message.dart';
import '../../models/sent_message.dart';
import '../auth/auth_controller.dart';

/// A levélíráshoz átadott kezdőértékek. Válasznál a címzett, a tárgy és a
/// megválaszolt levél azonosítója már ki van töltve.
class ComposeDraft {
  const ComposeDraft({
    this.to = const [],
    this.subject = '',
    this.bodyText = '',
    this.inReplyToMessageId,
    this.accountId,
  });

  final List<String> to;
  final String subject;
  final String bodyText;
  final String? inReplyToMessageId;
  final String? accountId;

  /// Válasz összeállítása egy beérkezett levélre.
  factory ComposeDraft.replyTo(EmailMessage message, {String bodyText = ''}) {
    final subject = message.subject.toLowerCase().startsWith('re:')
        ? message.subject
        : 'Re: ${message.subject}';
    return ComposeDraft(
      to: [message.fromAddress],
      subject: subject,
      bodyText: bodyText,
      inReplyToMessageId: message.id,
      accountId: message.accountId,
    );
  }
}

/// A küldésre alkalmas fiókok. Csak azok, amelyek megkapták a küldési jogot —
/// a többivel a hívás úgyis elutasításba futna a szerveren.
final sendableAccountsProvider = FutureProvider.autoDispose<List<EmailAccount>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];

  final rows = await supabase.from('taskmail_email_accounts').select().eq('user_id', user.id);
  return (rows as List)
      .map((e) => EmailAccount.fromJson(e as Map<String, dynamic>))
      .where((account) => account.scopeTier.canSend)
      .toList();
});

/// Van-e egyáltalán összekötött fiók — ha van, de egyik sem küldhet, más
/// üzenetet érdemes mutatni, mint ha egy sincs.
final hasAnyAccountProvider = FutureProvider.autoDispose<bool>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return false;
  final rows = await supabase.from('taskmail_email_accounts').select('id').eq('user_id', user.id);
  return (rows as List).isNotEmpty;
});

/// Az elküldött levelek listája (az "Elküldött" mappához).
final sentMessagesProvider = FutureProvider.autoDispose<List<SentMessage>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];

  final rows = await supabase
      .from('taskmail_sent_messages')
      .select()
      .eq('user_id', user.id)
      .order('sent_at', ascending: false)
      .limit(100);

  return (rows as List).map((e) => SentMessage.fromJson(e as Map<String, dynamic>)).toList();
});

class SendException implements Exception {
  const SendException(this.message);
  final String message;
  @override
  String toString() => message;
}

String sendErrorMessage(String? code) => switch (code) {
      'scope_upgrade_required' =>
        'Ebből a fiókból nem lehet küldeni. A Fiókok fülön bővítsd a jogosultságot.',
      'auth_expired' => 'A postafiók kapcsolata lejárt. Kösd össze újra a Fiókok fülön.',
      'account_not_connected' => 'Ehhez a fiókhoz nincs élő kapcsolat.',
      'rate_limited' => 'A szolgáltató most nem fogad több levelet. Próbáld újra kicsit később.',
      'invalid_body' => 'Hiányzik a címzett vagy a levél szövege.',
      'not_found' => 'A fiók nem található.',
      _ => 'A levelet nem sikerült elküldeni. Próbáld újra.',
    };

class ComposeRepository {
  const ComposeRepository(this.ref);

  final Ref ref;

  Future<void> send({
    required String accountId,
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    required String subject,
    required String bodyText,
    String? inReplyToMessageId,
  }) async {
    final response = await supabase.functions.invoke('send-email', body: {
      'accountId': accountId,
      'to': to,
      'cc': cc,
      'bcc': bcc,
      'subject': subject,
      'bodyText': bodyText,
      'inReplyToMessageId': inReplyToMessageId,
    });

    final data = response.data as Map?;
    if (data?['sentMessageId'] == null) {
      throw SendException(sendErrorMessage(data?['error'] as String?));
    }

    ref.invalidate(sentMessagesProvider);
  }
}

final composeRepositoryProvider = Provider((ref) => ComposeRepository(ref));
