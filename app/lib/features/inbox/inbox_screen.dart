import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/email_message.dart';
import 'inbox_controller.dart';

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messagesAsync = ref.watch(inboxMessagesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Postafiók')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(inboxMessagesProvider),
        child: messagesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => _ErrorState(message: '$err'),
          data: (messages) {
            if (messages.isEmpty) return const _EmptyState();
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: messages.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) => _EmailTile(message: messages[i]),
            );
          },
        ),
      ),
    );
  }
}

class _EmailTile extends StatelessWidget {
  const _EmailTile({required this.message});

  final EmailMessage message;

  @override
  Widget build(BuildContext context) {
    final category = message.aiCategory;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      leading: CircleAvatar(
        backgroundColor: AppColors.primary.withValues(alpha: 0.12),
        child: Text(
          (message.fromName?.isNotEmpty == true ? message.fromName! : message.fromAddress)
              .substring(0, 1)
              .toUpperCase(),
          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(
        message.subject,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: message.isRead ? FontWeight.normal : FontWeight.w700),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.fromName ?? message.fromAddress,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (message.aiSummary != null) ...[
            const SizedBox(height: 2),
            Text(
              message.aiSummary!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ],
      ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(DateFormat('MM.dd HH:mm').format(message.receivedAt), style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 6),
          if (category != null)
            Chip(
              label: Text(category.label),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('📭', style: TextStyle(fontSize: 48)),
            SizedBox(height: 12),
            Text('Még nincs csatlakoztatott postafiókod'),
            SizedBox(height: 4),
            Text(
              'Kösd össze a Gmail vagy Outlook fiókodat a Fiókok fülön.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text('Hiba történt: $message', textAlign: TextAlign.center),
      ),
    );
  }
}
