import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tickoff_replacement/core/utils/date_utils.dart';
import 'package:tickoff_replacement/data/database/app_database.dart';
import 'package:tickoff_replacement/data/repositories/sqlite_app_repository.dart';
import 'package:tickoff_replacement/domain/models/models.dart';

/// These tests run the real SQLite schema and repository through
/// sqflite_common_ffi (SQLite on the build machine), not on a phone.

Habit makeHabit({String id = 'h1', String? categoryId}) {
  return Habit(
    id: id,
    title: 'Reading Books',
    description: 'Read every day',
    createdAt: DateTime(2026, 10, 26, 8, 30),
    iconKey: 'menu_book',
    colorValue: 0xFFFFC62B,
    type: HabitType.build,
    tracking: TrackingMethod.checklist,
    schedule: const Schedule(
      type: FrequencyType.daysOfWeek,
      weekdays: <int>{1, 3, 5},
    ),
    reminder: const Reminder(enabled: true, minutesOfDay: 21 * 60),
    categoryId: categoryId,
    showStreaksOnTimeline: false,
    dailyGoal: 2.5,
    unit: 'pages',
    step: 0.5,
    checklist: const <ChecklistItem>[
      ChecklistItem(id: 'c1', title: 'Chapter'),
      ChecklistItem(
        id: 'c2',
        title: 'Notes',
        reminder: Reminder(enabled: true, minutesOfDay: 600),
      ),
    ],
    sortOrder: 3,
  );
}

CompletionRecord record(String habitId, String key, {double count = 0}) {
  return CompletionRecord(
    habitId: habitId,
    dateKey: key,
    updatedAt: DateTime(2026, 10, 27),
    done: true,
    count: count,
    checkedItemIds: const <String>{'c1'},
  );
}

Future<int> countRows(Database db, String table) async {
  final List<Map<String, Object?>> rows =
      await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
  return Sqflite.firstIntValue(rows) ?? -1;
}

Task makeStoredTask({String id = 'task-1'}) => Task(
      id: id,
      title: 'Prepare report',
      description: 'Draft then review',
      dueAt: DateTime(2026, 11, 4, 17),
      reminderAt: DateTime(2026, 11, 3, 9),
      priority: TaskPriority.high,
      category: 'Study',
      iconKey: 'study',
      colorValue: 0xFF26C6DA,
      repeat: TaskRepeat.weekly,
      notes: 'Use the lab results',
      photoPaths: const <String>['/app/attachments/photo.jpg'],
      audioPaths: const <String>['/app/attachments/audio.m4a'],
      subtasks: <Subtask>[
        Subtask(id: 'step-1', title: 'Gather notes', createdAt: DateTime(2026, 10, 27), dueAt: DateTime(2026, 11, 2, 11), sortOrder: 0),
      ],
      createdAt: DateTime(2026, 10, 27, 8),
      updatedAt: DateTime(2026, 10, 27, 8),
    );

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late SqliteAppRepository repo;

  setUp(() async {
    db = await AppDatabase.open(path: inMemoryDatabasePath);
    repo = SqliteAppRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('tasks, subtasks, attachments and status round-trip in SQLite', () async {
    final Task task = makeStoredTask();
    await repo.upsertTask(task);
    final Task loaded = (await repo.loadTasks()).single;
    expect(loaded.id, task.id);
    expect(loaded.title, task.title);
    expect(loaded.description, task.description);
    expect(loaded.dueAt, task.dueAt);
    expect(loaded.reminderAt, task.reminderAt);
    expect(loaded.priority, TaskPriority.high);
    expect(loaded.repeat, TaskRepeat.weekly);
    expect(loaded.notes, task.notes);
    expect(loaded.photoPaths, task.photoPaths);
    expect(loaded.audioPaths, task.audioPaths);
    expect(loaded.subtasks.single.id, 'step-1');
    expect(loaded.subtasks.single.dueAt, DateTime(2026, 11, 2, 11));

    await repo.upsertTask(loaded.copyWith(title: 'Final report'));
    expect(await countRows(db, 'tasks'), 1);
    expect((await repo.loadTasks()).single.title, 'Final report');
  });

  test('deleting a task retains immutable activity history', () async {
    await repo.upsertTask(makeStoredTask());
    final TaskActivity event = TaskActivity(
      id: 'event-1',
      taskId: 'task-1',
      entityId: 'step-1',
      entityType: 'subtask',
      eventType: 'subtask_completed',
      occurredAt: DateTime(2026, 10, 28, 14),
      snapshotJson: '{"title":"Prepare report","priority":"high","hasSubtasks":true}',
    );
    await repo.addTaskActivity(event);
    await repo.deleteTask('task-1');
    expect(await countRows(db, 'tasks'), 0);
    expect(await countRows(db, 'subtasks'), 0);
    expect(await countRows(db, 'task_activities'), 1);
    expect((await repo.loadTaskActivities()).single.entityId, 'step-1');
  });

  test('schema is created at the current version', () async {
    expect(await db.getVersion(), AppDatabase.version);
    final List<Map<String, Object?>> tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final Set<String> names =
        tables.map((Map<String, Object?> r) => r['name'] as String).toSet();
    expect(
      names,
      containsAll(<String>[
        'habits',
        'categories',
        'completions',
        'notes',
        'achievements',
        'tasks',
        'subtasks',
        'task_activities',
        'app_settings',
      ]),
    );
  });

  test('local settings round-trip through SQLite', () async {
    await repo.saveSetting('ui.theme', 'graphite');
    await repo.saveSetting('dashboard.section_order', '["tasks","progress","habits","insights"]');
    expect(await repo.loadSettings(), <String, String>{
      'ui.theme': 'graphite',
      'dashboard.section_order': '["tasks","progress","habits","insights"]',
    });
    await repo.saveSetting('ui.theme', 'original');
    expect((await repo.loadSettings())['ui.theme'], 'original');
    expect(await countRows(db, 'app_settings'), 2);
  });

  test('opening a version-1 database upgrades without deleting habit data', () async {
    final String oldPath = p.join(await getDatabasesPath(), 'stage3-migration-test.db');
    await databaseFactory.deleteDatabase(oldPath);
    final Database oldDb = await databaseFactory.openDatabase(
      oldPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (Database database, int version) async {
          await database.execute('CREATE TABLE habits (id TEXT PRIMARY KEY, title TEXT NOT NULL)');
          await database.insert('habits', <String, Object?>{'id': 'legacy-habit', 'title': 'Keep me'});
        },
      ),
    );
    await oldDb.close();
    final Database upgraded = await AppDatabase.open(path: oldPath);
    try {
      expect(await upgraded.getVersion(), AppDatabase.version);
      final List<Map<String, Object?>> retained = await upgraded.query('habits');
      expect(retained.single['id'], 'legacy-habit');
      expect(retained.single['title'], 'Keep me');
      expect(await countRows(upgraded, 'tasks'), 0);
      expect(await countRows(upgraded, 'task_activities'), 0);
    } finally {
      await upgraded.close();
      await databaseFactory.deleteDatabase(oldPath);
    }
  });

  test('a habit round-trips with every configuration field', () async {
    await repo.upsertCategory(const HabitCategory(id: 'cat', name: 'Mind'));
    final Habit h = makeHabit(categoryId: 'cat');
    await repo.upsertHabit(h);
    final List<Habit> loaded = await repo.loadHabits();
    expect(loaded.length, 1);
    expect(loaded.single, h);
  });

  test('updating a habit keeps its history (no cascade wipe)', () async {
    final Habit h = makeHabit();
    await repo.upsertHabit(h);
    await repo.upsertCompletion(record(h.id, '2026-10-26'));
    await repo.saveAchievement(h.id, 1, '2026-10-26');
    await repo.upsertNote(
      Note(
        id: 'n1',
        habitId: h.id,
        createdAt: DateTime(2026, 10, 26),
        updatedAt: DateTime(2026, 10, 26),
      ),
    );

    await repo.upsertHabit(h.copyWith(title: 'Renamed'));

    expect((await repo.loadHabits()).single.title, 'Renamed');
    expect(await countRows(db, 'habits'), 1);
    expect(await countRows(db, 'completions'), 1);
    expect(await countRows(db, 'achievements'), 1);
    expect(await countRows(db, 'notes'), 1);
  });

  test('there is never more than one completion per habit and day', () async {
    await repo.upsertHabit(makeHabit());
    await repo.upsertCompletion(record('h1', '2026-10-27', count: 1));
    await repo.upsertCompletion(record('h1', '2026-10-27', count: 5));
    expect(await countRows(db, 'completions'), 1);
    final List<CompletionRecord> all = await repo.loadCompletions();
    expect(all.single.count, 5);
    expect(all.single.checkedItemIds, <String>{'c1'});

    await repo.upsertCompletion(record('h1', '2026-10-28'));
    expect(await countRows(db, 'completions'), 2);

    await repo.deleteCompletion('h1', '2026-10-27');
    expect(await countRows(db, 'completions'), 1);
  });

  test('completion fields survive a round trip', () async {
    await repo.upsertHabit(makeHabit());
    final CompletionRecord r = CompletionRecord(
      habitId: 'h1',
      dateKey: '2026-10-27',
      updatedAt: DateTime(2026, 10, 27, 19, 3),
      done: true,
      count: 4.5,
      checkedItemIds: const <String>{'c1', 'c2'},
      slipped: true,
    );
    await repo.upsertCompletion(r);
    expect((await repo.loadCompletions()).single, r);
  });

  test('deleting a habit removes its completions, achievements and notes',
      () async {
    await repo.upsertHabit(makeHabit(id: 'a'));
    await repo.upsertHabit(makeHabit(id: 'b'));
    for (final String id in <String>['a', 'b']) {
      await repo.upsertCompletion(record(id, '2026-10-27'));
      await repo.saveAchievement(id, 1, '2026-10-27');
      await repo.upsertNote(
        Note(
          id: 'note-$id',
          habitId: id,
          createdAt: DateTime(2026, 10, 27),
          updatedAt: DateTime(2026, 10, 27),
        ),
      );
    }
    await repo.deleteHabit('a');
    expect(await countRows(db, 'habits'), 1);
    expect(await countRows(db, 'completions'), 1);
    expect(await countRows(db, 'achievements'), 1);
    expect(await countRows(db, 'notes'), 1);
    expect((await repo.loadCompletions()).single.habitId, 'b');
  });

  test('deleting a category keeps habits and clears their category', () async {
    await repo.upsertCategory(const HabitCategory(id: 'cat', name: 'Mind'));
    await repo.upsertHabit(makeHabit(categoryId: 'cat'));
    await repo.deleteCategory('cat');
    expect(await countRows(db, 'categories'), 0);
    final Habit h = (await repo.loadHabits()).single;
    expect(h.categoryId, isNull);
  });

  test('relationships are enforced: no completion for an unknown habit',
      () async {
    expect(
      () => repo.upsertCompletion(record('ghost', '2026-10-27')),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('achievements are stored once; the first unlock date wins', () async {
    await repo.upsertHabit(makeHabit());
    await repo.saveAchievement('h1', 7, '2026-10-01');
    await repo.saveAchievement('h1', 7, '2026-10-20');
    await repo.saveAchievement('h1', 14, '2026-10-20');
    final Map<String, Map<int, String>> all = await repo.loadAchievements();
    expect(all['h1'], <int, String>{7: '2026-10-01', 14: '2026-10-20'});
  });

  test('notes round-trip including attachment references', () async {
    await repo.upsertHabit(makeHabit());
    final Note n = Note(
      id: 'n1',
      habitId: 'h1',
      title: 'Idea',
      body: 'Line 1\nLine 2',
      createdAt: DateTime(2026, 10, 26, 9),
      updatedAt: DateTime(2026, 10, 27, 10),
      photoPaths: const <String>['/data/p1.jpg'],
      audioPaths: const <String>['/data/a1.m4a', '/data/a2.m4a'],
    );
    await repo.upsertNote(n);
    expect((await repo.loadNotes()).single, n);

    await repo.upsertNote(n.copyWith(title: 'Edited'));
    expect(await countRows(db, 'notes'), 1);
    expect((await repo.loadNotes()).single.title, 'Edited');

    await repo.deleteNote('n1');
    expect(await repo.loadNotes(), isEmpty);
  });

  test('a standalone note (no habit) is allowed', () async {
    final Note n = Note(
      id: 'free',
      title: 'Loose thought',
      createdAt: DateTime(2026, 10, 27),
      updatedAt: DateTime(2026, 10, 27),
    );
    await repo.upsertNote(n);
    expect((await repo.loadNotes()).single.habitId, isNull);
  });

  test('data survives closing and reopening the database file', () async {
    final Directory dir = Directory.systemTemp.createTempSync('tickoff_db_');
    final String path = p.join(dir.path, 'restart.db');
    try {
      Database first = await AppDatabase.open(path: path);
      SqliteAppRepository r1 = SqliteAppRepository(first);
      await r1.upsertCategory(const HabitCategory(id: 'cat', name: 'Mind'));
      await r1.upsertHabit(makeHabit(categoryId: 'cat'));
      await r1.upsertCompletion(record('h1', dateKey(DateTime(2026, 10, 27))));
      await r1.saveAchievement('h1', 1, '2026-10-27');
      await first.close();

      final Database second = await AppDatabase.open(path: path);
      final SqliteAppRepository r2 = SqliteAppRepository(second);
      expect((await r2.loadHabits()).single.title, 'Reading Books');
      expect((await r2.loadCategories()).single.name, 'Mind');
      expect((await r2.loadCompletions()).single.dateKey, '2026-10-27');
      expect((await r2.loadAchievements())['h1'], <int, String>{1: '2026-10-27'});
      await second.close();
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
