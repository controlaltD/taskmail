import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/supabase/supabase_client.dart';
import '../../models/board.dart';
import '../../models/serveos_venue.dart';
import '../../models/taskmail_task.dart';
import '../auth/auth_controller.dart';

const _uuid = Uuid();

/// Minden usernek egy alapértelmezett board-ja van — ha még nincs, létrehozzuk.
/// Ez tükrözi a ServeOS `FeladatokBoard` egyetlen, venue-szintű board
/// koncepcióját, csak itt user-szinten.
final defaultBoardProvider = FutureProvider.autoDispose<Board>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) throw StateError('Nincs bejelentkezve');

  final existing = await supabase
      .from('taskmail_boards')
      .select()
      .eq('user_id', user.id)
      .eq('is_default', true)
      .maybeSingle();
  if (existing != null) return Board.fromJson(existing);

  final inserted = await supabase
      .from('taskmail_boards')
      .insert({'user_id': user.id, 'name': 'Saját feladatok', 'is_default': true})
      .select()
      .single();
  return Board.fromJson(inserted);
});

final boardTasksProvider = FutureProvider.autoDispose<List<TaskMailTask>>((ref) async {
  final board = await ref.watch(defaultBoardProvider.future);
  final rows = await supabase
      .from('taskmail_tasks')
      .select()
      .eq('board_id', board.id)
      .order('sort_order');
  return (rows as List).map((e) => TaskMailTask.fromJson(e as Map<String, dynamic>)).toList();
});

/// A user ServeOS venue-kapcsolatai (`venue_users`) — ez adja a
/// "Küldés ServeOS-be" venue-választó listáját.
final serveosVenuesProvider = FutureProvider.autoDispose<List<ServeosVenue>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];

  final rows = await supabase
      .from('venue_users')
      .select('venue_id, role, venues(name)')
      .eq('user_id', user.id)
      .eq('active', true);
  return (rows as List).map((e) => ServeosVenue.fromJson(e as Map<String, dynamic>)).toList();
});

class BoardRepository {
  BoardRepository(this.ref);

  final Ref ref;

  Future<void> createTask({
    required String boardId,
    required String userId,
    required String title,
    required TaskColumn column,
  }) async {
    await supabase.from('taskmail_tasks').insert({
      'id': _uuid.v4(),
      'user_id': userId,
      'board_id': boardId,
      'title': title,
      'col': column.dbValue,
    });
    ref.invalidate(boardTasksProvider);
  }

  /// Új kártya mentése (a szerkesztő sheet-ben már generált id-val).
  Future<void> saveTaskUpsert(TaskMailTask task) async {
    await supabase.from('taskmail_tasks').insert({'id': task.id, ...task.toInsertJson()});
    ref.invalidate(boardTasksProvider);
  }

  Future<void> saveTask(TaskMailTask task) async {
    await supabase.from('taskmail_tasks').update(task.toInsertJson()).eq('id', task.id);
    ref.invalidate(boardTasksProvider);
  }

  Future<void> moveTask(String taskId, TaskColumn column) async {
    await supabase.from('taskmail_tasks').update({'col': column.dbValue}).eq('id', taskId);
    ref.invalidate(boardTasksProvider);
  }

  Future<void> setArchived(String taskId, bool archived) async {
    await supabase.from('taskmail_tasks').update({'is_archived': archived}).eq('id', taskId);
    ref.invalidate(boardTasksProvider);
  }

  Future<void> deleteTask(String taskId) async {
    await supabase.from('taskmail_tasks').delete().eq('id', taskId);
    ref.invalidate(boardTasksProvider);
  }

  /// Kártya átküldése a ServeOS Kanban táblájára.
  ///
  /// A beszúrást a `taskmail_push_to_serveos` függvény végzi, ami
  /// szerveroldalon ellenőrzi, hogy a kártya tényleg a hívóé, és hogy a hívó
  /// tagja-e a megcélzott üzletnek. Korábban a kliens közvetlenül írt a
  /// `tasks` táblába a saját maga által megadott `venue_id`-val — azt semmi
  /// nem ellenőrizte, így egy módosított kliens bármelyik üzletbe írhatott.
  Future<void> syncToServeos(TaskMailTask task, ServeosVenue venue) async {
    await supabase.rpc('taskmail_push_to_serveos', params: {
      'p_task_id': task.id,
      'p_venue_id': venue.venueId,
    });
    ref.invalidate(boardTasksProvider);
  }
}

final boardRepositoryProvider = Provider((ref) => BoardRepository(ref));
