import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

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

  /// Az engedélykérő URL-t a szerver állítja össze (`oauth-start`), és abban
  /// `state`-ként csak egy egyszer felhasználható nonce utazik. Korábban itt
  /// a felhasználó Supabase hozzáférési tokenje került az URL-be, ami a
  /// Google/Microsoft naplóin és a böngésző előzményein keresztül
  /// kiszivárogtatta a munkamenetet.
  Future<bool> _connect(String provider) async {
    final response = await supabase.functions.invoke(
      'oauth-start',
      body: {'provider': provider},
    );

    final authUrl = (response.data as Map?)?['url'] as String?;
    if (authUrl == null) return false;

    final result = await FlutterWebAuth2.authenticate(
      url: authUrl,
      callbackUrlScheme: _callbackScheme,
    );
    final status = Uri.parse(result).queryParameters['status'];
    ref.invalidate(connectedAccountsProvider);
    return status == 'ok';
  }

  Future<bool> connectGmail() => _connect('gmail');

  Future<bool> connectOutlook() => _connect('outlook');

  Future<void> disconnect(String accountId) async {
    await supabase.from('taskmail_email_accounts').delete().eq('id', accountId);
    ref.invalidate(connectedAccountsProvider);
  }
}

final accountsRepositoryProvider = Provider((ref) => AccountsRepository(ref));
