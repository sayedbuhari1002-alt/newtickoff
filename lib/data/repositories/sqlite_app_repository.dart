import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/models/models.dart';
import 'app_repository.dart';

/// SQLite-backed [AppRepository].
class SqliteAppRepository implements AppRepository {
  SqliteAppRepository(this._db);

  final Database _db;

  /// Update-then-insert. Deliberately not `INSERT OR REPLACE`: replacing a
  /// parent row would fire ON DELETE CASCADE and wipe the habit's history.
  Future<void> _upsert(
    DatabaseExecutor executor,
    String table,
    Map<String, Object?> row,
  ) async {
    final int updated = await executor.update(
      table,
      row,
      where: 'id = ?',
      whereArgs: <Object?>[row['id']],
    );
    if (updated == 0) await executor.insert(table, row);
  }

  // ------------------------------------------------------------- app settings

  @override
  Future<Map<String, String>> loadSettings() async {
    final List<Map<String, Object?>> rows = await _db.query('app_settings');
    return <String, String>{
      for (final Map<String, Object?> row in rows)
        row['setting_key'] as String: row['setting_value'] as String,
    };
  }

  @override
  Future<void> saveSetting(String key, String value) async {
    final int changed = await _db.update(
      'app_settings',
      <String, Object?>{'setting_key': key, 'setting_value': value},
      where: 'setting_key = ?',
      whereArgs: <Object?>[key],
    );
    if (changed == 0) {
      await _db.insert('app_settings', <String, Object?>{
        'setting_key': key,
        'setting_value': value,
      });
    }
  }

  // ------------------------------------------------------------------ habits

  @override
  Future<List<Habit>> loadHabits() async {
    final List<Map<String, Object?>> rows = await _db.query('habits');
    final List<Habit> habits = <Habit>[];
    for (final Map<String, Object?> row in rows) {
      try {
        habits.add(_habitFromRow(row));
      } catch (e) {
        debugPrint('Skipping unreadable habit row: $e');
      }
    }
    return habits;
  }

  @override
  Future<void> upsertHabit(Habit habit) async {
    await _db.transaction((Transaction txn) async {
      await _upsert(txn, 'habits', _habitToRow(habit));
    });
  }

  @override
  Future<void> deleteHabit(String habitId) async {
    await _db.delete('habits', where: 'id = ?', whereArgs: <Object?>[habitId]);
  }

  Map<String, Object?> _habitToRow(Habit h) {
    final Map<String, dynamic> j = h.toJson();
    return <String, Object?>{
      'id': h.id,
      'title': h.title,
      'description': h.description,
      'icon_key': h.iconKey,
      'color': h.colorValue,
      'type': h.type.name,
      'tracking': h.tracking.name,
      'schedule_json': jsonEncode(j['schedule']),
      'reminder_json': jsonEncode(j['reminder']),
      'category_id': h.categoryId,
      'show_streaks': h.showStreaksOnTimeline ? 1 : 0,
      'daily_goal': h.dailyGoal,
      'unit': h.unit,
      'step': h.step,
      'checklist_json': jsonEncode(j['checklist']),
      'created_at': h.createdAt.toIso8601String(),
      'archived_at': h.archivedAt?.toIso8601String(),
      'sort_order': h.sortOrder,
    };
  }

  Habit _habitFromRow(Map<String, Object?> r) {
    return Habit.fromJson(<String, dynamic>{
      'id': r['id'],
      'title': r['title'],
      'description': r['description'],
      'iconKey': r['icon_key'],
      'colorValue': r['color'],
      'type': r['type'],
      'tracking': r['tracking'],
      'schedule': jsonDecode(r['schedule_json'] as String),
      'reminder': jsonDecode(r['reminder_json'] as String),
      'categoryId': r['category_id'],
      'showStreaksOnTimeline': (r['show_streaks'] as int? ?? 1) != 0,
      'dailyGoal': r['daily_goal'],
      'unit': r['unit'],
      'step': r['step'],
      'checklist': jsonDecode(r['checklist_json'] as String),
      'createdAt': r['created_at'],
      'archivedAt': r['archived_at'],
      'sortOrder': r['sort_order'],
    });
  }

  // -------------------------------------------------------------- categories

  @override
  Future<List<HabitCategory>> loadCategories() async {
    final List<Map<String, Object?>> rows = await _db.query('categories');
    return rows
        .map(
          (Map<String, Object?> r) => HabitCategory(
            id: r['id'] as String,
            name: (r['name'] as String?) ?? '',
            iconKey: r['icon_key'] as String?,
            sortOrder: (r['sort_order'] as int?) ?? 0,
          ),
        )
        .toList();
  }

  @override
  Future<void> upsertCategory(HabitCategory c) async {
    await _db.transaction((Transaction txn) async {
      await _upsert(txn, 'categories', <String, Object?>{
        'id': c.id,
        'name': c.name,
        'icon_key': c.iconKey,
        'sort_order': c.sortOrder,
      });
    });
  }

  @override
  Future<void> deleteCategory(String categoryId) async {
    await _db.delete(
      'categories',
      where: 'id = ?',
      whereArgs: <Object?>[categoryId],
    );
  }

  // ------------------------------------------------------------- completions

  @override
  Future<List<CompletionRecord>> loadCompletions() async {
    final List<Map<String, Object?>> rows = await _db.query('completions');
    final List<CompletionRecord> records = <CompletionRecord>[];
    for (final Map<String, Object?> r in rows) {
      try {
        records.add(
          CompletionRecord.fromJson(<String, dynamic>{
            'habitId': r['habit_id'],
            'dateKey': r['date_key'],
            'done': (r['done'] as int? ?? 0) != 0,
            'count': r['count_value'],
            'checkedItemIds': jsonDecode(r['checked_ids_json'] as String),
            'slipped': (r['slipped'] as int? ?? 0) != 0,
            'updatedAt': r['updated_at'],
          }),
        );
      } catch (e) {
        debugPrint('Skipping unreadable completion row: $e');
      }
    }
    return records;
  }

  @override
  Future<void> upsertCompletion(CompletionRecord r) async {
    // Safe to REPLACE: completions are leaf rows and (habit_id, date_key) is
    // the primary key, so there can never be two records for one habit/day.
    await _db.insert(
      'completions',
      <String, Object?>{
        'habit_id': r.habitId,
        'date_key': r.dateKey,
        'done': r.done ? 1 : 0,
        'count_value': r.count,
        'checked_ids_json': jsonEncode(r.checkedItemIds.toList()..sort()),
        'slipped': r.slipped ? 1 : 0,
        'updated_at': r.updatedAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteCompletion(String habitId, String dateKey) async {
    await _db.delete(
      'completions',
      where: 'habit_id = ? AND date_key = ?',
      whereArgs: <Object?>[habitId, dateKey],
    );
  }

  // ------------------------------------------------------------------- notes

  @override
  Future<List<Note>> loadNotes() async {
    final List<Map<String, Object?>> rows = await _db.query('notes');
    final List<Note> notes = <Note>[];
    for (final Map<String, Object?> r in rows) {
      try {
        notes.add(
          Note.fromJson(<String, dynamic>{
            'id': r['id'],
            'habitId': r['habit_id'],
            'title': r['title'],
            'body': r['body'],
            'createdAt': r['created_at'],
            'updatedAt': r['updated_at'],
            'photoPaths': jsonDecode(r['photos_json'] as String),
            'audioPaths': jsonDecode(r['audio_json'] as String),
          }),
        );
      } catch (e) {
        debugPrint('Skipping unreadable note row: $e');
      }
    }
    return notes;
  }

  @override
  Future<void> upsertNote(Note n) async {
    await _db.transaction((Transaction txn) async {
      await _upsert(txn, 'notes', <String, Object?>{
        'id': n.id,
        'habit_id': n.habitId,
        'title': n.title,
        'body': n.body,
        'created_at': n.createdAt.toIso8601String(),
        'updated_at': n.updatedAt.toIso8601String(),
        'photos_json': jsonEncode(n.photoPaths),
        'audio_json': jsonEncode(n.audioPaths),
      });
    });
  }

  @override
  Future<void> deleteNote(String noteId) async {
    await _db.delete('notes', where: 'id = ?', whereArgs: <Object?>[noteId]);
  }

  // -------------------------------------------------------------------- tasks

  @override
  Future<List<Task>> loadTasks() async {
    final List<Map<String, Object?>> taskRows = await _db.query('tasks');
    final List<Map<String, Object?>> subtaskRows = await _db.query(
      'subtasks', orderBy: 'task_id ASC, sort_order ASC',
    );
    final Map<String, List<Subtask>> byTask = <String, List<Subtask>>{};
    for (final Map<String, Object?> row in subtaskRows) {
      final Subtask subtask = Subtask(
        id: row['id'] as String,
        title: row['title'] as String,
        createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
        dueAt: DateTime.tryParse(row['due_at'] as String? ?? ''),
        isCompleted: (row['is_completed'] as int? ?? 0) != 0,
        completedAt: DateTime.tryParse(row['completed_at'] as String? ?? ''),
        sortOrder: (row['sort_order'] as int?) ?? 0,
      );
      byTask.putIfAbsent(row['task_id'] as String, () => <Subtask>[]).add(subtask);
    }
    final List<Task> tasks = <Task>[];
    for (final Map<String, Object?> row in taskRows) {
      try {
        final Task task = Task(
          id: row['id'] as String,
          title: row['title'] as String,
          description: row['description'] as String? ?? '',
          dueAt: DateTime.tryParse(row['due_at'] as String? ?? ''),
          reminderAt: DateTime.tryParse(row['reminder_at'] as String? ?? ''),
          priority: TaskPriority.values.firstWhere(
            (TaskPriority p) => p.name == row['priority'],
            orElse: () => TaskPriority.medium,
          ),
          category: row['category'] as String? ?? '',
          iconKey: row['icon_key'] as String? ?? 'task',
          colorValue: row['color_value'] as int? ?? 0xFFFFC857,
          isCompleted: (row['is_completed'] as int? ?? 0) != 0,
          completedAt: DateTime.tryParse(row['completed_at'] as String? ?? ''),
          isPaused: (row['is_paused'] as int? ?? 0) != 0,
          repeat: TaskRepeat.values.firstWhere(
            (TaskRepeat v) => v.name == row['repeat_rule'],
            orElse: () => TaskRepeat.none,
          ),
          notes: row['notes'] as String? ?? '',
          photoPaths: (jsonDecode(row['photo_paths_json'] as String? ?? '[]') as List).whereType<String>().toList(),
          audioPaths: (jsonDecode(row['audio_paths_json'] as String? ?? '[]') as List).whereType<String>().toList(),
          subtasks: byTask[row['id']] ?? const <Subtask>[],
          createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
          updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
        );
        tasks.add(task);
      } catch (e) {
        debugPrint('Skipping unreadable task row: $e');
      }
    }
    return tasks;
  }

  @override
  Future<void> upsertTask(Task task) async {
    await _db.transaction((Transaction txn) async {
      final Map<String, Object?> row = <String, Object?>{
        'id': task.id,
        'title': task.title.trim(),
        'description': task.description,
        'due_at': task.dueAt?.toIso8601String(),
        'reminder_at': task.reminderAt?.toIso8601String(),
        'priority': task.priority.name,
        'category': task.category,
        'icon_key': task.iconKey,
        'color_value': task.colorValue,
        'is_completed': task.isCompleted ? 1 : 0,
        'completed_at': task.completedAt?.toIso8601String(),
        'is_paused': task.isPaused ? 1 : 0,
        'repeat_rule': task.repeat.name,
        'notes': task.notes,
        'photo_paths_json': jsonEncode(task.photoPaths),
        'audio_paths_json': jsonEncode(task.audioPaths),
        'created_at': task.createdAt.toIso8601String(),
        'updated_at': task.updatedAt.toIso8601String(),
      };
      await _upsert(txn, 'tasks', row);
      // Reconcile only the subtask rows. Task history has no FK and is intact.
      final Set<String> keep = task.subtasks.map((Subtask s) => s.id).toSet();
      final List<Map<String, Object?>> existing = await txn.query(
        'subtasks', columns: <String>['id'], where: 'task_id = ?', whereArgs: <Object?>[task.id],
      );
      for (final Map<String, Object?> old in existing) {
        final String id = old['id'] as String;
        if (!keep.contains(id)) await txn.delete('subtasks', where: 'id = ?', whereArgs: <Object?>[id]);
      }
      for (final Subtask subtask in task.subtasks) {
        final Map<String, Object?> subRow = <String, Object?>{
          'id': subtask.id,
          'task_id': task.id,
          'title': subtask.title.trim(),
          'created_at': subtask.createdAt.toIso8601String(),
          'due_at': subtask.dueAt?.toIso8601String(),
          'is_completed': subtask.isCompleted ? 1 : 0,
          'completed_at': subtask.completedAt?.toIso8601String(),
          'sort_order': subtask.sortOrder,
        };
        final int updated = await txn.update('subtasks', subRow, where: 'id = ?', whereArgs: <Object?>[subtask.id]);
        if (updated == 0) await txn.insert('subtasks', subRow);
      }
    });
  }

  @override
  Future<void> deleteTask(String taskId) async {
    // The task row and its live subtasks are removed; immutable activities stay.
    await _db.delete('tasks', where: 'id = ?', whereArgs: <Object?>[taskId]);
  }

  @override
  Future<List<TaskActivity>> loadTaskActivities() async {
    final List<Map<String, Object?>> rows = await _db.query(
      'task_activities', orderBy: 'occurred_at ASC, id ASC',
    );
    return rows.map(TaskActivity.fromMap).toList();
  }

  @override
  Future<void> addTaskActivity(TaskActivity activity) async {
    await _db.insert('task_activities', activity.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  // ------------------------------------------------------------ achievements

  @override
  Future<Map<String, Map<int, String>>> loadAchievements() async {
    final List<Map<String, Object?>> rows = await _db.query('achievements');
    final Map<String, Map<int, String>> result = <String, Map<int, String>>{};
    for (final Map<String, Object?> r in rows) {
      final String habitId = r['habit_id'] as String;
      result.putIfAbsent(habitId, () => <int, String>{})[r['milestone'] as int] =
          r['unlocked_on'] as String;
    }
    return result;
  }

  @override
  Future<void> saveAchievement(
    String habitId,
    int milestone,
    String unlockedOn,
  ) async {
    await _db.insert(
      'achievements',
      <String, Object?>{
        'habit_id': habitId,
        'milestone': milestone,
        'unlocked_on': unlockedOn,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}
