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
    this.tasks = const <Task>[],
    this.taskActivities = const <TaskActivity>[],
  });

  /// All habits including archived ones.
  final List<Habit> habits;
  final List<HabitCategory> categories;

  /// habitId -> dateKey -> record.
  final Map<String, Map<String, CompletionRecord>> completions;

  /// habitId -> milestone -> unlocked-on date key.
  final Map<String, Map<int, String>> achievements;
  final List<Note> notes;
  final List<Task> tasks;
  final List<TaskActivity> taskActivities;

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

  Task? taskById(String id) {
    for (final Task task in tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

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
    List<Task>? tasks,
    List<TaskActivity>? taskActivities,
  }) {
    return AppData(
      habits: habits ?? this.habits,
      categories: categories ?? this.categories,
      completions: completions ?? this.completions,
      achievements: achievements ?? this.achievements,
      notes: notes ?? this.notes,
      tasks: tasks ?? this.tasks,
      taskActivities: taskActivities ?? this.taskActivities,
    );
  }
}
