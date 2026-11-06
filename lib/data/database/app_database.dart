import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Opens the app's SQLite database and owns the versioned schema.
///
/// Schema version history:
/// * 1 - initial schema (categories, habits, completions, notes, achievements).
/// * 2 - local tasks, subtasks, and immutable task activity history.
/// * 3 - local key/value preferences for appearance and Dashboard layout.
/// * 4 - date-based journal notes and local expense tracking.
/// * 5 - local video attachments for journal notes.
///
/// To change the schema, bump [version], add a step to [_migrations] that
/// upgrades from the previous version, and keep [_createV1] untouched.
class AppDatabase {
  AppDatabase._();

  static const int version = 5;
  static const String fileName = 'tickoff.db';

  /// Opens (creating if needed) the database. Pass [path] to use another file
  /// or `inMemoryDatabasePath` (tests).
  static Future<Database> open({String? path}) async {
    final String dbPath = path ?? p.join(await getDatabasesPath(), fileName);
    return openDatabase(
      dbPath,
      version: version,
      onConfigure: (Database db) async {
        // Enforce relationships (cascade deletes, SET NULL on categories).
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (Database db, int newVersion) async {
        await _createV1(db);
        if (newVersion >= 2) await _migrateV2(db);
        if (newVersion >= 3) await _migrateV3(db);
        if (newVersion >= 4) await _migrateV4(db);
        if (newVersion >= 5) await _migrateV5(db);
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        for (int v = oldVersion; v < newVersion; v++) {
          final Future<void> Function(Database db)? step = _migrations[v];
          if (step != null) await step(db);
        }
      },
    );
  }

  /// Upgrade steps keyed by the version they upgrade FROM (1 -> 2, etc.).
  static final Map<int, Future<void> Function(Database db)> _migrations =
      <int, Future<void> Function(Database db)>{
        1: _migrateV2,
        2: _migrateV3,
        3: _migrateV4,
        4: _migrateV5,
      };



  static Future<void> _migrateV5(Database db) async {
    // Preserve all existing journal and habit notes while adding the optional
    // JSON list used to store local video attachment paths.
    final List<Map<String, Object?>> noteTables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'notes'",
    );
    if (noteTables.isEmpty) return;
    final List<Map<String, Object?>> columns =
        await db.rawQuery('PRAGMA table_info(notes)');
    if (!columns.any((Map<String, Object?> column) =>
        column['name'] == 'video_json')) {
      await db.execute(
        "ALTER TABLE notes ADD COLUMN video_json TEXT NOT NULL DEFAULT '[]'",
      );
    }
  }

  static Future<void> _migrateV4(Database db) async {
    // Existing standalone notes become journal entries on their creation day.
    // Habit-linked notes remain attached to their habit and keep log_date NULL.
    // A defensive table check also supports minimal legacy databases used by
    // migration tests or partially provisioned older installations.
    final List<Map<String, Object?>> noteTables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'notes'",
    );
    if (noteTables.isNotEmpty) {
      final List<Map<String, Object?>> columns = await db.rawQuery('PRAGMA table_info(notes)');
      if (!columns.any((Map<String, Object?> column) => column['name'] == 'log_date')) {
        await db.execute('ALTER TABLE notes ADD COLUMN log_date TEXT');
      }
      await db.execute('''
        UPDATE notes
        SET log_date = substr(created_at, 1, 10)
        WHERE habit_id IS NULL AND log_date IS NULL
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_notes_log_date ON notes(log_date)');
    }

    await db.execute('''
      CREATE TABLE expense_categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL COLLATE NOCASE UNIQUE,
        icon_key TEXT NOT NULL DEFAULT 'category',
        color_value INTEGER NOT NULL DEFAULT 4289170426,
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_builtin INTEGER NOT NULL DEFAULT 0
      )
    ''');

    const List<Map<String, Object>> defaults = <Map<String, Object>>[
      <String, Object>{'id': 'exp_food', 'name': 'Food', 'icon': 'restaurant', 'color': 0xFFFFA726, 'order': 0},
      <String, Object>{'id': 'exp_transport', 'name': 'Transportation', 'icon': 'directions_car', 'color': 0xFF42A5F5, 'order': 1},
      <String, Object>{'id': 'exp_shopping', 'name': 'Shopping', 'icon': 'shopping_bag', 'color': 0xFFAB47BC, 'order': 2},
      <String, Object>{'id': 'exp_education', 'name': 'Education', 'icon': 'school', 'color': 0xFF66BB6A, 'order': 3},
      <String, Object>{'id': 'exp_entertainment', 'name': 'Entertainment', 'icon': 'movie', 'color': 0xFFEC407A, 'order': 4},
      <String, Object>{'id': 'exp_healthcare', 'name': 'Healthcare', 'icon': 'medical_services', 'color': 0xFF26A69A, 'order': 5},
      <String, Object>{'id': 'exp_bills', 'name': 'Bills', 'icon': 'receipt_long', 'color': 0xFF78909C, 'order': 6},
      <String, Object>{'id': 'exp_personal', 'name': 'Personal', 'icon': 'person', 'color': 0xFFFFCA28, 'order': 7},
      <String, Object>{'id': 'exp_others', 'name': 'Others', 'icon': 'more_horiz', 'color': 0xFF90A4AE, 'order': 8},
    ];
    final Batch batch = db.batch();
    for (final Map<String, Object> category in defaults) {
      batch.insert('expense_categories', <String, Object?>{
        'id': category['id'],
        'name': category['name'],
        'icon_key': category['icon'],
        'color_value': category['color'],
        'sort_order': category['order'],
        'is_builtin': 1,
      });
    }
    await batch.commit(noResult: true);

    await db.execute('''
      CREATE TABLE expenses (
        id TEXT PRIMARY KEY,
        amount_paise INTEGER NOT NULL CHECK(amount_paise > 0),
        expense_date TEXT NOT NULL,
        category_id TEXT REFERENCES expense_categories(id) ON DELETE SET NULL,
        description TEXT NOT NULL DEFAULT '',
        payment_method TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_expenses_date ON expenses(expense_date)');
    await db.execute('CREATE INDEX idx_expenses_category ON expenses(category_id)');
  }

  static Future<void> _migrateV3(Database db) async {
    await db.execute('''
      CREATE TABLE app_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL
      )''');
  }

  static Future<void> _migrateV2(Database db) async {
    final Batch batch = db.batch();
    batch.execute('''
      CREATE TABLE tasks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        due_at TEXT,
        reminder_at TEXT,
        priority TEXT NOT NULL DEFAULT 'medium',
        category TEXT NOT NULL DEFAULT '',
        icon_key TEXT NOT NULL DEFAULT 'task',
        color_value INTEGER NOT NULL DEFAULT 4289170426,
        is_completed INTEGER NOT NULL DEFAULT 0,
        completed_at TEXT,
        is_paused INTEGER NOT NULL DEFAULT 0,
        repeat_rule TEXT NOT NULL DEFAULT 'none',
        notes TEXT NOT NULL DEFAULT '',
        photo_paths_json TEXT NOT NULL DEFAULT '[]',
        audio_paths_json TEXT NOT NULL DEFAULT '[]',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )''');
    batch.execute("CREATE INDEX idx_tasks_due ON tasks(due_at)");
    batch.execute("CREATE INDEX idx_tasks_reminder ON tasks(reminder_at)");
    batch.execute('''
      CREATE TABLE subtasks (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
        title TEXT NOT NULL,
        created_at TEXT NOT NULL,
        due_at TEXT,
        is_completed INTEGER NOT NULL DEFAULT 0,
        completed_at TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0
      )''');
    batch.execute('CREATE INDEX idx_subtasks_task ON subtasks(task_id, sort_order)');
    // Deliberately no foreign key to tasks: deletion must not erase history.
    batch.execute('''
      CREATE TABLE task_activities (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        event_type TEXT NOT NULL,
        occurred_at TEXT NOT NULL,
        snapshot_json TEXT NOT NULL DEFAULT '{}'
      )''');
    batch.execute('CREATE INDEX idx_task_activity_time ON task_activities(occurred_at)');
    batch.execute('CREATE INDEX idx_task_activity_task ON task_activities(task_id, occurred_at)');
    await batch.commit(noResult: true);
  }

  static Future<void> _createV1(Database db) async {
    final Batch batch = db.batch();
    batch.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        icon_key TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0
      )''');
    batch.execute('''
      CREATE TABLE habits (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        icon_key TEXT NOT NULL,
        color INTEGER NOT NULL,
        type TEXT NOT NULL,
        tracking TEXT NOT NULL,
        schedule_json TEXT NOT NULL,
        reminder_json TEXT NOT NULL,
        category_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
        show_streaks INTEGER NOT NULL DEFAULT 1,
        daily_goal REAL,
        unit TEXT NOT NULL DEFAULT '',
        step REAL NOT NULL DEFAULT 1,
        checklist_json TEXT NOT NULL DEFAULT '[]',
        created_at TEXT NOT NULL,
        archived_at TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0
      )''');
    // One row per habit and day: the composite primary key makes duplicate
    // completion records impossible.
    batch.execute('''
      CREATE TABLE completions (
        habit_id TEXT NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
        date_key TEXT NOT NULL,
        done INTEGER NOT NULL DEFAULT 0,
        count_value REAL NOT NULL DEFAULT 0,
        checked_ids_json TEXT NOT NULL DEFAULT '[]',
        slipped INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (habit_id, date_key)
      )''');
    batch.execute(
      'CREATE INDEX idx_completions_date ON completions(date_key)',
    );
    batch.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        habit_id TEXT REFERENCES habits(id) ON DELETE CASCADE,
        title TEXT NOT NULL DEFAULT '',
        body TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        photos_json TEXT NOT NULL DEFAULT '[]',
        audio_json TEXT NOT NULL DEFAULT '[]'
      )''');
    batch.execute('CREATE INDEX idx_notes_habit ON notes(habit_id)');
    batch.execute('''
      CREATE TABLE achievements (
        habit_id TEXT NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
        milestone INTEGER NOT NULL,
        unlocked_on TEXT NOT NULL,
        PRIMARY KEY (habit_id, milestone)
      )''');
    await batch.commit(noResult: true);
  }
}
