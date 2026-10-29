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
  final Map<String, Map<int, String>> achievements =
      <String, Map<int, String>>{};
  final Map<String, Task> tasks = <String, Task>{};
  final Map<String, TaskActivity> taskActivities = <String, TaskActivity>{};
  final Map<String, String> settings = <String, String>{};

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
}
