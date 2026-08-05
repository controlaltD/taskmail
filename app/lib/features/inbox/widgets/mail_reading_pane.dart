import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../models/email_message.dart';
import '../../compose/compose_controller.dart';
import '../inbox_controller.dart';

/// A kinyitott levél tartalma. A törzs letöltése itt indul el, amikor a
/// widget először megjelenik.
class MailReadingPane extends ConsumerWidget {
  const MailReadingPane({super.key, required this.message});

  final EmailMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bodyAsync = ref.watch(messageBodyProvider(message));

    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 4, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 12),
          bodyAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (err, _) => _ErrorBody(
              message: err is MessageBodyException
                  ? err.message
                  : 'A levél tartalmát nem sikerült betölteni.',
              onRetry: () => ref.invalidate(messageBodyProvider(message)),
            ),
            data: (loaded) => _LoadedBody(message: loaded),
          ),
        ],
      ),
    );
  }
}

class _LoadedBody extends StatelessWidget {
  const _LoadedBody({required this.message});

  final EmailMessage message;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      message.fromName != null
          ? '${message.fromName} <${message.fromAddress}>'
          : message.fromAddress,
      if (message.toAddresses.isNotEmpty) 'Címzett: ${message.toAddresses.join(', ')}',
      if (message.ccAddresses.isNotEmpty) 'Másolat: ${message.ccAddresses.join(', ')}',
      DateFormat('yyyy.MM.dd. HH:mm').format(message.receivedAt),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          meta.join(' · '),
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 14),
        SelectableText(
          _displayBody(message),
          style: const TextStyle(fontSize: 13.5, height: 1.6),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => context.push(
            '/compose',
            extra: ComposeDraft.replyTo(message),
          ),
          icon: const Icon(Icons.reply_rounded, size: 16),
          label: const Text('Válasz'),
        ),
      ],
    );
  }
}

/// Egyelőre sima szövegként jelenítjük meg a levelet. Ha csak HTML változat
/// érkezett, abból nyerünk ki olvasható szöveget — idegen HTML biztonságos
/// rendereléséhez (követő pixelek, beágyazott szkriptek) külön megoldás kell,
/// ami nem minden célplatformon támogatott egyformán.
String _displayBody(EmailMessage message) {
  final text = message.bodyText;
  if (text != null && text.trim().isNotEmpty) return text.trim();

  final html = message.bodyHtml;
  if (html != null && html.trim().isNotEmpty) return _stripHtml(html);

  return '(A levélnek nincs szöveges tartalma.)';
}

String _stripHtml(String html) {
  return html
      // A fejrészben lévő stílus/szkript blokkok tartalma nem olvasnivaló.
      .replaceAll(RegExp(r'<(script|style)[^>]*>[\s\S]*?</\1>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(message, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
        ),
        TextButton(onPressed: onRetry, child: const Text('Újra')),
      ],
    );
  }
}
