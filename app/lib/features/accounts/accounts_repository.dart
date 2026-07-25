import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../../core/config/env.dart';
import '../../core/supabase/supabase_client.dart';
import '../../models/email_account.dart';
import '../auth/auth_controller.dart';

/// A custom URL scheme, amit az OAuth callback Edge Function végül visszahív
/// (lásd `supabase/functions/gmail-oauth-callback`). Regisztrálva az
/// Android/iOS/macOS platform manifestekben.
const _callbackScheme = 'hu.serveos.taskmail';

final connectedAccountsProvider = FutureProvider.autoDispose<List<EmailAccount>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  final rows = await supabase.from('taskmail_email_accounts').select().eq('user_id', user.id);
  return (rows as List).map((e) => EmailAccount.fromJson(e as Map<String, dynamic>)).toList();
});

class AccountsRepository {
  AccountsRepository(this.ref);

  final Ref ref;

  String get _functionsBase => '${Env.supabaseUrl}/functions/v1';

  Future<bool> connectGmail() async {
    final session = supabase.auth.currentSession;
    if (session == null) return false;

    final callbackUrl = '$_functionsBase/gmail-oauth-callback';
    final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': Env.googleClientId,
      'redirect_uri': callbackUrl,
      'response_type': 'code',
      'access_type': 'offline',
      'prompt': 'consent',
      'scope': 'https://www.googleapis.com/auth/gmail.readonly',
      'state': session.accessToken,
    });

    final result = await FlutterWebAuth2.authenticate(url: authUrl.toString(), callbackUrlScheme: _callbackScheme);
    final status = Uri.parse(result).queryParameters['status'];
    ref.invalidate(connectedAccountsProvider);
    return status == 'ok';
  }

  Future<bool> connectOutlook() async {
    final session = supabase.auth.currentSession;
    if (session == null) return false;

    final callbackUrl = '$_functionsBase/outlook-oauth-callback';
    final authUrl = Uri.https('login.microsoftonline.com', '/common/oauth2/v2.0/authorize', {
      'client_id': Env.microsoftClientId,
      'redirect_uri': callbackUrl,
      'response_type': 'code',
      'response_mode': 'query',
      'scope': 'offline_access Mail.Read',
      'state': session.accessToken,
    });

    final result = await FlutterWebAuth2.authenticate(url: authUrl.toString(), callbackUrlScheme: _callbackScheme);
    final status = Uri.parse(result).queryParameters['status'];
    ref.invalidate(connectedAccountsProvider);
    return status == 'ok';
  }

  Future<void> disconnect(String accountId) async {
    await supabase.from('taskmail_email_accounts').delete().eq('id', accountId);
    ref.invalidate(connectedAccountsProvider);
  }
}

final accountsRepositoryProvider = Provider((ref) => AccountsRepository(ref));
