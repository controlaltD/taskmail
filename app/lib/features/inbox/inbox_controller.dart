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
