import '../domain/models/models.dart';

/// Everything loaded from the database, held in memory (a personal habit
/// tracker has at most a few thousand records, so this is fast and simple).
class AppData {
  const AppData({
    this.habits = const <Habit>[],
    this.categories = const <HabitCategory>[],
    this.completions = const <String, Map<String, CompletionRecord>>{},
    this.achievements = const <String, Map<int, String>>{},
    this.notes = const <Note>[],
    this.expenses = const <Expense>[],
    this.expenseCategories = const <ExpenseCategory>[],
    this.tasks = const <Task>[],
    this.taskActivities = const <TaskActivity>[],
    this.taskProgressEvents = const <TaskProgressEvent>[],
    this.taskTemplates = const <TaskTemplate>[],
    this.assignments = const <Assignment>[],
    this.productivityTargets = const <ProductivityTargetChange>[],
    this.productivityTargetOverrides = const <String, double>{},
    this.distractionCategories = const <DistractionCategory>[],
    this.distractionLogs = const <DistractionLog>[],
    this.appUsageRecords = const <AppUsageRecord>[],
    this.appUsageDailyTotals = const <AppUsageDailyTotal>[],
    this.settings = const <String, String>{},
  });

  /// All habits including archived ones.
  final List<Habit> habits;
  final List<HabitCategory> categories;

  /// habitId -> dateKey -> record.
  final Map<String, Map<String, CompletionRecord>> completions;

  /// habitId -> milestone -> unlocked-on date key.
  final Map<String, Map<int, String>> achievements;
  final List<Note> notes;
  final List<Expense> expenses;
  final List<ExpenseCategory> expenseCategories;
  final List<Task> tasks;
  final List<TaskActivity> taskActivities;
  final List<TaskProgressEvent> taskProgressEvents;
  final List<TaskTemplate> taskTemplates;
  final List<Assignment> assignments;
  final List<ProductivityTargetChange> productivityTargets;
  final Map<String, double> productivityTargetOverrides;
  final List<DistractionCategory> distractionCategories;
  final List<DistractionLog> distractionLogs;
  final List<AppUsageRecord> appUsageRecords;
  final List<AppUsageDailyTotal> appUsageDailyTotals;

  /// On-device preferences stored in the SQLite app_settings table.
  final Map<String, String> settings;

  Habit? habitById(String id) {
    for (final Habit h in habits) {
      if (h.id == id) return h;
    }
    return null;
  }

  HabitCategory? categoryById(String? id) {
    if (id == null) return null;
    for (final HabitCategory c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  Map<String, CompletionRecord> recordsFor(String habitId) =>
      completions[habitId] ?? const <String, CompletionRecord>{};

  Map<int, String> achievementsFor(String habitId) =>
      achievements[habitId] ?? const <int, String>{};

  /// Non-archived habits in display order.
  List<Habit> get activeHabits {
    final List<Habit> list =
        habits.where((Habit h) => !h.isArchived).toList();
    list.sort(_byOrder);
    return list;
  }

  List<Habit> get archivedHabits {
    final List<Habit> list = habits.where((Habit h) => h.isArchived).toList();
    list.sort(_byOrder);
    return list;
  }

  List<HabitCategory> get sortedCategories {
    final List<HabitCategory> list = List<HabitCategory>.of(categories);
    list.sort((HabitCategory a, HabitCategory b) {
      final int c = a.sortOrder.compareTo(b.sortOrder);
      return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  List<Note> get sortedNotes {
    final List<Note> list = List<Note>.of(notes);
    list.sort((Note a, Note b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  List<Note> notesForDate(DateTime date) => sortedNotes
      .where((Note note) => note.habitId == null &&
          note.logDate != null &&
          note.logDate!.year == date.year &&
          note.logDate!.month == date.month &&
          note.logDate!.day == date.day)
      .toList();

  List<Note> get habitNotes => sortedNotes
      .where((Note note) => note.habitId != null)
      .toList();

  List<Note> habitNotesForDate(DateTime date) => habitNotes
      .where((Note note) =>
          note.createdAt.year == date.year &&
          note.createdAt.month == date.month &&
          note.createdAt.day == date.day)
      .toList();

  /// All income and expense transactions recorded for a date.
  List<Expense> expensesForDate(DateTime date) {
    final List<Expense> result = expenses.where((Expense expense) =>
      expense.expenseDate.year == date.year &&
      expense.expenseDate.month == date.month &&
      expense.expenseDate.day == date.day).toList();
    result.sort((Expense a, Expense b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  /// All income and expense transactions recorded for a month.
  List<Expense> expensesForMonth(DateTime month) {
    final List<Expense> result = expenses.where((Expense expense) =>
      expense.expenseDate.year == month.year &&
      expense.expenseDate.month == month.month).toList();
    result.sort((Expense a, Expense b) {
      final int byDate = b.expenseDate.compareTo(a.expenseDate);
      return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
    });
    return result;
  }

  List<ExpenseCategory> expenseCategoriesForType(TransactionType type) {
    return sortedExpenseCategories
        .where((ExpenseCategory category) => category.transactionType == type)
        .toList();
  }

  List<ExpenseCategory> get sortedExpenseCategories {
    final List<ExpenseCategory> result = List<ExpenseCategory>.of(expenseCategories);
    result.sort((ExpenseCategory a, ExpenseCategory b) {
      final int order = a.sortOrder.compareTo(b.sortOrder);
      return order != 0 ? order : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }

  ExpenseCategory? expenseCategoryById(String? id) {
    if (id == null) return null;
    for (final ExpenseCategory category in expenseCategories) {
      if (category.id == id) return category;
    }
    return null;
  }

  Task? taskById(String id) {
    for (final Task task in tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  List<Task> childrenForTask(String id) => tasks
      .where((Task task) => task.parentTaskId == id)
      .toList()
    ..sort((Task a, Task b) {
      final int order = a.sortOrder.compareTo(b.sortOrder);
      return order != 0 ? order : a.createdAt.compareTo(b.createdAt);
    });

  bool isGroupTask(Task task) => task.isGroup || childrenForTask(task.id).isNotEmpty;

  /// Returns progress as a fraction from 0.0 to 1.0 for group indicators.
  double progressForTask(Task task) {
    final List<Task> children = childrenForTask(task.id);
    if (children.isEmpty) return task.isGroup ? 0 : task.progressPercent / 100;
    return children.fold<double>(0, (double sum, Task child) => sum + child.progressPercent / 100) / children.length;
  }

  List<TaskProgressEvent> progressHistoryForTask(String id) => taskProgressEvents
      .where((TaskProgressEvent event) => event.taskId == id)
      .toList()
    ..sort((TaskProgressEvent a, TaskProgressEvent b) => a.occurredAt.compareTo(b.occurredAt));

  List<TaskActivity> activitiesForTask(String id) => taskActivities
      .where((TaskActivity a) => a.taskId == id)
      .toList()
    ..sort((TaskActivity a, TaskActivity b) => a.occurredAt.compareTo(b.occurredAt));

  List<Task> get sortedTasks {
    final List<Task> list = List<Task>.of(tasks);
    list.sort((Task a, Task b) {
      if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
      if (a.isPaused != b.isPaused) return a.isPaused ? 1 : -1;
      final bool ao = a.isOverdue;
      final bool bo = b.isOverdue;
      if (ao != bo) return ao ? -1 : 1;
      if (a.dueAt == null && b.dueAt != null) return 1;
      if (a.dueAt != null && b.dueAt == null) return -1;
      final int due = (a.dueAt ?? DateTime(9999)).compareTo(b.dueAt ?? DateTime(9999));
      if (due != 0) return due;
      return b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  double targetForDate(DateTime date) {
    final String key = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final double? override = productivityTargetOverrides[key];
    if (override != null) return override;
    final List<ProductivityTargetChange> changes = List<ProductivityTargetChange>.of(productivityTargets)
      ..sort((a, b) => a.effectiveDate.compareTo(b.effectiveDate));
    double target = 15.0;
    for (final ProductivityTargetChange change in changes) {
      if (change.effectiveDate.compareTo(key) <= 0) target = change.target;
      else break;
    }
    return target;
  }

  int get nextSortOrder {
    int max = -1;
    for (final Habit h in habits) {
      if (h.sortOrder > max) max = h.sortOrder;
    }
    return max + 1;
  }

  static int _byOrder(Habit a, Habit b) {
    final int c = a.sortOrder.compareTo(b.sortOrder);
    return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
  }

  AppData copyWith({
    List<Habit>? habits,
    List<HabitCategory>? categories,
    Map<String, Map<String, CompletionRecord>>? completions,
    Map<String, Map<int, String>>? achievements,
    List<Note>? notes,
    List<Expense>? expenses,
    List<ExpenseCategory>? expenseCategories,
    List<Task>? tasks,
    List<TaskActivity>? taskActivities,
    List<TaskProgressEvent>? taskProgressEvents,
    List<TaskTemplate>? taskTemplates,
    List<Assignment>? assignments,
    List<ProductivityTargetChange>? productivityTargets,
    Map<String, double>? productivityTargetOverrides,
    List<DistractionCategory>? distractionCategories,
    List<DistractionLog>? distractionLogs,
    List<AppUsageRecord>? appUsageRecords,
    List<AppUsageDailyTotal>? appUsageDailyTotals,
    Map<String, String>? settings,
  }) {
    return AppData(
      habits: habits ?? this.habits,
      categories: categories ?? this.categories,
      completions: completions ?? this.completions,
      achievements: achievements ?? this.achievements,
      notes: notes ?? this.notes,
      expenses: expenses ?? this.expenses,
      expenseCategories: expenseCategories ?? this.expenseCategories,
      tasks: tasks ?? this.tasks,
      taskActivities: taskActivities ?? this.taskActivities,
      taskProgressEvents: taskProgressEvents ?? this.taskProgressEvents,
      taskTemplates: taskTemplates ?? this.taskTemplates,
      assignments: assignments ?? this.assignments,
      productivityTargets: productivityTargets ?? this.productivityTargets,
      productivityTargetOverrides: productivityTargetOverrides ?? this.productivityTargetOverrides,
      distractionCategories: distractionCategories ?? this.distractionCategories,
      distractionLogs: distractionLogs ?? this.distractionLogs,
      appUsageRecords: appUsageRecords ?? this.appUsageRecords,
      appUsageDailyTotals: appUsageDailyTotals ?? this.appUsageDailyTotals,
      settings: settings ?? this.settings,
    );
  }
}
