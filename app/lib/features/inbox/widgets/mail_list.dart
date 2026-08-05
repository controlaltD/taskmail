import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../models/mail_folder.dart';
import '../../compose/compose_controller.dart';
import '../../compose/drafts_repository.dart';
import '../inbox_controller.dart';
import 'mail_row.dart';

/// A kiválasztott mappa levéllistája.
class MailList extends ConsumerWidget {
  const MailList({super.key, required this.folder});

  final MailFolder folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (folder == MailFolder.sent) return const _SentList();
    if (folder == MailFolder.drafts) return const _DraftsList();

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

/// A megkezdett levelek. Egy koppintás visszanyitja a szerkesztőt ott, ahol
/// abbamaradt.
class _DraftsList extends ConsumerWidget {
  const _DraftsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draftsAsync = ref.watch(draftsProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(draftsProvider),
      child: draftsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorState(message: '$err'),
        data: (drafts) {
          if (drafts.isEmpty) return const _EmptyState(folder: MailFolder.drafts);
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: drafts.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final draft = drafts[i];
              final recipients = draft.toAddresses.isEmpty
                  ? 'Nincs címzett'
                  : 'Címzett: ${draft.toAddresses.join(', ')}';
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                onTap: () => context.push('/compose', extra: ComposeDraft.fromSaved(draft)),
                title: Text(
                  draft.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  recipients,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5),
                ),
                trailing: Text(
                  DateFormat('MM.dd HH:mm').format(draft.updatedAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Az elküldött levelek külön táblából jönnek, és nem nyithatók ki: a saját
/// levelünk tartalma teljes egészében megvan, nincs mit utólag letölteni.
class _SentList extends ConsumerWidget {
  const _SentList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sentAsync = ref.watch(sentMessagesProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(sentMessagesProvider),
      child: sentAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorState(message: '$err'),
        data: (messages) {
          if (messages.isEmpty) return const _EmptyState(folder: MailFolder.sent);
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: messages.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final message = messages[i];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                title: Text(
                  message.subject.isEmpty ? '(nincs tárgy)' : message.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Címzett: ${message.toAddresses.join(', ')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5),
                ),
                trailing: Text(
                  DateFormat('MM.dd HH:mm').format(message.sentAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              );
            },
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
