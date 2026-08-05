import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/mail_folder.dart';
import '../mail_layout_controller.dart';

const double kSidebarWidth = 208;
const double kSidebarCollapsedWidth = 60;

/// Bal oldali mappalista. Összecsukva csak az ikonok látszanak, hogy a
/// levéllista több helyet kapjon.
class MailSidebar extends ConsumerWidget {
  const MailSidebar({super.key, this.iconsOnly = false});

  /// Fixen ikonsáv módban jelenik-e meg. Közepes (tablet) szélességen ez a
  /// mód fut: a teljes mappalista elvenné a helyet a levelektől, viszont a
  /// mappák így is egy koppintásra elérhetők maradnak, fiók nélkül.
  final bool iconsOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed = iconsOnly || ref.watch(sidebarCollapsedProvider);
    final selected = ref.watch(selectedFolderProvider);
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: collapsed ? kSidebarCollapsedWidth : kSidebarWidth,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5))),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ComposeButton(collapsed: collapsed),
            const SizedBox(height: 6),
            if (iconsOnly)
              const SizedBox(height: 8)
            else
              Align(
                alignment: collapsed ? Alignment.center : Alignment.centerRight,
                child: IconButton(
                  tooltip: collapsed ? 'Mappák megnyitása' : 'Mappák összecsukása',
                  iconSize: 18,
                  icon: Icon(collapsed ? Icons.chevron_right_rounded : Icons.chevron_left_rounded),
                  onPressed: () =>
                      ref.read(sidebarCollapsedProvider.notifier).state = !collapsed,
                ),
              ),
            const SizedBox(height: 4),
            _FolderTile(
              folder: MailFolder.inbox,
              icon: Icons.inbox_rounded,
              selected: selected == MailFolder.inbox,
              collapsed: collapsed,
            ),
            if (!collapsed) const _SectionLabel('AI kategóriák'),
            for (final folder in const [
              MailFolder.urgent,
              MailFolder.task,
              MailFolder.newsletter,
              MailFolder.other,
            ])
              _FolderTile(
                folder: folder,
                icon: _categoryIcon(folder),
                selected: selected == folder,
                collapsed: collapsed,
                indented: !collapsed,
              ),
            const SizedBox(height: 8),
            Divider(color: theme.dividerColor.withValues(alpha: 0.5)),
            const SizedBox(height: 4),
            _FolderTile(
              folder: MailFolder.drafts,
              icon: Icons.edit_note_rounded,
              selected: selected == MailFolder.drafts,
              collapsed: collapsed,
            ),
            _FolderTile(
              folder: MailFolder.sent,
              icon: Icons.send_rounded,
              selected: selected == MailFolder.sent,
              collapsed: collapsed,
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposeButton extends StatelessWidget {
  const _ComposeButton({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/compose'),
        child: Tooltip(
          message: collapsed ? 'Új levél' : '',
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 12, vertical: 10),
            child: Row(
              mainAxisAlignment:
                  collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                const Icon(Icons.add_rounded, size: 17, color: Colors.white),
                if (!collapsed) ...[
                  const SizedBox(width: 8),
                  const Text(
                    'Új levél',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

IconData _categoryIcon(MailFolder folder) => switch (folder) {
      MailFolder.urgent => Icons.priority_high_rounded,
      MailFolder.task => Icons.check_circle_outline_rounded,
      MailFolder.newsletter => Icons.newspaper_rounded,
      _ => Icons.mail_outline_rounded,
    };

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
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

class _FolderTile extends ConsumerWidget {
  const _FolderTile({
    required this.folder,
    required this.icon,
    required this.selected,
    required this.collapsed,
    this.indented = false,
  });

  final MailFolder folder;
  final IconData icon;
  final bool selected;
  final bool collapsed;
  final bool indented;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = selected ? AppColors.primary : Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? AppColors.primary.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => ref.read(selectedFolderProvider.notifier).state = folder,
          child: Tooltip(
            message: collapsed ? folder.title : '',
            child: Padding(
              padding: EdgeInsets.fromLTRB(collapsed ? 0 : (indented ? 20 : 10), 9, 10, 9),
              child: Row(
                mainAxisAlignment:
                    collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                children: [
                  Icon(icon, size: 17, color: color.withValues(alpha: selected ? 1 : 0.75)),
                  if (!collapsed) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        folder.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
