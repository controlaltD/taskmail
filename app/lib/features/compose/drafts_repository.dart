import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_client.dart';
import '../../models/email_draft.dart';
import '../auth/auth_controller.dart';

/// A megkezdett, még el nem küldött levelek.
final draftsProvider = FutureProvider.autoDispose<List<EmailDraft>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];

  final rows = await supabase
      .from('taskmail_drafts')
      .select()
      .eq('user_id', user.id)
      .eq('status', 'draft')
      .order('updated_at', ascending: false)
      .limit(100);

  return (rows as List).map((e) => EmailDraft.fromJson(e as Map<String, dynamic>)).toList();
});

/// A piszkozat nem tartalmaz titkot és nem nyúl tokenhez, ezért a kliens
/// közvetlenül írja, RLS mögött — nem kell hozzá Edge Function. (A küldés
/// viszont továbbra is szerveroldalon megy át, ott van a jogosultság-
/// ellenőrzés.)
class DraftsRepository {
  const DraftsRepository(this.ref);

  final Ref ref;

  /// Létrehoz vagy frissít egy piszkozatot, és visszaadja az azonosítóját.
  /// Az első mentés után ugyanazt a sort írjuk tovább, nem gyűjtünk
  /// félkész másolatokat minden billentyűleütésre.
  Future<String?> save({
    String? draftId,
    String? accountId,
    String? inReplyToMessageId,
    required List<String> to,
    required String subject,
    required String bodyText,
  }) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return null;

    final payload = {
      'user_id': user.id,
      'account_id': accountId,
      'in_reply_to_message_id': inReplyToMessageId,
      'to_addresses': to,
      'subject': subject,
      'body_text': bodyText,
    };

    if (draftId == null) {
      final row = await supabase.from('taskmail_drafts').insert(payload).select('id').single();
      ref.invalidate(draftsProvider);
      return row['id'] as String;
    }

    await supabase.from('taskmail_drafts').update(payload).eq('id', draftId);
    ref.invalidate(draftsProvider);
    return draftId;
  }

  Future<void> delete(String draftId) async {
    await supabase.from('taskmail_drafts').delete().eq('id', draftId);
    ref.invalidate(draftsProvider);
  }

  /// Elküldés után a piszkozatot nem töröljük, hanem megjelöljük — így a
  /// küldés utólag is visszakövethető.
  Future<void> markSent(String draftId, String? sentMessageId) async {
    await supabase
        .from('taskmail_drafts')
        .update({'status': 'sent', 'sent_message_id': sentMessageId})
        .eq('id', draftId);
    ref.invalidate(draftsProvider);
  }
}

final draftsRepositoryProvider = Provider((ref) => DraftsRepository(ref));
