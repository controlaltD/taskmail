import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/taskmail_task.dart';
import '../auth/auth_controller.dart';
import 'board_repository.dart';
import 'task_card.dart';
import 'task_editor_sheet.dart';

class BoardScreen extends ConsumerWidget {
  const BoardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardAsync = ref.watch(defaultBoardProvider);
    final tasksAsync = ref.watch(boardTasksProvider);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Board'),
        actions: [
          tasksAsync.maybeWhen(
            data: (tasks) {
              final archivedCount = tasks.where((t) => t.isArchived).length;
              if (archivedCount == 0) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Archivált kártyák',
                onPressed: () => _showArchivedSheet(context, ref, tasks.where((t) => t.isArchived).toList()),
                icon: Badge(label: Text('$archivedCount'), child: const Icon(Icons.archive_outlined)),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: boardAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Hiba: $e')),
        data: (board) => tasksAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Hiba: $e')),
          data: (tasks) {
            final active = tasks.where((t) => !t.isArchived).toList();
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final column in TaskColumn.values)
                    _BoardColumn(
                      column: column,
                      tasks: active.where((t) => t.column == column).toList(),
                      boardId: board.id,
                      userId: user?.id ?? '',
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _showArchivedSheet(BuildContext context, WidgetRef ref, List<TaskMailTask> archived) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text('Archivált kártyák', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final task in archived)
              ListTile(
                title: Text(task.title),
                subtitle: Text(task.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.undo_rounded),
                      tooltip: 'Visszaállítás',
                      onPressed: () => ref.read(boardRepositoryProvider).setArchived(task.id, false),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppColors.priorityUrgent),
                      tooltip: 'Végleges törlés',
                      onPressed: () => ref.read(boardRepositoryProvider).deleteTask(task.id),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BoardColumn extends ConsumerStatefulWidget {
  const _BoardColumn({required this.column, required this.tasks, required this.boardId, required this.userId});

  final TaskColumn column;
  final List<TaskMailTask> tasks;
  final String boardId;
  final String userId;

  @override
  ConsumerState<_BoardColumn> createState() => _BoardColumnState();
}

class _BoardColumnState extends ConsumerState<_BoardColumn> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DragTarget<TaskMailTask>(
      onWillAcceptWithDetails: (details) {
        setState(() => _hovering = true);
        return details.data.column != widget.column;
      },
      onLeave: (_) => setState(() => _hovering = false),
      onAcceptWithDetails: (details) {
        setState(() => _hovering = false);
        ref.read(boardRepositoryProvider).moveTask(details.data.id, widget.column);
      },
      builder: (context, candidate, rejected) => Container(
        width: 280,
        margin: const EdgeInsets.only(right: 16),
        padding: const EdgeInsets.all(10),
        constraints: const BoxConstraints(minHeight: 500),
        decoration: BoxDecoration(
          color: _hovering
              ? AppColors.primary.withValues(alpha: 0.08)
              : (isDark ? AppColors.surfaceDark : AppColors.surfaceLight2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(widget.column.icon, style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 6),
                Text(widget.column.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${widget.tasks.length}', style: const TextStyle(fontSize: 10)),
                ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add_rounded, size: 20),
                  onPressed: () => showTaskEditorSheet(
                    context,
                    ref: ref,
                    boardId: widget.boardId,
                    userId: widget.userId,
                    initialColumn: widget.column,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final task in widget.tasks)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Draggable<TaskMailTask>(
                  data: task,
                  feedback: SizedBox(
                    width: 260,
                    child: TaskCard(task: task, onTap: () {}, dragging: true),
                  ),
                  childWhenDragging: Opacity(
                    opacity: 0.3,
                    child: TaskCard(task: task, onTap: () {}),
                  ),
                  child: TaskCard(
                    task: task,
                    onTap: () => showTaskEditorSheet(
                      context,
                      ref: ref,
                      task: task,
                      boardId: widget.boardId,
                      userId: widget.userId,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
