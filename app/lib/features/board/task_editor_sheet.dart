import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../models/checklist_item.dart';
import '../../models/task_comment.dart';
import '../../models/taskmail_task.dart';
import 'board_repository.dart';
import 'venue_picker_dialog.dart';

const _uuid = Uuid();

/// Kártya létrehozó/szerkesztő bottom sheet — a ServeOS `CardModal` mezőinek
/// megfelelő szerkesztő felület (cím, leírás, oszlop, prioritás, címke,
/// határidő, felelősök, checklist, kommentek), plusz a "Küldés ServeOS-be" akció.
Future<void> showTaskEditorSheet(
  BuildContext context, {
  required WidgetRef ref,
  TaskMailTask? task,
  required String boardId,
  required String userId,
  TaskColumn initialColumn = TaskColumn.todo,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      builder: (context, scrollController) => _TaskEditorContent(
        task: task,
        boardId: boardId,
        userId: userId,
        initialColumn: initialColumn,
        scrollController: scrollController,
      ),
    ),
  );
}

class _TaskEditorContent extends ConsumerStatefulWidget {
  const _TaskEditorContent({
    required this.task,
    required this.boardId,
    required this.userId,
    required this.initialColumn,
    required this.scrollController,
  });

  final TaskMailTask? task;
  final String boardId;
  final String userId;
  final TaskColumn initialColumn;
  final ScrollController scrollController;

  @override
  ConsumerState<_TaskEditorContent> createState() => _TaskEditorContentState();
}

class _TaskEditorContentState extends ConsumerState<_TaskEditorContent> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _assigneeCtrl;
  late final TextEditingController _checklistCtrl;
  late final TextEditingController _commentCtrl;

  late TaskColumn _column;
  late TaskPriority _priority;
  late TaskLabel _label;
  DateTime? _dueDate;
  late List<String> _assignees;
  late List<ChecklistItem> _checklist;
  late List<TaskComment> _comments;
  bool _saving = false;

  bool get _isNew => widget.task == null;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _titleCtrl = TextEditingController(text: t?.title ?? '');
    _descCtrl = TextEditingController(text: t?.description ?? '');
    _assigneeCtrl = TextEditingController();
    _checklistCtrl = TextEditingController();
    _commentCtrl = TextEditingController();
    _column = t?.column ?? widget.initialColumn;
    _priority = t?.priority ?? TaskPriority.medium;
    _label = t?.label ?? TaskLabel.ops;
    _dueDate = t?.dueDate;
    _assignees = List.of(t?.assignees ?? const []);
    _checklist = List.of(t?.checklist ?? const []);
    _comments = List.of(t?.comments ?? const []);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _assigneeCtrl.dispose();
    _checklistCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  void _addAssignee() {
    final value = _assigneeCtrl.text.trim();
    if (value.isEmpty || _assignees.contains(value)) return;
    setState(() {
      _assignees.add(value);
      _assigneeCtrl.clear();
    });
  }

  void _addChecklistItem() {
    final text = _checklistCtrl.text.trim();
    if (text.isEmpty) return;
    final nextId = (_checklist.isEmpty ? 0 : _checklist.map((c) => c.id).reduce((a, b) => a > b ? a : b)) + 1;
    setState(() {
      _checklist.add(ChecklistItem(id: nextId, text: text));
      _checklistCtrl.clear();
    });
  }

  void _addComment() {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    setState(() {
      _comments.add(TaskComment(
        id: now.millisecondsSinceEpoch,
        user: 'Én',
        text: text,
        time: '${two(now.month)}.${two(now.day)} ${two(now.hour)}:${two(now.minute)}',
      ));
      _commentCtrl.clear();
    });
  }

  TaskMailTask _buildTask() {
    final now = DateTime.now();
    return TaskMailTask(
      id: widget.task?.id ?? _uuid.v4(),
      userId: widget.userId,
      boardId: widget.boardId,
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      column: _column,
      priority: _priority,
      label: _label,
      assignees: _assignees,
      dueDate: _dueDate,
      checklist: _checklist,
      comments: _comments,
      sortOrder: widget.task?.sortOrder ?? 0,
      isArchived: widget.task?.isArchived ?? false,
      createdByAi: widget.task?.createdByAi ?? false,
      sourceEmailId: widget.task?.sourceEmailId,
      serveosVenueId: widget.task?.serveosVenueId,
      serveosTaskId: widget.task?.serveosTaskId,
      syncedAt: widget.task?.syncedAt,
      createdAt: widget.task?.createdAt ?? now,
      updatedAt: now,
    );
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final repo = ref.read(boardRepositoryProvider);
    final task = _buildTask();
    try {
      if (_isNew) {
        await repo.saveTaskUpsert(task);
      } else {
        await repo.saveTask(task);
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (widget.task == null) return;
    await ref.read(boardRepositoryProvider).deleteTask(widget.task!.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _syncToServeos() async {
    final venue = await showVenuePickerDialog(context, ref);
    if (venue == null) return;

    final repo = ref.read(boardRepositoryProvider);
    try {
      // A szerver a mentett sorból építi az átküldött kártyát, ezért a
      // képernyőn lévő módosításokat előbb rögzítjük.
      final task = _buildTask();
      await repo.saveTask(task);
      await repo.syncToServeos(task, venue);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nem sikerült átküldeni a kártyát. Próbáld újra.')),
        );
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Átküldve a(z) "${venue.name}" ServeOS Kanban táblájára ✓')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Row(
            children: [
              Text(
                _isNew ? 'Új kártya' : 'Kártya szerkesztése',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              if (!_isNew)
                IconButton(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline, color: AppColors.priorityUrgent),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(labelText: 'Feladat neve'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            decoration: const InputDecoration(labelText: 'Leírás'),
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<TaskColumn>(
                  initialValue: _column,
                  decoration: const InputDecoration(labelText: 'Oszlop'),
                  items: TaskColumn.values
                      .map((c) => DropdownMenuItem(value: c, child: Text('${c.icon} ${c.title}')))
                      .toList(),
                  onChanged: (v) => setState(() => _column = v ?? _column),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<TaskPriority>(
                  initialValue: _priority,
                  decoration: const InputDecoration(labelText: 'Prioritás'),
                  items: TaskPriority.values
                      .map((p) => DropdownMenuItem(value: p, child: Text(p.label)))
                      .toList(),
                  onChanged: (v) => setState(() => _priority = v ?? _priority),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<TaskLabel>(
                  initialValue: _label,
                  decoration: const InputDecoration(labelText: 'Címke'),
                  items: TaskLabel.values
                      .map((l) => DropdownMenuItem(value: l, child: Text(l.title)))
                      .toList(),
                  onChanged: (v) => setState(() => _label = v ?? _label),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _dueDate ?? DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                    );
                    if (picked != null) setState(() => _dueDate = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Határidő'),
                    child: Text(_dueDate != null ? DateFormat('yyyy.MM.dd').format(_dueDate!) : '—'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Felelősök', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final name in _assignees)
                Chip(label: Text(name), onDeleted: () => setState(() => _assignees.remove(name))),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _assigneeCtrl,
                  decoration: const InputDecoration(hintText: '+ Felelős neve'),
                  onSubmitted: (_) => _addAssignee(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Checklist', style: Theme.of(context).textTheme.labelLarge),
          for (final item in _checklist)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: item.done,
              title: Text(item.text),
              onChanged: (v) => setState(() {
                final idx = _checklist.indexOf(item);
                _checklist[idx] = item.copyWith(done: v ?? false);
              }),
              secondary: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _checklist.remove(item)),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _checklistCtrl,
                  decoration: const InputDecoration(hintText: '+ Új tétel'),
                  onSubmitted: (_) => _addChecklistItem(),
                ),
              ),
              IconButton(onPressed: _addChecklistItem, icon: const Icon(Icons.add)),
            ],
          ),
          const SizedBox(height: 16),
          Text('Kommentek', style: Theme.of(context).textTheme.labelLarge),
          for (final c in _comments)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: RichText(
                text: TextSpan(
                  style: DefaultTextStyle.of(context).style.copyWith(fontSize: 13),
                  children: [
                    TextSpan(text: '${c.user}: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(text: c.text),
                    TextSpan(text: '  ${c.time}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  ],
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentCtrl,
                  decoration: const InputDecoration(hintText: 'Új komment...'),
                  onSubmitted: (_) => _addComment(),
                ),
              ),
              IconButton(onPressed: _addComment, icon: const Icon(Icons.send_rounded)),
            ],
          ),
          const SizedBox(height: 24),
          if (!_isNew && widget.task?.isSyncedToServeos != true)
            OutlinedButton.icon(
              onPressed: _syncToServeos,
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Küldés ServeOS-be'),
            ),
          if (widget.task?.isSyncedToServeos == true)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('✓ ServeOS-be szinkronizálva', style: TextStyle(color: AppColors.priorityLow)),
            ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Mentés'),
          ),
        ],
      ),
    );
  }
}
