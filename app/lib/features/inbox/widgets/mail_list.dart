import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/mail_folder.dart';
import '../inbox_controller.dart';
import 'mail_row.dart';

/// A kiválasztott mappa levéllistája.
class MailList extends ConsumerWidget {
  const MailList({super.key, required this.folder});

  final MailFolder folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messagesAsync = ref.watch(mailboxMessagesProvider(folder));

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(mailboxMessagesProvider(folder)),
      child: messagesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorState(message: '$err'),
        data: (messages) {
          if (messages.isEmpty) return _EmptyState(folder: folder);
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
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.folder});

  final MailFolder folder;

  @override
  Widget build(BuildContext context) {
    final (emoji, title, hint) = switch (folder) {
      MailFolder.inbox => (
          '📭',
          'Még nincs csatlakoztatott postafiókod',
          'Kösd össze a Gmail vagy Outlook fiókodat a Fiókok fülön.',
        ),
      MailFolder.drafts => (
          '📝',
          'Nincs piszkozatod',
          'A megkezdett levelek itt fognak megjelenni.',
        ),
      MailFolder.sent => (
          '📮',
          'Még nem küldtél levelet',
          'A TaskMail-ből küldött levelek itt gyűlnek.',
        ),
      _ => (
          '🗂️',
          'Nincs levél ebben a kategóriában',
          'Az AI ide sorolja majd a megfelelő leveleket.',
        ),
    };

    // Görgethetőnek kell maradnia, különben a lehúzásos frissítés nem indul.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 48)),
                  const SizedBox(height: 12),
                  Text(title, textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
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
