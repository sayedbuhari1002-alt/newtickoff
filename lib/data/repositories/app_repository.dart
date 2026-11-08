import '../../domain/models/models.dart';

/// Everything the app persists. The only implementation shipped in the app is
/// `SqliteAppRepository`; tests also use an in-memory version of this
/// interface for fast widget tests.
abstract class AppRepository {
  // Local application preferences (never synced to a cloud service).
  Future<Map<String, String>> loadSettings();
  Future<void> saveSetting(String key, String value);

  // Habits
  Future<List<Habit>> loadHabits();

  /// Inserts or updates a habit (never replaces, so history is kept).
  Future<void> upsertHabit(Habit habit);

  /// Deletes a habit with its completions, achievements and notes.
  Future<void> deleteHabit(String habitId);

  // Categories
  Future<List<HabitCategory>> loadCategories();
  Future<void> upsertCategory(HabitCategory category);

  /// Deletes a category; habits in it become uncategorised.
  Future<void> deleteCategory(String categoryId);

  // Completions (one record per habit and day)
  Future<List<CompletionRecord>> loadCompletions();
  Future<void> upsertCompletion(CompletionRecord record);
  Future<void> deleteCompletion(String habitId, String dateKey);

  // Notes
  Future<List<Note>> loadNotes();
  Future<void> upsertNote(Note note);
  Future<void> deleteNote(String noteId);

  // Daily expenses and user-defined expense categories.
  Future<List<Expense>> loadExpenses();
  Future<void> upsertExpense(Expense expense);
  Future<void> deleteExpense(String expenseId);
  Future<List<ExpenseCategory>> loadExpenseCategories();
  Future<void> upsertExpenseCategory(ExpenseCategory category);
  Future<void> deleteExpenseCategory(String categoryId);

  // Achievements: habitId -> milestone -> `yyyy-MM-dd` unlocked on
  Future<Map<String, Map<int, String>>> loadAchievements();
  Future<void> saveAchievement(String habitId, int milestone, String unlockedOn);

  // Tasks and immutable history. Deleting a task must not delete its activity.
  Future<List<Task>> loadTasks();
  Future<void> upsertTask(Task task);
  Future<void> deleteTask(String taskId);
  Future<List<TaskActivity>> loadTaskActivities();
  Future<void> addTaskActivity(TaskActivity activity);
  Future<List<TaskProgressEvent>> loadTaskProgressEvents();
  Future<void> addTaskProgressEvent(TaskProgressEvent event);
  Future<List<TaskTemplate>> loadTaskTemplates();
  Future<void> upsertTaskTemplate(TaskTemplate template);
  Future<void> deleteTaskTemplate(String templateId);

  // Productivity features (all local/offline).
  Future<List<Assignment>> loadAssignments();
  Future<void> upsertAssignment(Assignment assignment);
  Future<void> deleteAssignment(String assignmentId);
  Future<List<ProductivityTargetChange>> loadProductivityTargets();
  Future<void> upsertProductivityTarget(ProductivityTargetChange change);
  Future<Map<String, double>> loadProductivityTargetOverrides();
  Future<void> upsertProductivityTargetOverride(String dateKey, double target);
  Future<void> deleteProductivityTargetOverride(String dateKey);
  Future<List<DistractionCategory>> loadDistractionCategories();
  Future<void> upsertDistractionCategory(DistractionCategory category);
  Future<void> deleteDistractionCategory(String categoryId);
  Future<List<DistractionLog>> loadDistractionLogs();
  Future<void> upsertDistractionLog(DistractionLog log);
  Future<void> deleteDistractionLog(String logId);
  Future<List<AppUsageRecord>> loadAppUsageRecords();
  Future<void> upsertAppUsageRecord(AppUsageRecord record);
  Future<void> deleteAppUsageRecordsForDate(String dateKey);
}
