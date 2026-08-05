import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/email_message.dart';
import '../inbox_controller.dart';
import 'mail_reading_pane.dart';

/// Egy levél a listában. Kattintásra helyben kinyílik, és megmutatja a teljes
/// üzenetet — nincs külön képernyőre navigálás.
class MailRow extends ConsumerWidget {
  const MailRow({super.key, required this.message});

  final EmailMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expandedId = ref.watch(expandedMessageIdProvider);
    final isExpanded = expandedId == message.id;

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            // Egyszerre csak egy levél van nyitva: az újabb megnyitása bezárja
            // az előzőt, így a lista nem esik szét sok nyitott blokkra.
            onTap: () => ref.read(expandedMessageIdProvider.notifier).state =
                isExpanded ? null : message.id,
            child: _Header(message: message, isExpanded: isExpanded),
          ),
          if (isExpanded) MailReadingPane(message: message),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.message, required this.isExpanded});

  final EmailMessage message;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    final displayName = message.fromName?.isNotEmpty == true
        ? message.fromName!
        : message.fromAddress;
    final initial = displayName.isNotEmpty ? displayName.substring(0, 1).toUpperCase() : '?';

    return Container(
      color: isExpanded ? Theme.of(context).colorScheme.surface : null,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            child: Text(
              initial,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: message.isRead ? FontWeight.w500 : FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('MM.dd HH:mm').format(message.receivedAt),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  message.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: message.isRead ? FontWeight.normal : FontWeight.w600,
                  ),
                ),
                // Összecsukva az AI összefoglaló segít eldönteni, kell-e
                // egyáltalán megnyitni. Nyitva viszont fölösleges: ott van
                // alatta maga a levél.
                if (!isExpanded && message.aiSummary != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    message.aiSummary!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                  ),
                ],
                if (message.aiCategory != null) ...[
                  const SizedBox(height: 6),
                  _CategoryChip(label: message.aiCategory!.label),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).chipTheme.backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}
