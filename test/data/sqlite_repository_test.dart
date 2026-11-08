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
      parentTaskId: 'parent-group',
      taskType: TaskType.progressive,
      progressMode: TaskProgressMode.count,
      progressValue: 5,
      progressTarget: 10,
      progressUnit: 'chapters',
      difficultyScore: 3.5,
      sortOrder: 2,
      notes: 'Use the lab results',
      photoPaths: const <String>['/app/attachments/photo.jpg'],
      audioPaths: const <String>['/app/attachments/audio.m4a'],
      subtasks: <Subtask>[
        Subtask(id: 'step-1', title: 'Gather notes', createdAt: DateTime(2026, 10, 27), dueAt: DateTime(2026, 11, 2, 11), reminderAt: DateTime(2026, 11, 1, 18), sortOrder: 0),
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
    expect(loaded.parentTaskId, 'parent-group');
    expect(loaded.taskType, TaskType.progressive);
    expect(loaded.progressMode, TaskProgressMode.count);
    expect(loaded.progressValue, 5);
    expect(loaded.progressTarget, 10);
    expect(loaded.progressUnit, 'chapters');
    expect(loaded.difficultyScore, 3.5);
    expect(loaded.sortOrder, 2);
    expect(loaded.notes, task.notes);
    expect(loaded.photoPaths, task.photoPaths);
    expect(loaded.audioPaths, task.audioPaths);
    expect(loaded.subtasks.single.id, 'step-1');
    expect(loaded.subtasks.single.dueAt, DateTime(2026, 11, 2, 11));
    expect(loaded.subtasks.single.reminderAt, DateTime(2026, 11, 1, 18));

    await repo.upsertTask(loaded.copyWith(title: 'Final report'));
    expect(await countRows(db, 'tasks'), 1);
    expect((await repo.loadTasks()).single.title, 'Final report');
  });

  test('progress events and reusable task templates round-trip in SQLite', () async {
    final DateTime created = DateTime(2026, 11, 8, 9);
    final TaskProgressEvent event = TaskProgressEvent(
      id: 'progress-1', taskId: 'task-progress',
      previousValue: 50, newValue: 70,
      previousPercent: 50, newPercent: 70, progressDelta: 20,
      occurredAt: created, difficultyScore: 3.5,
    );
    await repo.addTaskProgressEvent(event);
    expect((await repo.loadTaskProgressEvents()).single.progressDelta, 20);
    expect((await repo.loadTaskProgressEvents()).single.difficultyScore, 3.5);

    final TaskTemplate template = TaskTemplate(
      id: 'template-1', name: 'Academic Revision',
      taskType: TaskType.progressive, progressMode: TaskProgressMode.count,
      progressTarget: 12, progressUnit: 'chapters', difficultyScore: 3.5,
      priority: TaskPriority.high, category: 'Study', iconKey: 'study',
      repeat: TaskRepeat.weekly, createdAt: created, updatedAt: created,
    );
    await repo.upsertTaskTemplate(template);
    final TaskTemplate loaded = (await repo.loadTaskTemplates()).single;
    expect(loaded.name, template.name);
    expect(loaded.taskType, TaskType.progressive);
    expect(loaded.progressMode, TaskProgressMode.count);
    expect(loaded.progressTarget, 12);
    expect(loaded.difficultyScore, 3.5);
    expect(loaded.priority, TaskPriority.high);
    await repo.deleteTaskTemplate(template.id);
    expect(await repo.loadTaskTemplates(), isEmpty);
  });

  test('daily notes preserve photo, audio and video attachment paths', () async {
    final DateTime created = DateTime(2026, 11, 5, 10, 30);
    final Note note = Note(
      id: 'journal-media',
      logDate: DateTime(2026, 11, 5),
      title: 'Field notes',
      body: 'A photo, voice memo and short clip.',
      photoPaths: const <String>['/app/attachments/photo.jpg'],
      audioPaths: const <String>['/app/attachments/audio.m4a'],
      videoPaths: const <String>['/app/attachments/video.mp4'],
      noteType: NoteType.monthly,
      periodDate: DateTime(2026, 11, 1),
      createdAt: created,
      updatedAt: created,
    );

    await repo.upsertNote(note);
    final Note loaded = (await repo.loadNotes()).single;
    expect(loaded, note);
    expect(loaded.videoPaths, note.videoPaths);
    expect(loaded.noteType, NoteType.monthly);
    expect(loaded.periodDate, DateTime(2026, 11, 1));

    await repo.upsertNote(loaded.copyWith(body: 'Updated note'));
    expect((await repo.loadNotes()).single.videoPaths, note.videoPaths);
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
    final List<Map<String, Object?>> subtaskColumns = await db.rawQuery('PRAGMA table_info(subtasks)');
    expect(subtaskColumns.map((Map<String, Object?> column) => column['name']), contains('reminder_at'));
    final List<Map<String, Object?>> taskColumns = await db.rawQuery('PRAGMA table_info(tasks)');
    expect(taskColumns.map((Map<String, Object?> column) => column['name']), containsAll(<String>['parent_task_id', 'task_type', 'progress_value', 'difficulty_score']));
    final List<Map<String, Object?>> noteColumns = await db.rawQuery('PRAGMA table_info(notes)');
    expect(noteColumns.map((Map<String, Object?> column) => column['name']), containsAll(<String>['video_json', 'note_type', 'period_date']));
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
        'expense_categories',
        'expenses',
        'task_templates',
        'task_progress_events',
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

  test('version-4 databases gain video attachment storage without losing notes', () async {
    final String oldPath = p.join(await getDatabasesPath(), 'v4-video-migration-test.db');
    await databaseFactory.deleteDatabase(oldPath);
    final Database oldDb = await databaseFactory.openDatabase(
      oldPath,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (Database database, int version) async {
          await database.execute('''
            CREATE TABLE notes (
              id TEXT PRIMARY KEY,
              habit_id TEXT,
              log_date TEXT,
              title TEXT NOT NULL DEFAULT '',
              body TEXT NOT NULL DEFAULT '',
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              photos_json TEXT NOT NULL DEFAULT '[]',
              audio_json TEXT NOT NULL DEFAULT '[]'
            )
          ''');
          await database.insert('notes', <String, Object?>{
            'id': 'existing-note',
            'title': 'Keep this note',
            'body': 'Existing content must remain unchanged.',
            'log_date': '2026-11-04',
            'created_at': '2026-11-04T08:00:00.000',
            'updated_at': '2026-11-04T08:00:00.000',
          });
        },
      ),
    );
    await oldDb.close();

    final Database upgraded = await AppDatabase.open(path: oldPath);
    try {
      final List<Map<String, Object?>> rows = await upgraded.query('notes');
      expect(rows.single['id'], 'existing-note');
      expect(rows.single['title'], 'Keep this note');
      expect(rows.single['video_json'], '[]');
      expect(await upgraded.getVersion(), AppDatabase.version);
    } finally {
      await upgraded.close();
      await databaseFactory.deleteDatabase(oldPath);
    }
  });

  test('version-3 standalone notes become dated journal entries', () async {
    final String oldPath = p.join(await getDatabasesPath(), 'v3-journal-migration-test.db');
    await databaseFactory.deleteDatabase(oldPath);
    final Database oldDb = await databaseFactory.openDatabase(
      oldPath,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (Database database, int version) async {
          await database.execute('''
            CREATE TABLE notes (
              id TEXT PRIMARY KEY,
              habit_id TEXT,
              title TEXT NOT NULL DEFAULT '',
              body TEXT NOT NULL DEFAULT '',
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              photos_json TEXT NOT NULL DEFAULT '[]',
              audio_json TEXT NOT NULL DEFAULT '[]'
            )
          ''');
          await database.insert('notes', <String, Object?>{
            'id': 'journal-old',
            'title': 'Legacy thought',
            'body': 'Keep this entry',
            'created_at': '2026-10-31T08:15:00.000',
            'updated_at': '2026-10-31T08:15:00.000',
          });
          await database.insert('notes', <String, Object?>{
            'id': 'habit-old',
            'habit_id': 'legacy-habit',
            'title': 'Habit reflection',
            'created_at': '2026-10-31T09:15:00.000',
            'updated_at': '2026-10-31T09:15:00.000',
          });
        },
      ),
    );
    await oldDb.close();

    final Database upgraded = await AppDatabase.open(path: oldPath);
    try {
      final SqliteAppRepository upgradedRepo = SqliteAppRepository(upgraded);
      final List<Note> notes = await upgradedRepo.loadNotes();
      final Note standalone = notes.singleWhere((Note note) => note.id == 'journal-old');
      final Note habitNote = notes.singleWhere((Note note) => note.id == 'habit-old');
      expect(standalone.logDate, DateTime(2026, 10, 31));
      expect(habitNote.logDate, isNull);
      expect(await upgraded.getVersion(), AppDatabase.version);
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
      logDate: DateTime(2026, 10, 27),
      createdAt: DateTime(2026, 10, 27),
      updatedAt: DateTime(2026, 10, 27),
    );
    await repo.upsertNote(n);
    final Note loaded = (await repo.loadNotes()).single;
    expect(loaded.habitId, isNull);
    expect(loaded.logDate, DateTime(2026, 10, 27));
  });

  test('expense categories are seeded and expenses round-trip in paise', () async {
    final List<ExpenseCategory> categories = await repo.loadExpenseCategories();
    expect(categories, hasLength(9));
    expect(categories.every((ExpenseCategory c) => c.isBuiltIn), isTrue);

    final Expense expense = Expense(
      id: 'expense-1',
      amountPaise: 12345,
      expenseDate: DateTime(2026, 11, 4),
      categoryId: categories.first.id,
      description: 'Lunch',
      paymentMethod: 'UPI',
      createdAt: DateTime(2026, 11, 4, 13),
      updatedAt: DateTime(2026, 11, 4, 13),
    );
    await repo.upsertExpense(expense);
    expect((await repo.loadExpenses()).single, expense);

    await repo.upsertExpense(expense.copyWith(amountPaise: 15000));
    expect(await countRows(db, 'expenses'), 1);
    expect((await repo.loadExpenses()).single.amountPaise, 15000);

    await repo.deleteExpense(expense.id);
    expect(await repo.loadExpenses(), isEmpty);
  });

  test('deleting a custom expense category leaves its expenses uncategorised', () async {
    final ExpenseCategory category = ExpenseCategory(
      id: 'custom-category',
      name: 'Coffee',
      sortOrder: 20,
    );
    await repo.upsertExpenseCategory(category);
    await repo.upsertExpense(Expense(
      id: 'expense-2',
      amountPaise: 2500,
      expenseDate: DateTime(2026, 11, 4),
      categoryId: category.id,
      createdAt: DateTime(2026, 11, 4),
      updatedAt: DateTime(2026, 11, 4),
    ));

    await repo.deleteExpenseCategory(category.id);
    expect((await repo.loadExpenses()).single.categoryId, isNull);
    expect(await countRows(db, 'expense_categories'), 9);
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
