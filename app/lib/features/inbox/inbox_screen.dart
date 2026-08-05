import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'inbox_controller.dart';
import 'widgets/mail_row.dart';

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
            // A sorok maguk rajzolják az elválasztójukat, mert kinyitva a
            // levéltartalom is a soron belülre kerül.
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: messages.length,
              itemBuilder: (context, i) => MailRow(message: messages[i]),
            );
          },
        ),
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
