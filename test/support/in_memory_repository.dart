import 'package:tickoff_replacement/data/repositories/app_repository.dart';
import 'package:tickoff_replacement/domain/models/models.dart';

/// Fast in-memory [AppRepository] used by widget and state tests. It mirrors
/// the relationships the SQLite schema enforces (cascade deletes, categories
/// set to null) so behaviour matches; the real SQLite code has its own tests
/// in test/data.
class InMemoryAppRepository implements AppRepository {
  final Map<String, Habit> habits = <String, Habit>{};
  final Map<String, HabitCategory> categories = <String, HabitCategory>{};
  final Map<String, CompletionRecord> records = <String, CompletionRecord>{};
  final Map<String, Note> notes = <String, Note>{};
  final Map<String, Expense> expenses = <String, Expense>{};
  final Map<String, ExpenseCategory> expenseCategories = <String, ExpenseCategory>{};
  final Map<String, Map<int, String>> achievements =
      <String, Map<int, String>>{};
  final Map<String, Task> tasks = <String, Task>{};
  final Map<String, TaskActivity> taskActivities = <String, TaskActivity>{};
  final Map<String, TaskProgressEvent> taskProgressEvents = <String, TaskProgressEvent>{};
  final Map<String, TaskTemplate> taskTemplates = <String, TaskTemplate>{};
  final Map<String, String> settings = <String, String>{};
  final Map<String, Assignment> assignments = <String, Assignment>{};
  final Map<String, ProductivityTargetChange> productivityTargets = <String, ProductivityTargetChange>{
    '0001-01-01': const ProductivityTargetChange(effectiveDate: '0001-01-01', target: 15),
  };
  final Map<String, double> productivityTargetOverrides = <String, double>{};
  final Map<String, DistractionCategory> distractionCategories = <String, DistractionCategory>{};
  final Map<String, DistractionLog> distractionLogs = <String, DistractionLog>{};
  final Map<String, AppUsageRecord> appUsageRecords = <String, AppUsageRecord>{};

  @override
  Future<Map<String, String>> loadSettings() async => Map<String, String>.of(settings);

  @override
  Future<void> saveSetting(String key, String value) async => settings[key] = value;

  @override
  Future<List<Habit>> loadHabits() async => habits.values.toList();

  @override
  Future<void> upsertHabit(Habit habit) async => habits[habit.id] = habit;

  @override
  Future<void> deleteHabit(String habitId) async {
    habits.remove(habitId);
    records.removeWhere((String _, CompletionRecord r) => r.habitId == habitId);
    notes.removeWhere((String _, Note n) => n.habitId == habitId);
    achievements.remove(habitId);
  }

  @override
  Future<List<HabitCategory>> loadCategories() async =>
      categories.values.toList();

  @override
  Future<void> upsertCategory(HabitCategory category) async =>
      categories[category.id] = category;

  @override
  Future<void> deleteCategory(String categoryId) async {
    categories.remove(categoryId);
    for (final String id in habits.keys.toList()) {
      final Habit h = habits[id]!;
      if (h.categoryId == categoryId) {
        habits[id] = h.copyWith(clearCategory: true);
      }
    }
  }

  @override
  Future<List<CompletionRecord>> loadCompletions() async =>
      records.values.toList();

  @override
  Future<void> upsertCompletion(CompletionRecord record) async =>
      records[record.key] = record;

  @override
  Future<void> deleteCompletion(String habitId, String dateKey) async =>
      records.remove('$habitId|$dateKey');

  @override
  Future<List<Note>> loadNotes() async => notes.values.toList();

  @override
  Future<void> upsertNote(Note note) async => notes[note.id] = note;

  @override
  Future<void> deleteNote(String noteId) async => notes.remove(noteId);

  @override
  Future<List<Expense>> loadExpenses() async => expenses.values.toList();

  @override
  Future<void> upsertExpense(Expense expense) async => expenses[expense.id] = expense;

  @override
  Future<void> deleteExpense(String expenseId) async => expenses.remove(expenseId);

  @override
  Future<List<ExpenseCategory>> loadExpenseCategories() async => expenseCategories.values.toList();

  @override
  Future<void> upsertExpenseCategory(ExpenseCategory category) async => expenseCategories[category.id] = category;

  @override
  Future<void> deleteExpenseCategory(String categoryId) async {
    expenseCategories.remove(categoryId);
    for (final String id in expenses.keys.toList()) {
      final Expense expense = expenses[id]!;
      if (expense.categoryId == categoryId) {
        expenses[id] = expense.copyWith(clearCategory: true);
      }
    }
  }

  @override
  Future<Map<String, Map<int, String>>> loadAchievements() async =>
      achievements.map(
        (String k, Map<int, String> v) =>
            MapEntry<String, Map<int, String>>(k, Map<int, String>.of(v)),
      );

  @override
  Future<List<Task>> loadTasks() async => tasks.values.toList();

  @override
  Future<void> upsertTask(Task task) async => tasks[task.id] = task;

  @override
  Future<void> deleteTask(String taskId) async => tasks.remove(taskId);

  @override
  Future<List<TaskActivity>> loadTaskActivities() async => taskActivities.values.toList()
    ..sort((TaskActivity a, TaskActivity b) => a.occurredAt.compareTo(b.occurredAt));

  @override
  Future<void> addTaskActivity(TaskActivity activity) async => taskActivities[activity.id] = activity;

  @override
  Future<List<TaskProgressEvent>> loadTaskProgressEvents() async => taskProgressEvents.values.toList()
    ..sort((TaskProgressEvent a, TaskProgressEvent b) => a.occurredAt.compareTo(b.occurredAt));

  @override
  Future<void> addTaskProgressEvent(TaskProgressEvent event) async => taskProgressEvents[event.id] = event;

  @override
  Future<List<TaskTemplate>> loadTaskTemplates() async => taskTemplates.values.toList()
    ..sort((TaskTemplate a, TaskTemplate b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  @override
  Future<void> upsertTaskTemplate(TaskTemplate template) async => taskTemplates[template.id] = template;

  @override
  Future<void> deleteTaskTemplate(String templateId) async => taskTemplates.remove(templateId);

  @override
  Future<void> saveAchievement(
    String habitId,
    int milestone,
    String unlockedOn,
  ) async {
    achievements.putIfAbsent(habitId, () => <int, String>{}).putIfAbsent(
          milestone,
          () => unlockedOn,
        );
  }

  @override
  Future<List<Assignment>> loadAssignments() async => assignments.values.toList();
  @override
  Future<void> upsertAssignment(Assignment value) async => assignments[value.id] = value;
  @override
  Future<void> deleteAssignment(String id) async => assignments.remove(id);
  @override
  Future<List<ProductivityTargetChange>> loadProductivityTargets() async => productivityTargets.values.toList()..sort((a, b) => a.effectiveDate.compareTo(b.effectiveDate));
  @override
  Future<void> upsertProductivityTarget(ProductivityTargetChange value) async => productivityTargets[value.effectiveDate] = value;
  @override
  Future<Map<String, double>> loadProductivityTargetOverrides() async => Map<String, double>.of(productivityTargetOverrides);
  @override
  Future<void> upsertProductivityTargetOverride(String key, double value) async => productivityTargetOverrides[key] = value;
  @override
  Future<void> deleteProductivityTargetOverride(String key) async => productivityTargetOverrides.remove(key);
  @override
  Future<List<DistractionCategory>> loadDistractionCategories() async => distractionCategories.values.toList();
  @override
  Future<void> upsertDistractionCategory(DistractionCategory value) async => distractionCategories[value.id] = value;
  @override
  Future<void> deleteDistractionCategory(String id) async { distractionCategories.remove(id); distractionLogs.removeWhere((_, value) => value.categoryId == id); appUsageRecords.removeWhere((_, value) => value.categoryId == id); }
  @override
  Future<List<DistractionLog>> loadDistractionLogs() async => distractionLogs.values.toList();
  @override
  Future<void> upsertDistractionLog(DistractionLog value) async => distractionLogs[value.id] = value;
  @override
  Future<void> deleteDistractionLog(String id) async => distractionLogs.remove(id);
  @override
  Future<List<AppUsageRecord>> loadAppUsageRecords() async => appUsageRecords.values.toList();
  @override
  Future<void> upsertAppUsageRecord(AppUsageRecord value) async => appUsageRecords[value.id] = value;
  @override
  Future<void> deleteAppUsageRecordsForDate(String key) async { final DateTime day = DateTime.parse(key); appUsageRecords.removeWhere((_, r) => r.startAt.isBefore(day.add(const Duration(days: 1))) && r.endAt.isAfter(day)); }

}
