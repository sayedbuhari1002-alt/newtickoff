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
/// * 6 - note categories/periods and independent subtask reminder timestamps.
/// * 7 - first-class task groups, progressive task fields, templates and progress history.
/// * 8 - Productivity targets, assignments, distractions and scoring metadata.
/// * 9 - daily Android UsageStats totals and reconciliation against event sessions.
/// * 10 - income/expense transaction types and separate income categories.
///
/// To change the schema, bump [version], add a step to [_migrations] that
/// upgrades from the previous version, and keep [_createV1] untouched.
class AppDatabase {
  AppDatabase._();

  static const int version = 10;
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
        if (newVersion >= 6) await _migrateV6(db);
        if (newVersion >= 7) await _migrateV7(db);
        if (newVersion >= 8) await _migrateV8(db);
        if (newVersion >= 9) await _migrateV9(db);
        if (newVersion >= 10) await _migrateV10(db);
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
        5: _migrateV6,
        6: _migrateV7,
        7: _migrateV8,
        8: _migrateV9,
        9: _migrateV10,
      };






  static Future<void> _migrateV8(Database db) async {
    // Additive migration only: all existing habits, tasks and history remain intact.
    // Some historical test/import databases contain only a subset of the original
    // tables. Guard each ALTER so those databases can still reach the latest schema.
    final List<Map<String, Object?>> tableRows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final Set<String> tables = tableRows.map((Map<String, Object?> row) => row['name'] as String).toSet();

    if (tables.contains('habits')) {
      final List<Map<String, Object?>> columns = await db.rawQuery('PRAGMA table_info(habits)');
      final Set<String> names = columns.map((Map<String, Object?> c) => c['name'] as String).toSet();
      if (!names.contains('productivity_points')) await db.execute('ALTER TABLE habits ADD COLUMN productivity_points REAL NOT NULL DEFAULT 1.0');
      if (!names.contains('quit_penalty')) await db.execute('ALTER TABLE habits ADD COLUMN quit_penalty REAL NOT NULL DEFAULT 2.0');
    }
    if (tables.contains('completions')) {
      final List<Map<String, Object?>> columns = await db.rawQuery('PRAGMA table_info(completions)');
      final Set<String> names = columns.map((Map<String, Object?> c) => c['name'] as String).toSet();
      if (!names.contains('productivity_points')) await db.execute('ALTER TABLE completions ADD COLUMN productivity_points REAL NOT NULL DEFAULT 1.0');
      if (!names.contains('quit_penalty')) await db.execute('ALTER TABLE completions ADD COLUMN quit_penalty REAL NOT NULL DEFAULT 2.0');
      if (!names.contains('habit_type')) await db.execute('ALTER TABLE completions ADD COLUMN habit_type TEXT');
      if (!names.contains('tracking_method')) await db.execute('ALTER TABLE completions ADD COLUMN tracking_method TEXT');
      if (!names.contains('daily_goal_snapshot')) await db.execute('ALTER TABLE completions ADD COLUMN daily_goal_snapshot REAL');
      if (!names.contains('checklist_ids_snapshot_json')) await db.execute("ALTER TABLE completions ADD COLUMN checklist_ids_snapshot_json TEXT");
      if (tables.contains('habits')) {
        await db.execute('''
          UPDATE completions SET
            habit_type = COALESCE(habit_type, (SELECT type FROM habits WHERE habits.id = completions.habit_id)),
            tracking_method = COALESCE(tracking_method, (SELECT tracking FROM habits WHERE habits.id = completions.habit_id)),
            daily_goal_snapshot = COALESCE(daily_goal_snapshot, (SELECT daily_goal FROM habits WHERE habits.id = completions.habit_id)),
            checklist_ids_snapshot_json = COALESCE(checklist_ids_snapshot_json, (SELECT checklist_json FROM habits WHERE habits.id = completions.habit_id))
          WHERE habit_type IS NULL OR tracking_method IS NULL OR checklist_ids_snapshot_json IS NULL
        ''');
      }
    }
    if (tables.contains('tasks')) {
      final List<Map<String, Object?>> columns = await db.rawQuery('PRAGMA table_info(tasks)');
      final Set<String> names = columns.map((Map<String, Object?> c) => c['name'] as String).toSet();
      if (!names.contains('scheduled_date')) await db.execute('ALTER TABLE tasks ADD COLUMN scheduled_date TEXT');
    }
    if (tables.contains('subtasks')) {
      final List<Map<String, Object?>> columns = await db.rawQuery('PRAGMA table_info(subtasks)');
      final Set<String> names = columns.map((Map<String, Object?> c) => c['name'] as String).toSet();
      if (!names.contains('difficulty_score')) await db.execute('ALTER TABLE subtasks ADD COLUMN difficulty_score REAL NOT NULL DEFAULT 1.0');
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS assignments (
        id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
        due_at TEXT, priority TEXT NOT NULL DEFAULT 'medium', difficulty_score REAL NOT NULL DEFAULT 1.0,
        category TEXT NOT NULL DEFAULT '', is_completed INTEGER NOT NULL DEFAULT 0,
        completed_at TEXT, completed_points REAL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_assignments_due ON assignments(due_at)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS productivity_target_history (
        effective_date TEXT PRIMARY KEY, target REAL NOT NULL CHECK(target > 0)
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS productivity_target_overrides (
        date_key TEXT PRIMARY KEY, target REAL NOT NULL CHECK(target > 0)
      )''');
    await db.insert('productivity_target_history', <String, Object?>{
      'effective_date': '0001-01-01', 'target': 15.0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS distraction_categories (
        id TEXT PRIMARY KEY, name TEXT NOT NULL COLLATE NOCASE UNIQUE,
        severity_points_per_hour REAL NOT NULL DEFAULT 1.0,
        details TEXT NOT NULL DEFAULT '', auto_track INTEGER NOT NULL DEFAULT 0,
        package_names_json TEXT NOT NULL DEFAULT '[]', created_at TEXT NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS distraction_logs (
        id TEXT PRIMARY KEY,
        category_id TEXT NOT NULL REFERENCES distraction_categories(id) ON DELETE CASCADE,
        start_at TEXT NOT NULL, end_at TEXT NOT NULL, details TEXT NOT NULL DEFAULT '',
        severity_points_per_hour REAL
      )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_distraction_logs_time ON distraction_logs(start_at, end_at)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_usage_records (
        id TEXT PRIMARY KEY,
        category_id TEXT NOT NULL REFERENCES distraction_categories(id) ON DELETE CASCADE,
        package_name TEXT NOT NULL, start_at TEXT NOT NULL, end_at TEXT NOT NULL,
        severity_points_per_hour REAL
      )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_app_usage_time ON app_usage_records(start_at, end_at)');
  }

  static Future<void> _migrateV9(Database db) async {
    // Store Android's daily foreground totals separately from timestamped event
    // sessions. Aggregate totals are authoritative for daily display, while
    // sessions retain their real boundaries for overlap-aware productivity scoring.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_usage_daily_totals (
        id TEXT PRIMARY KEY,
        date_key TEXT NOT NULL,
        category_id TEXT NOT NULL REFERENCES distraction_categories(id) ON DELETE CASCADE,
        package_name TEXT NOT NULL,
        android_foreground_ms INTEGER NOT NULL DEFAULT 0,
        reconstructed_ms INTEGER NOT NULL DEFAULT 0,
        native_stats_available INTEGER NOT NULL DEFAULT 0,
        UNIQUE(date_key, package_name)
      )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_app_usage_daily_date ON app_usage_daily_totals(date_key)');
  }

  static Future<void> _migrateV10(Database db) async {
    // Existing rows are expenses by default, preserving historical meaning.
    final List<Map<String, Object?>> expenseColumns = await db.rawQuery(
      'PRAGMA table_info(expenses)',
    );
    final Set<String> expenseNames = expenseColumns
        .map((Map<String, Object?> column) => column['name'] as String)
        .toSet();
    if (expenseNames.isNotEmpty && !expenseNames.contains('transaction_type')) {
      await db.execute(
        "ALTER TABLE expenses ADD COLUMN transaction_type TEXT NOT NULL DEFAULT 'expense'",
      );
    }

    final List<Map<String, Object?>> categoryColumns = await db.rawQuery(
      'PRAGMA table_info(expense_categories)',
    );
    final Set<String> categoryNames = categoryColumns
        .map((Map<String, Object?> column) => column['name'] as String)
        .toSet();
    if (categoryNames.isNotEmpty && !categoryNames.contains('transaction_type')) {
      await db.execute(
        "ALTER TABLE expense_categories ADD COLUMN transaction_type TEXT NOT NULL DEFAULT 'expense'",
      );
    }

    if (categoryNames.isNotEmpty) {
      const List<Map<String, Object>> incomeCategories = <Map<String, Object>>[
        <String, Object>{'id': 'inc_salary', 'name': 'Salary', 'icon': 'payments', 'color': 0xFF66BB6A, 'order': 0},
        <String, Object>{'id': 'inc_freelance', 'name': 'Freelance', 'icon': 'work', 'color': 0xFF26A69A, 'order': 1},
        <String, Object>{'id': 'inc_business', 'name': 'Business', 'icon': 'business', 'color': 0xFF42A5F5, 'order': 2},
        <String, Object>{'id': 'inc_investment', 'name': 'Investment', 'icon': 'trending_up', 'color': 0xFFAB47BC, 'order': 3},
        <String, Object>{'id': 'inc_interest', 'name': 'Interest', 'icon': 'savings', 'color': 0xFF26A69A, 'order': 4},
        <String, Object>{'id': 'inc_gift', 'name': 'Gift', 'icon': 'card_giftcard', 'color': 0xFFFFA726, 'order': 5},
        <String, Object>{'id': 'inc_other', 'name': 'Other income', 'icon': 'more_horiz', 'color': 0xFF90A4AE, 'order': 6},
      ];
      for (final Map<String, Object> category in incomeCategories) {
        await db.insert(
          'expense_categories',
          <String, Object?>{
            'id': category['id'],
            'name': category['name'],
            'icon_key': category['icon'],
            'color_value': category['color'],
            'sort_order': category['order'],
            'is_builtin': 1,
            'transaction_type': 'income',
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
  }

  static Future<void> _migrateV7(Database db) async {
    final List<Map<String, Object?>> taskTables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'tasks'",
    );
    if (taskTables.isNotEmpty) {
      final List<Map<String, Object?>> columns = await db.rawQuery('PRAGMA table_info(tasks)');
      final Set<String> existing = columns.map((Map<String, Object?> c) => c['name'] as String).toSet();
      final List<String> additions = <String>[
        if (!existing.contains('parent_task_id')) 'ALTER TABLE tasks ADD COLUMN parent_task_id TEXT',
        if (!existing.contains('is_group')) 'ALTER TABLE tasks ADD COLUMN is_group INTEGER NOT NULL DEFAULT 0',
        if (!existing.contains('task_type')) "ALTER TABLE tasks ADD COLUMN task_type TEXT NOT NULL DEFAULT 'standard'",
        if (!existing.contains('progress_mode')) "ALTER TABLE tasks ADD COLUMN progress_mode TEXT NOT NULL DEFAULT 'percentage'",
        if (!existing.contains('progress_value')) 'ALTER TABLE tasks ADD COLUMN progress_value REAL NOT NULL DEFAULT 0',
        if (!existing.contains('progress_target')) 'ALTER TABLE tasks ADD COLUMN progress_target REAL NOT NULL DEFAULT 100',
        if (!existing.contains('progress_unit')) "ALTER TABLE tasks ADD COLUMN progress_unit TEXT NOT NULL DEFAULT ''",
        if (!existing.contains('difficulty_score')) 'ALTER TABLE tasks ADD COLUMN difficulty_score REAL NOT NULL DEFAULT 1.0',
        if (!existing.contains('sort_order')) 'ALTER TABLE tasks ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0',
      ];
      for (final String sql in additions) {
        await db.execute(sql);
      }
      await db.execute('CREATE INDEX IF NOT EXISTS idx_tasks_parent ON tasks(parent_task_id, sort_order)');
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS task_progress_events (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        previous_value REAL NOT NULL DEFAULT 0,
        new_value REAL NOT NULL DEFAULT 0,
        previous_percent REAL NOT NULL DEFAULT 0,
        new_percent REAL NOT NULL DEFAULT 0,
        progress_delta REAL NOT NULL DEFAULT 0,
        difficulty_score REAL NOT NULL DEFAULT 1.0,
        occurred_at TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT ''
      )''');
    final List<Map<String, Object?>> progressColumns = await db.rawQuery('PRAGMA table_info(task_progress_events)');
    if (!progressColumns.any((Map<String, Object?> column) => column['name'] == 'difficulty_score')) {
      await db.execute('ALTER TABLE task_progress_events ADD COLUMN difficulty_score REAL NOT NULL DEFAULT 1.0');
    }
    await db.execute('CREATE INDEX IF NOT EXISTS idx_task_progress_task_time ON task_progress_events(task_id, occurred_at)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS task_templates (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL COLLATE NOCASE UNIQUE,
        task_type TEXT NOT NULL DEFAULT 'standard',
        progress_mode TEXT NOT NULL DEFAULT 'percentage',
        progress_target REAL NOT NULL DEFAULT 100,
        progress_unit TEXT NOT NULL DEFAULT '',
        difficulty_score REAL NOT NULL DEFAULT 1.0,
        priority TEXT NOT NULL DEFAULT 'medium',
        category TEXT NOT NULL DEFAULT '',
        icon_key TEXT NOT NULL DEFAULT 'task',
        color_value INTEGER NOT NULL DEFAULT 4289170426,
        repeat_rule TEXT NOT NULL DEFAULT 'none',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_task_templates_name ON task_templates(name COLLATE NOCASE)');
  }

  static Future<void> _migrateV6(Database db) async {
    final List<Map<String, Object?>> noteTables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'notes'",
    );
    if (noteTables.isNotEmpty) {
      final List<Map<String, Object?>> columns = await db.rawQuery('PRAGMA table_info(notes)');
      if (!columns.any((column) => column['name'] == 'note_type')) {
        await db.execute("ALTER TABLE notes ADD COLUMN note_type TEXT NOT NULL DEFAULT 'daily'");
      }
      if (!columns.any((column) => column['name'] == 'period_date')) {
        await db.execute('ALTER TABLE notes ADD COLUMN period_date TEXT');
      }
      // Old standalone notes were Daily Log entries after migration v4;
      // habit notes remain linked and are intentionally excluded from Library.
      await db.execute("UPDATE notes SET note_type = CASE WHEN log_date IS NULL THEN 'general' ELSE 'daily' END WHERE habit_id IS NULL");
      await db.execute('CREATE INDEX IF NOT EXISTS idx_notes_type_period ON notes(note_type, period_date)');
    }
    final List<Map<String, Object?>> subtaskTables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'subtasks'",
    );
    if (subtaskTables.isNotEmpty) {
      final List<Map<String, Object?>> columns = await db.rawQuery('PRAGMA table_info(subtasks)');
      if (!columns.any((column) => column['name'] == 'reminder_at')) {
        await db.execute('ALTER TABLE subtasks ADD COLUMN reminder_at TEXT');
      }
      await db.execute('CREATE INDEX IF NOT EXISTS idx_subtasks_reminder ON subtasks(reminder_at)');
    }
  }

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
        reminder_at TEXT,
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
        productivity_points REAL NOT NULL DEFAULT 1.0,
        quit_penalty REAL NOT NULL DEFAULT 2.0,
        habit_type TEXT,
        tracking_method TEXT,
        daily_goal_snapshot REAL,
        checklist_ids_snapshot_json TEXT,
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
