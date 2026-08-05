import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/email_message.dart';
import '../../compose/compose_controller.dart';
import '../ai_chat_controller.dart';
import '../inbox_controller.dart';
import '../mail_layout_controller.dart';

const double kAiPanelWidth = 268;
const double kAiPanelCollapsedWidth = 52;

/// Jobb oldali AI panel: a megnyitott levélhez tartozó javaslatok és a róla
/// szóló beszélgetés.
///
/// Széles nézeten önálló hasábként ül a levéllista mellett; keskenyebb
/// nézeteken fiókként (`endDrawer`) nyílik, hogy ne szorítsa össze a listát.
class AiPanel extends ConsumerWidget {
  const AiPanel({super.key, this.inDrawer = false});

  /// Fiókban jelenik-e meg. Ilyenkor nincs összecsukott állapot: a fiók
  /// megnyitása maga a "kinyitás".
  final bool inDrawer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final collapsed = !inDrawer && ref.watch(aiPanelCollapsedProvider);
    final message = ref.watch(expandedMessageProvider);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(collapsed ? 0 : 16, 12, collapsed ? 0 : 8, 4),
          child: Row(
            mainAxisAlignment:
                collapsed ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween,
            children: [
              if (!collapsed)
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [AppColors.primary, AppColors.accent],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('AI', style: theme.textTheme.titleSmall),
                  ],
                ),
              if (inDrawer)
                IconButton(
                  tooltip: 'Bezárás',
                  iconSize: 18,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              else
                IconButton(
                  tooltip: collapsed ? 'AI panel megnyitása' : 'AI panel összecsukása',
                  iconSize: 18,
                  icon: Icon(
                    collapsed ? Icons.auto_awesome_rounded : Icons.chevron_right_rounded,
                  ),
                  onPressed: () =>
                      ref.read(aiPanelCollapsedProvider.notifier).state = !collapsed,
                ),
            ],
          ),
        ),
        if (!collapsed)
          Expanded(
            child: message == null
                ? const _IdleState()
                : _MessageAiView(message: message),
          ),
      ],
    );

    if (inDrawer) return SafeArea(child: content);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: collapsed ? kAiPanelCollapsedWidth : kAiPanelWidth,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5))),
      ),
      child: content,
    );
  }
}

class _IdleState extends StatelessWidget {
  const _IdleState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Text(
          'Nyiss meg egy levelet, és itt jelennek meg a hozzá tartozó javaslatok.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ),
    );
  }
}

class _MessageAiView extends ConsumerWidget {
  const _MessageAiView({required this.message});

  final EmailMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionLabel('Azonnali javaslatok'),
                _InstantSuggestions(message: message),
                const SizedBox(height: 18),
                const _SectionLabel('Kérdezz a levélről'),
                _ChatThread(messageId: message.id),
              ],
            ),
          ),
        ),
        _ChatInput(messageId: message.id),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }
}

/// A kategória és az összefoglaló a szinkron során már elkészült — ezek
/// megjelenítése nem kerül újabb AI-hívásba, ezért azonnal ott vannak.
class _InstantSuggestions extends ConsumerWidget {
  const _InstantSuggestions({required this.message});

  final EmailMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requested = ref.watch(quickReplyRequestedProvider(message.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (message.aiSummary != null)
          _SuggestionCard(
            title: '📄 Összefoglaló',
            body: message.aiSummary!,
          ),
        if (message.aiCategory == AiCategory.task)
          const _SuggestionCard(
            title: '📋 Teendőnek tűnik',
            body: 'Az AI konkrét elvégzendő feladatot ismert fel ebben a levélben — '
                'a Board fülön megtalálod a belőle készült kártyát.',
          ),
        // A javaslat csak kifejezett kérésre készül el: a provider figyelése
        // önmagában elindítaná a hívást, ezért egy kapcsoló mögé tesszük.
        if (!requested)
          _SuggestionCard(
            title: '✍️ Válaszjavaslat',
            body: 'Az AI megfogalmaz egy válasz-tervezetet erre a levélre.',
            action: _SmallButton(
              label: 'Javaslat kérése',
              onPressed: () =>
                  ref.read(quickReplyRequestedProvider(message.id).notifier).state = true,
            ),
          )
        else
          _QuickReplyResult(messageId: message.id),
      ],
    );
  }
}

class _QuickReplyResult extends ConsumerWidget {
  const _QuickReplyResult({required this.messageId});

  final String messageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(quickReplyProvider(messageId)).when(
          loading: () => const _CardShell(
            child: Row(
              children: [
                SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text('Válasz fogalmazása…', style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
          error: (err, _) => _CardShell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  err is AiException ? err.message : 'A javaslat nem készült el.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 6),
                _SmallButton(
                  label: 'Újra',
                  onPressed: () => ref.invalidate(quickReplyProvider(messageId)),
                ),
              ],
            ),
          ),
          data: (reply) => _SuggestionCard(
            title: '✍️ Válaszjavaslat',
            body: reply.bodyText,
            // A javaslat nem megy el magától: a levélíróba töltjük, hogy a
            // felhasználó átolvashassa és szerkeszthesse küldés előtt.
            action: _SmallButton(
              label: 'Válasz megnyitása',
              onPressed: () {
                final message = ref.read(expandedMessageProvider);
                if (message == null) return;
                context.push(
                  '/compose',
                  extra: ComposeDraft.replyTo(message, bodyText: reply.bodyText),
                );
              },
            ),
          ),
        );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Theme.of(context).chipTheme.backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.title, required this.body, this.action});

  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(
            body,
            style: TextStyle(fontSize: 10.5, height: 1.5, color: Colors.grey.shade700),
          ),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatThread extends ConsumerWidget {
  const _ChatThread({required this.messageId});

  final String messageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(aiChatControllerProvider(messageId));

    if (state.turns.isEmpty && state.error == null) {
      return Text(
        'Például: „Foglald össze 2 mondatban", „Mi a határidő?"',
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final turn in state.turns) _ChatBubble(turn: turn),
        if (state.sending)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              state.error!,
              style: const TextStyle(fontSize: 10.5, color: AppColors.priorityUrgent),
            ),
          ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.turn});

  final ChatTurn turn;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: turn.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 220),
        decoration: BoxDecoration(
          color: turn.fromUser ? AppColors.primary : Theme.of(context).chipTheme.backgroundColor,
          borderRadius: BorderRadius.circular(13).copyWith(
            bottomRight: turn.fromUser ? const Radius.circular(4) : null,
            bottomLeft: turn.fromUser ? null : const Radius.circular(4),
          ),
        ),
        child: SelectableText(
          turn.text,
          style: TextStyle(
            fontSize: 11,
            height: 1.5,
            color: turn.fromUser ? Colors.white : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _ChatInput extends ConsumerStatefulWidget {
  const _ChatInput({required this.messageId});

  final String messageId;

  @override
  ConsumerState<_ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends ConsumerState<_ChatInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    ref.read(aiChatControllerProvider(widget.messageId).notifier).send(text);
  }

  @override
  Widget build(BuildContext context) {
    final sending = ref.watch(aiChatControllerProvider(widget.messageId)).sending;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: !sending,
              style: const TextStyle(fontSize: 11.5),
              decoration: const InputDecoration(
                hintText: 'Írj az AI-nak erről a levélről…',
                hintStyle: TextStyle(fontSize: 11),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            iconSize: 18,
            onPressed: sending ? null : _send,
            icon: const Icon(Icons.send_rounded, color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}
