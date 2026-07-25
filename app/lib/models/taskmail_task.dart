import 'checklist_item.dart';
import 'task_comment.dart';

/// A ServeOS `tasks` tábla `col` enumjával megegyező oszlopok — ugyanaz a
/// 4 fix érték, hogy egy szinkronizált kártya oszlopa mindkét rendszerben
/// ugyanazt jelentse. Az "archivált" állapot itt külön `isArchived` flag,
/// NEM ötödik oszlop (a ServeOS DB enum-ja sem ismeri az 'archived' értéket).
enum TaskColumn { todo, inprogress, review, done }

extension TaskColumnX on TaskColumn {
  String get dbValue => name;

  static TaskColumn fromDb(String value) =>
      TaskColumn.values.firstWhere((c) => c.dbValue == value, orElse: () => TaskColumn.todo);

  String get title => switch (this) {
        TaskColumn.todo => 'Teendő',
        TaskColumn.inprogress => 'Folyamatban',
        TaskColumn.review => 'Ellenőrzés',
        TaskColumn.done => 'Kész',
      };

  String get icon => switch (this) {
        TaskColumn.todo => '📋',
        TaskColumn.inprogress => '⚡',
        TaskColumn.review => '🔍',
        TaskColumn.done => '✅',
      };
}

/// ServeOS `task_priority` enum: urgent/high/medium/low
enum TaskPriority { urgent, high, medium, low }

extension TaskPriorityX on TaskPriority {
  String get dbValue => name;

  static TaskPriority fromDb(String value) =>
      TaskPriority.values.firstWhere((p) => p.dbValue == value, orElse: () => TaskPriority.medium);

  String get label => switch (this) {
        TaskPriority.urgent => '🔴 Sürgős',
        TaskPriority.high => '🟠 Magas',
        TaskPriority.medium => '🟡 Közepes',
        TaskPriority.low => '🟢 Alacsony',
      };
}

/// ServeOS LABEL_OPTIONS kulcsaival megegyező címkék.
enum TaskLabel { urgent, ops, kitchen, service, admin, event }

extension TaskLabelX on TaskLabel {
  String get dbValue => name;

  static TaskLabel fromDb(String value) =>
      TaskLabel.values.firstWhere((l) => l.dbValue == value, orElse: () => TaskLabel.ops);

  String get title => switch (this) {
        TaskLabel.urgent => 'Sürgős',
        TaskLabel.ops => 'Operatív',
        TaskLabel.kitchen => 'Konyha',
        TaskLabel.service => 'Felszolgálás',
        TaskLabel.admin => 'Adminisztráció',
        TaskLabel.event => 'Esemény',
      };
}

/// `taskmail_tasks` sor — mezőnként igazítva a ServeOS `tasks` táblájához,
/// hogy a ServeOS-be küldés (lásd `board`/board_repository.dart) triviális
/// mezőleképezés legyen. A `serveos*`/`synced_at` mezők csak TaskMail-oldali
/// nyomkövetést szolgálnak, a ServeOS `tasks` táblájában nincs megfelelőjük.
class TaskMailTask {
  final String id;
  final String userId;
  final String boardId;
  final String title;
  final String description;
  final TaskColumn column;
  final TaskPriority priority;
  final TaskLabel label;
  final List<String> assignees;
  final DateTime? dueDate;
  final List<ChecklistItem> checklist;
  final List<TaskComment> comments;
  final int sortOrder;
  final bool isArchived;
  final bool createdByAi;
  final String? sourceEmailId;
  final String? serveosVenueId;
  final int? serveosTaskId;
  final DateTime? syncedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TaskMailTask({
    required this.id,
    required this.userId,
    required this.boardId,
    required this.title,
    this.description = '',
    this.column = TaskColumn.todo,
    this.priority = TaskPriority.medium,
    this.label = TaskLabel.ops,
    this.assignees = const [],
    this.dueDate,
    this.checklist = const [],
    this.comments = const [],
    this.sortOrder = 0,
    this.isArchived = false,
    this.createdByAi = false,
    this.sourceEmailId,
    this.serveosVenueId,
    this.serveosTaskId,
    this.syncedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isSyncedToServeos => serveosTaskId != null;

  factory TaskMailTask.fromJson(Map<String, dynamic> json) => TaskMailTask(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        boardId: json['board_id'] as String,
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        column: TaskColumnX.fromDb(json['col'] as String? ?? 'todo'),
        priority: TaskPriorityX.fromDb(json['priority'] as String? ?? 'medium'),
        label: TaskLabelX.fromDb(json['label'] as String? ?? 'ops'),
        assignees: (json['assignees'] as List?)?.map((e) => e as String).toList() ?? const [],
        dueDate: json['due_date'] != null ? DateTime.tryParse(json['due_date'] as String) : null,
        checklist: (json['checklist'] as List?)
                ?.map((e) => ChecklistItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        comments: (json['comments'] as List?)
                ?.map((e) => TaskComment.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        sortOrder: json['sort_order'] as int? ?? 0,
        isArchived: json['is_archived'] as bool? ?? false,
        createdByAi: json['created_by_ai'] as bool? ?? false,
        sourceEmailId: json['source_email_id'] as String?,
        serveosVenueId: json['serveos_venue_id'] as String?,
        serveosTaskId: json['serveos_task_id'] as int?,
        syncedAt: json['synced_at'] != null ? DateTime.tryParse(json['synced_at'] as String) : null,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  /// A `taskmail_tasks` táblába íráshoz.
  Map<String, dynamic> toInsertJson() => {
        'user_id': userId,
        'board_id': boardId,
        'title': title,
        'description': description,
        'col': column.dbValue,
        'priority': priority.dbValue,
        'label': label.dbValue,
        'assignees': assignees,
        'due_date': dueDate?.toIso8601String().split('T').first,
        'checklist': checklist.map((e) => e.toJson()).toList(),
        'comments': comments.map((e) => e.toJson()).toList(),
        'sort_order': sortOrder,
        'is_archived': isArchived,
        'created_by_ai': createdByAi,
        'source_email_id': sourceEmailId,
      };

  /// A ServeOS megosztott `tasks` táblájába küldéshez — csak azok a mezők,
  /// amik ott is léteznek (lásd `serveos/supabase/migration.sql`).
  Map<String, dynamic> toServeosInsertJson({required String venueId}) => {
        'title': title,
        'description': description,
        'col': column.dbValue,
        'priority': priority.dbValue,
        'label': label.dbValue,
        'assignees': assignees,
        'due_date': dueDate?.toIso8601String().split('T').first,
        'checklist': checklist.map((e) => e.toJson()).toList(),
        'comments': [
          {
            'id': DateTime.now().millisecondsSinceEpoch,
            'user': 'TaskMail AI',
            'text': 'Létrehozva a TaskMail appból',
            'time': _nowStamp(),
          },
          ...comments.map((e) => e.toJson()),
        ],
        'venue_id': venueId,
      };

  static String _nowStamp() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(now.month)}.${two(now.day)} ${two(now.hour)}:${two(now.minute)}';
  }

  TaskMailTask copyWith({
    String? title,
    String? description,
    TaskColumn? column,
    TaskPriority? priority,
    TaskLabel? label,
    List<String>? assignees,
    DateTime? dueDate,
    List<ChecklistItem>? checklist,
    List<TaskComment>? comments,
    int? sortOrder,
    bool? isArchived,
    String? serveosVenueId,
    int? serveosTaskId,
    DateTime? syncedAt,
  }) =>
      TaskMailTask(
        id: id,
        userId: userId,
        boardId: boardId,
        title: title ?? this.title,
        description: description ?? this.description,
        column: column ?? this.column,
        priority: priority ?? this.priority,
        label: label ?? this.label,
        assignees: assignees ?? this.assignees,
        dueDate: dueDate ?? this.dueDate,
        checklist: checklist ?? this.checklist,
        comments: comments ?? this.comments,
        sortOrder: sortOrder ?? this.sortOrder,
        isArchived: isArchived ?? this.isArchived,
        createdByAi: createdByAi,
        sourceEmailId: sourceEmailId,
        serveosVenueId: serveosVenueId ?? this.serveosVenueId,
        serveosTaskId: serveosTaskId ?? this.serveosTaskId,
        syncedAt: syncedAt ?? this.syncedAt,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}
