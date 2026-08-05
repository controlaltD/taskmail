import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../inbox_controller.dart';
import '../mail_layout_controller.dart';

const double kAiPanelWidth = 268;
const double kAiPanelCollapsedWidth = 52;

/// Jobb oldali AI panel. A tartalma (javaslatok, chat) a következő fázisban
/// készül el — a helye, a nyit/zár működése és az üres állapot már itt van,
/// hogy az elrendezés véglegesen a helyére kerüljön.
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: ref.watch(expandedMessageIdProvider) == null
                  ? const _IdleState()
                  : const _ComingSoonState(),
            ),
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
    return Center(
      child: Text(
        'Nyiss meg egy levelet, és itt jelennek meg a hozzá tartozó javaslatok.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
    );
  }
}

class _ComingSoonState extends StatelessWidget {
  const _ComingSoonState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Az AI javaslatok és a chat hamarosan itt lesznek elérhetők.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
    );
  }
}
