import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/email_account.dart';
import '../auth/auth_controller.dart';
import '../board/board_repository.dart';
import 'accounts_repository.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(connectedAccountsProvider);
    final venuesAsync = ref.watch(serveosVenuesProvider);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Fiókok')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (user != null) ...[
            Text('Bejelentkezve mint', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(user.email ?? user.id, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => ref.read(authControllerProvider).signOut(),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Kijelentkezés'),
            ),
            const Divider(height: 32),
          ],
          Text('Csatlakoztatott postafiókok', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          accountsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Hiba: $e'),
            data: (accounts) => Column(
              children: [
                for (final account in accounts) _AccountTile(account: account),
                if (accounts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Még nincs csatlakoztatott fiókod.', style: TextStyle(color: Colors.grey)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await ref.read(accountsRepositoryProvider).connectGmail();
                    if (context.mounted && !ok) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Nem sikerült a Gmail összekötése.')));
                    }
                  },
                  icon: const Icon(Icons.mail_outline_rounded),
                  label: const Text('Gmail'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await ref.read(accountsRepositoryProvider).connectOutlook();
                    if (context.mounted && !ok) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Nem sikerült az Outlook összekötése.')));
                    }
                  },
                  icon: const Icon(Icons.alternate_email_rounded),
                  label: const Text('Outlook'),
                ),
              ),
            ],
          ),
          const Divider(height: 40),
          Text('ServeOS venue kapcsolat', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'A board kártyáid ezekbe a venue-kba küldheted át a ServeOS Kanban táblájára.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 8),
          venuesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Hiba: $e'),
            data: (venues) {
              if (venues.isEmpty) {
                return const Text(
                  'Nincs venue-hoz kötve a fiókod. Kérd meg az admint, hogy kössön össze '
                  'egy venue-val a ServeOS admin panelen.',
                  style: TextStyle(color: Colors.grey),
                );
              }
              return Column(
                children: [
                  for (final v in venues)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.storefront_rounded, color: AppColors.primary),
                      title: Text(v.name),
                      subtitle: Text(v.role),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AccountTile extends ConsumerWidget {
  const _AccountTile({required this.account});

  final EmailAccount account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusColor = switch (account.syncStatus) {
      SyncStatus.ok => AppColors.priorityLow,
      SyncStatus.error => AppColors.priorityUrgent,
      SyncStatus.pending => Colors.grey,
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        account.provider == EmailProvider.gmail ? Icons.mail_outline_rounded : Icons.alternate_email_rounded,
        color: AppColors.primary,
      ),
      title: Text(account.emailAddress),
      subtitle: Text(account.provider.label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: statusColor),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: () => ref.read(accountsRepositoryProvider).disconnect(account.id),
          ),
        ],
      ),
    );
  }
}
