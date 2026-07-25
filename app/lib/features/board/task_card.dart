import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/taskmail_task.dart';

/// A ServeOS `FeladatokBoard` kártyájának vizuális párja: ugyanazok az
/// információk (label, priority, cím, leírás, felelősök, határidő, checklist
/// progress, komment szám), TaskMail-saját színpalettával.
class TaskCard extends StatelessWidget {
  const TaskCard({super.key, required this.task, required this.onTap, this.dragging = false});

  final TaskMailTask task;
  final VoidCallback onTap;
  final bool dragging;

  Color _labelColor(TaskLabel l) => switch (l) {
        TaskLabel.urgent => AppColors.labelUrgent,
        TaskLabel.ops => AppColors.labelOps,
        TaskLabel.kitchen => AppColors.labelKitchen,
        TaskLabel.service => AppColors.labelService,
        TaskLabel.admin => AppColors.labelAdmin,
        TaskLabel.event => AppColors.labelEvent,
      };

  Color _priorityColor(TaskPriority p) => switch (p) {
        TaskPriority.urgent => AppColors.priorityUrgent,
        TaskPriority.high => AppColors.priorityHigh,
        TaskPriority.medium => AppColors.priorityMedium,
        TaskPriority.low => AppColors.priorityLow,
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark2 : Colors.white;
    final labelColor = _labelColor(task.label);
    final priorityColor = _priorityColor(task.priority);
    final isDue = task.dueDate != null && task.dueDate!.isBefore(DateTime.now());
    final checklistDone = task.checklist.where((c) => c.done).length;

    return Material(
      color: surface,
      elevation: dragging ? 8 : 0,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: labelColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: labelColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      task.label.title,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: labelColor),
                    ),
                  ),
                  const Spacer(),
                  if (task.isSyncedToServeos)
                    const Tooltip(
                      message: 'ServeOS-be szinkronizálva',
                      child: Icon(Icons.sync_rounded, size: 14, color: AppColors.priorityLow),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                task.title,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (task.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  task.description,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(task.priority.label, style: TextStyle(fontSize: 10, color: priorityColor)),
                  const Spacer(),
                  if (task.dueDate != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDue ? AppColors.priorityUrgent.withValues(alpha: 0.1) : null,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        DateFormat('MMM d').format(task.dueDate!),
                        style: TextStyle(
                          fontSize: 10,
                          color: isDue ? AppColors.priorityUrgent : Colors.grey,
                        ),
                      ),
                    ),
                ],
              ),
              if (task.checklist.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: checklistDone / task.checklist.length,
                          minHeight: 3,
                          backgroundColor: Colors.grey.withValues(alpha: 0.2),
                          valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('$checklistDone/${task.checklist.length}', style: const TextStyle(fontSize: 9)),
                  ],
                ),
              ],
              if (task.assignees.isNotEmpty || task.comments.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (task.assignees.isNotEmpty)
                      Expanded(
                        child: Text(
                          task.assignees.join(', '),
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (task.comments.isNotEmpty)
                      Text('💬 ${task.comments.length}', style: const TextStyle(fontSize: 9)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
