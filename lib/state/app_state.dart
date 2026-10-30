import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/date_utils.dart';
import '../core/utils/ids.dart';
import '../data/repositories/app_repository.dart';
import '../data/services/task_reminder_service.dart';
import '../domain/logic/achievements.dart';
import '../domain/logic/habit_engine.dart';
import '../domain/models/models.dart';
import 'app_data.dart';

/// The persistence layer. `main.dart` overrides this with the SQLite
/// repository; tests override it with an in-memory one.
final Provider<AppRepository> repositoryProvider = Provider<AppRepository>(
  (Ref ref) => throw UnimplementedError('repositoryProvider must be overridden'),
);

/// The current calendar day. Refreshes itself just after midnight.
final Provider<DateTime> todayProvider = Provider<DateTime>((Ref ref) {
  final DateTime now = DateTime.now();
  final DateTime today = dateOnly(now);
  final Timer timer = Timer(
    addDays(today, 1).difference(now) + const Duration(seconds: 1),
    ref.invalidateSelf,
  );
  ref.onDispose(timer.cancel);
  return today;
});

/// Streak / completion / score rules bound to today's date.
final Provider<HabitEngine> habitEngineProvider = Provider<HabitEngine>(
  (Ref ref) => HabitEngine(today: ref.watch(todayProvider)),
);

/// Loads everything from the repository and exposes all changes. Every write
/// goes to the database first and only then updates in-memory state, so what
/// is on screen is always what is stored.
class AppDataNotifier extends AsyncNotifier<AppData> {
  AppRepository get _repo => ref.read(repositoryProvider);

  HabitEngine get _engine => HabitEngine(today: ref.read(todayProvider));

  @override
  Future<AppData> build() async {
    final AppRepository repo = ref.watch(repositoryProvider);
    final List<Habit> habits = await repo.loadHabits();
    final List<HabitCategory> categories = await repo.loadCategories();
    final List<CompletionRecord> records = await repo.loadCompletions();
    final List<Note> notes = await repo.loadNotes();
    final Map<String, Map<int, String>> achievements =
        await repo.loadAchievements();
    final List<Task> tasks = await repo.loadTasks();
    final List<TaskActivity> taskActivities = await repo.loadTaskActivities();
    final Map<String, String> settings = await repo.loadSettings();

    final Map<String, Map<String, CompletionRecord>> index =
        <String, Map<String, CompletionRecord>>{};
    for (final CompletionRecord r in records) {
      index.putIfAbsent(r.habitId, () => <String, CompletionRecord>{})[r.dateKey] = r;
    }

    AppData data = AppData(
      habits: habits,
      categories: categories,
      completions: index,
      achievements: achievements,
      notes: notes,
      tasks: tasks,
      taskActivities: taskActivities,
      settings: settings,
    );
    // Refresh local notifications after every launch. A notification failure
    // never prevents local data from loading.
    for (final Task task in tasks) {
      unawaited(TaskReminderService.instance.scheduleTask(task));
    }
    final DateTime today = ref.read(todayProvider);
    final HabitEngine reminderEngine = HabitEngine(today: today);
    for (final Habit habit in habits.where((Habit h) => !h.isArchived)) {
      final CompletionRecord? todayRecord = index[habit.id]?[dateKey(today)];
      final bool skipToday = habit.type == HabitType.build &&
          reminderEngine.isCompleted(habit, todayRecord);
      unawaited(TaskReminderService.instance.scheduleHabit(
        habit,
        skipToday: skipToday,
      ));
    }
    // Back-fill achievements reached before this version stored them.
    for (final Habit h in habits.where((Habit h) => !h.isArchived)) {
      data = await _syncAchievements(data, h);
    }
    return data;
  }

  AppData get _current {
    final AppData? data = state.valueOrNull;
    if (data == null) throw StateError('App data is not loaded yet.');
    return data;
  }

  /// Re-reads everything from the database.
  Future<void> reload() async {
    state = const AsyncLoading<AppData>();
    state = await AsyncValue.guard(build);
  }

  // ------------------------------------------------------------- achievements

  Future<AppData> _syncAchievements(AppData data, Habit habit) async {
    final HabitStats stats = _engine.stats(habit, data.recordsFor(habit.id));
    final Map<int, String> existing = data.achievementsFor(habit.id);
    final List<int> reached = newlyReached(stats.bestStreak, existing.keys);
    if (reached.isEmpty) return data;
    final String today = dateKey(ref.read(todayProvider));
    final Map<int, String> updated = Map<int, String>.of(existing);
    for (final int m in reached) {
      await _repo.saveAchievement(habit.id, m, today);
      updated[m] = today;
    }
    final Map<String, Map<int, String>> all =
        Map<String, Map<int, String>>.of(data.achievements);
    all[habit.id] = updated;
    return data.copyWith(achievements: all);
  }

  // --------------------------------------------------------------- preferences

  /// Persists a small UI preference locally and publishes it to the app.
  Future<void> saveSetting(String key, String value) async {
    if (state.valueOrNull == null) await future;
    await _repo.saveSetting(key, value);
    final AppData data = _current;
    state = AsyncData<AppData>(data.copyWith(
      settings: <String, String>{...data.settings, key: value},
    ));
  }

  // ------------------------------------------------------------------ habits

  /// Creates or updates a habit after validating it.
  Future<void> saveHabit(Habit habit) async {
    final String? problem = habit.validate();
    if (problem != null) throw ArgumentError(problem);
    AppData data = _current;
    final DateTime today = ref.read(todayProvider);
    final bool skipToday = habit.type == HabitType.build &&
        HabitEngine(today: today).isCompleted(
          habit,
          data.recordsFor(habit.id)[dateKey(today)],
        );
    await _repo.upsertHabit(habit);
    await TaskReminderService.instance.scheduleHabit(
      habit,
      requestPermissions: habit.reminder.enabled,
      skipToday: skipToday,
    );
    final List<Habit> habits = List<Habit>.of(data.habits);
    final int i = habits.indexWhere((Habit h) => h.id == habit.id);
    if (i >= 0) {
      habits[i] = habit;
    } else {
      habits.add(habit);
    }
    data = data.copyWith(habits: habits);
    data = await _syncAchievements(data, habit);
    state = AsyncData<AppData>(data);
  }

  Future<void> setArchived(String habitId, bool archived) async {
    final Habit? habit = _current.habitById(habitId);
    if (habit == null) return;
    await saveHabit(
      archived
          ? habit.copyWith(archivedAt: DateTime.now())
          : habit.copyWith(clearArchived: true),
    );
  }

  /// Permanently deletes a habit, its history, achievements and notes.
  Future<void> deleteHabit(String habitId) async {
    await _repo.deleteHabit(habitId);
    await TaskReminderService.instance.cancelHabit(habitId);
    final AppData data = _current;
    final Map<String, Map<String, CompletionRecord>> completions =
        Map<String, Map<String, CompletionRecord>>.of(data.completions)
          ..remove(habitId);
    final Map<String, Map<int, String>> achievements =
        Map<String, Map<int, String>>.of(data.achievements)..remove(habitId);
    state = AsyncData<AppData>(
      data.copyWith(
        habits: data.habits.where((Habit h) => h.id != habitId).toList(),
        completions: completions,
        achievements: achievements,
        notes: data.notes.where((Note n) => n.habitId != habitId).toList(),
      ),
    );
  }

  // -------------------------------------------------------------- completions

  Future<void> _edit(
    Habit habit,
    DateTime date,
    CompletionRecord Function(CompletionRecord base) change,
  ) async {
    final AppData data = _current;
    final String key = dateKey(date);
    final DateTime now = DateTime.now();
    final CompletionRecord base =
        data.recordsFor(habit.id)[key] ??
        CompletionRecord(habitId: habit.id, dateKey: key, updatedAt: now);
    final CompletionRecord updated = change(base).copyWith(updatedAt: now);

    final Map<String, CompletionRecord> forHabit =
        Map<String, CompletionRecord>.of(data.recordsFor(habit.id));
    if (updated.isBlank) {
      await _repo.deleteCompletion(habit.id, key);
      forHabit.remove(key);
    } else {
      await _repo.upsertCompletion(updated);
      forHabit[key] = updated;
    }
    final Map<String, Map<String, CompletionRecord>> all =
        Map<String, Map<String, CompletionRecord>>.of(data.completions);
    all[habit.id] = forHabit;
    AppData next = data.copyWith(completions: all);
    next = await _syncAchievements(next, habit);
    state = AsyncData<AppData>(next);

    // When a Build habit is completed today, suppress only today's upcoming
    // reminder. Its selected weekday reminder resumes next week. Reopening or
    // reducing a count below goal restores today's reminder if its time has
    // not passed yet.
    final bool completedToday =
        habit.type == HabitType.build &&
        dateOnly(date).isAtSameMomentAs(dateOnly(DateTime.now())) &&
        HabitEngine(today: DateTime.now()).isCompleted(habit, updated);
    unawaited(TaskReminderService.instance.scheduleHabit(
      habit,
      skipToday: completedToday,
    ));
  }

  /// Tick habits: toggles done (Build) or slipped (Quit).
  Future<void> toggleTick(Habit habit, DateTime date) {
    return _edit(habit, date, (CompletionRecord r) {
      return habit.type == HabitType.quit
          ? r.copyWith(slipped: !r.slipped)
          : r.copyWith(done: !r.done);
    });
  }

  /// Count habits: adds [delta] (may be negative); never below zero.
  Future<void> addCount(Habit habit, DateTime date, double delta) {
    if (!delta.isFinite) {
      throw ArgumentError('The count change must be a finite number.');
    }
    return _edit(habit, date, (CompletionRecord r) {
      return r.copyWith(count: _clean(r.count + delta));
    });
  }

  Future<void> decreaseCount(Habit habit, DateTime date) {
    return addCount(habit, date, -habit.step);
  }

  /// Resets the selected day's count only. Other days' records are untouched.
  Future<void> resetCount(Habit habit, DateTime date) {
    return setCount(habit, date, 0);
  }

  Future<void> setCount(Habit habit, DateTime date, double value) {
    if (!value.isFinite || value < 0) {
      throw ArgumentError('The count must be a finite number that is zero or more.');
    }
    return _edit(habit, date, (CompletionRecord r) {
      return r.copyWith(count: _clean(value));
    });
  }

  /// Checklist habits: ticks/unticks one item (Quit: marks/unmarks a slip).
  Future<void> toggleChecklistItem(Habit habit, DateTime date, String itemId) {
    return _edit(habit, date, (CompletionRecord r) {
      final Set<String> ids = Set<String>.of(r.checkedItemIds);
      if (!ids.add(itemId)) ids.remove(itemId);
      return r.copyWith(checkedItemIds: ids);
    });
  }

  static double _clean(double v) {
    final double rounded = (v * 10000).round() / 10000;
    return rounded < 0 ? 0 : rounded;
  }

  // --------------------------------------------------------------------- tasks

  Future<void> _cleanupOrphanedAttachments(Iterable<String> paths) async {
    final AppData data = _current;
    for (final String path in paths.toSet()) {
      final bool taskStillUses = data.tasks.any((Task t) => t.photoPaths.contains(path) || t.audioPaths.contains(path));
      final bool noteStillUses = data.notes.any((Note n) => n.photoPaths.contains(path) || n.audioPaths.contains(path));
      if (taskStillUses || noteStillUses || path.trim().isEmpty) continue;
      try {
        final File file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Missing/unavailable attachment files do not invalidate the task.
      }
    }
  }

  Map<String, dynamic> _taskSnapshot(Task task, {Subtask? subtask}) => <String, dynamic>{
        'title': task.title,
        'description': task.description,
        'dueAt': task.dueAt?.toIso8601String(),
        'reminderAt': task.reminderAt?.toIso8601String(),
        'priority': task.priority.name,
        'category': task.category,
        'isCompleted': task.isCompleted,
        'completedAt': task.completedAt?.toIso8601String(),
        'isPaused': task.isPaused,
        'subtaskCount': task.subtasks.length,
        'hasSubtasks': task.subtasks.isNotEmpty,
        // Snapshot the child set for historical day breakdowns after children
        // are edited, removed, or the parent task is deleted.
        'subtasks': task.subtasks.map((Subtask s) => <String, dynamic>{
          'id': s.id,
          'title': s.title,
          'dueAt': s.dueAt?.toIso8601String(),
          'isCompleted': s.isCompleted,
          'completedAt': s.completedAt?.toIso8601String(),
          'sortOrder': s.sortOrder,
        }).toList(),
        if (subtask != null) ...<String, dynamic>{
          'subtaskId': subtask.id,
          'subtaskTitle': subtask.title,
          'subtaskDueAt': subtask.dueAt?.toIso8601String(),
          'subtaskCompleted': subtask.isCompleted,
          'subtaskCompletedAt': subtask.completedAt?.toIso8601String(),
        },
      };

  Future<void> _recordTaskActivity(
    Task task,
    String eventType, {
    String? entityId,
    String entityType = 'task',
    Subtask? subtask,
    DateTime? occurredAt,
  }) async {
    final DateTime time = occurredAt ?? DateTime.now();
    final TaskActivity activity = TaskActivity(
      id: newId(),
      taskId: task.id,
      entityId: entityId ?? task.id,
      entityType: entityType,
      eventType: eventType,
      occurredAt: time,
      snapshotJson: jsonEncode(_taskSnapshot(task, subtask: subtask)),
    );
    await _repo.addTaskActivity(activity);
    final AppData data = _current;
    state = AsyncData<AppData>(data.copyWith(
      taskActivities: <TaskActivity>[...data.taskActivities, activity],
    ));
  }

  /// Creates or updates a task. Updates retain the same ID and append history.
  Future<void> saveTask(Task task) async {
    final String? issue = task.validate();
    if (issue != null) throw ArgumentError(issue);
    final AppData data = _current;
    final Task? old = data.taskById(task.id);
    final DateTime now = DateTime.now();
    final bool shouldBeCompleted = task.subtasks.isNotEmpty
        ? task.subtasks.every((Subtask subtask) => subtask.isCompleted)
        : task.isCompleted;
    final Task saved = task.copyWith(
      isCompleted: shouldBeCompleted,
      completedAt: shouldBeCompleted ? (task.completedAt ?? now) : null,
      clearCompletedAt: !shouldBeCompleted,
      updatedAt: now,
    );
    await _repo.upsertTask(saved);
    await TaskReminderService.instance.scheduleTask(saved, requestPermissions: saved.reminderAt != null && !saved.isCompleted && !saved.isPaused);
    final List<Task> tasks = List<Task>.of(data.tasks);
    final int at = tasks.indexWhere((Task t) => t.id == saved.id);
    if (at >= 0) {
      tasks[at] = saved;
    } else {
      tasks.add(saved);
    }
    state = AsyncData<AppData>(data.copyWith(tasks: tasks));
    if (old != null) {
      final Set<String> retained = <String>{...saved.photoPaths, ...saved.audioPaths};
      await _cleanupOrphanedAttachments(<String>{...old.photoPaths, ...old.audioPaths}.where((String p) => !retained.contains(p)));
    }
    await _recordTaskActivity(saved, old == null ? 'task_created' : 'task_updated', occurredAt: now);
    if ((old != null && old.isCompleted != saved.isCompleted) || (old == null && saved.isCompleted)) {
      final bool hasChildren = saved.subtasks.isNotEmpty;
      final String event = saved.isCompleted
          ? (hasChildren ? 'task_completed_automatic' : 'task_completed')
          : (hasChildren ? 'task_reopened_automatic' : 'task_reopened');
      await _recordTaskActivity(saved, event, occurredAt: now);
    }
    if (old != null && old.dueAt != saved.dueAt) {
      await _recordTaskActivity(saved, 'deadline_changed', occurredAt: now);
    }

    final Map<String, Subtask> before = <String, Subtask>{
      if (old != null) for (final Subtask subtask in old.subtasks) subtask.id: subtask,
    };
    final Map<String, Subtask> after = <String, Subtask>{
      for (final Subtask subtask in saved.subtasks) subtask.id: subtask,
    };
    for (final Subtask subtask in saved.subtasks) {
      final Subtask? previous = before[subtask.id];
      if (previous == null) {
        await _recordTaskActivity(saved, 'subtask_created', entityId: subtask.id, entityType: 'subtask', subtask: subtask, occurredAt: now);
        if (subtask.isCompleted) {
          await _recordTaskActivity(saved, 'subtask_completed', entityId: subtask.id, entityType: 'subtask', subtask: subtask, occurredAt: subtask.completedAt ?? now);
        }
      } else if (previous.isCompleted != subtask.isCompleted) {
        await _recordTaskActivity(saved, subtask.isCompleted ? 'subtask_completed' : 'subtask_reopened', entityId: subtask.id, entityType: 'subtask', subtask: subtask, occurredAt: subtask.completedAt ?? now);
      } else if (previous.title != subtask.title || previous.dueAt != subtask.dueAt || previous.sortOrder != subtask.sortOrder) {
        await _recordTaskActivity(saved, 'subtask_updated', entityId: subtask.id, entityType: 'subtask', subtask: subtask, occurredAt: now);
      }
    }
    for (final Subtask previous in before.values) {
      if (!after.containsKey(previous.id)) {
        await _recordTaskActivity(saved, 'subtask_deleted', entityId: previous.id, entityType: 'subtask', subtask: previous, occurredAt: now);
      }
    }
  }

  Future<void> setTaskCompleted(String taskId, bool completed) async {
    final AppData data = _current;
    final Task? current = data.taskById(taskId);
    if (current == null) return;
    if (current.isPaused && completed) return;
    if (completed && current.subtasks.any((Subtask s) => !s.isCompleted)) {
      throw ArgumentError('Complete all subtasks before completing this task.');
    }
    if (current.isCompleted == completed) return;
    final DateTime now = DateTime.now();
    final Task updated = current.copyWith(
      isCompleted: completed,
      completedAt: completed ? now : null,
      clearCompletedAt: !completed,
      updatedAt: now,
    );
    await _repo.upsertTask(updated);
    await TaskReminderService.instance.scheduleTask(updated);
    final List<Task> tasks = List<Task>.of(data.tasks);
    tasks[tasks.indexWhere((Task t) => t.id == taskId)] = updated;
    state = AsyncData<AppData>(data.copyWith(tasks: tasks));
    await _recordTaskActivity(updated, completed ? 'task_completed' : 'task_reopened', occurredAt: now);
    if (completed) await _createNextRepeat(updated);
  }

  Future<void> _createNextRepeat(Task completed) async {
    if (completed.repeat == TaskRepeat.none) return;
    int days;
    switch (completed.repeat) {
      case TaskRepeat.none: return;
      case TaskRepeat.daily: days = 1; break;
      case TaskRepeat.weekly: days = 7; break;
      case TaskRepeat.monthly: days = 0; break;
    }
    DateTime? shift(DateTime? value) {
      if (value == null) return null;
      if (completed.repeat == TaskRepeat.monthly) {
        final DateTime nextMonth = DateTime(value.year, value.month + 1, 1);
        final int lastDay = DateTime(nextMonth.year, nextMonth.month + 1, 0).day;
        return DateTime(nextMonth.year, nextMonth.month, value.day > lastDay ? lastDay : value.day, value.hour, value.minute);
      }
      return value.add(Duration(days: days));
    }
    final DateTime now = DateTime.now();
    final List<Subtask> children = completed.subtasks.map((Subtask s) => Subtask(
      id: newId(), title: s.title, createdAt: now, dueAt: shift(s.dueAt), sortOrder: s.sortOrder,
    )).toList();
    final Task next = Task(
      id: newId(), title: completed.title, description: completed.description,
      dueAt: shift(completed.dueAt), reminderAt: shift(completed.reminderAt),
      priority: completed.priority, category: completed.category, iconKey: completed.iconKey,
      colorValue: completed.colorValue, repeat: completed.repeat, notes: completed.notes,
      photoPaths: completed.photoPaths, audioPaths: completed.audioPaths,
      subtasks: children, createdAt: now, updatedAt: now,
    );
    await _repo.upsertTask(next);
    await TaskReminderService.instance.scheduleTask(next);
    final AppData data = _current;
    state = AsyncData<AppData>(data.copyWith(tasks: <Task>[...data.tasks, next]));
    await _recordTaskActivity(next, 'task_created', occurredAt: now);
    for (final Subtask child in children) {
      await _recordTaskActivity(next, 'subtask_created', entityId: child.id, entityType: 'subtask', subtask: child, occurredAt: now);
    }
  }

  Future<void> setTaskPaused(String taskId, bool paused) async {
    final Task? task = _current.taskById(taskId);
    if (task == null || task.isPaused == paused || task.isCompleted) return;
    final Task updated = task.copyWith(isPaused: paused, updatedAt: DateTime.now());
    await _repo.upsertTask(updated);
    await TaskReminderService.instance.scheduleTask(updated);
    final AppData data = _current;
    final List<Task> tasks = List<Task>.of(data.tasks);
    tasks[tasks.indexWhere((Task t) => t.id == taskId)] = updated;
    state = AsyncData<AppData>(data.copyWith(tasks: tasks));
    await _recordTaskActivity(updated, paused ? 'task_paused' : 'task_resumed');
  }

  Future<void> postponeTask(String taskId, {required int days}) async {
    final Task? task = _current.taskById(taskId);
    if (task == null || task.dueAt == null || days <= 0) return;
    final Task updated = task.copyWith(
      dueAt: task.dueAt!.add(Duration(days: days)),
      reminderAt: task.reminderAt?.add(Duration(days: days)),
      updatedAt: DateTime.now(),
    );
    await _repo.upsertTask(updated);
    await TaskReminderService.instance.scheduleTask(updated);
    final AppData data = _current;
    final List<Task> tasks = List<Task>.of(data.tasks);
    tasks[tasks.indexWhere((Task t) => t.id == taskId)] = updated;
    state = AsyncData<AppData>(data.copyWith(tasks: tasks));
    await _recordTaskActivity(updated, 'task_postponed');
  }

  Future<Task?> duplicateTask(String taskId) async {
    final Task? original = _current.taskById(taskId);
    if (original == null) return null;
    final DateTime now = DateTime.now();
    final Task copy = Task(
      id: newId(), title: original.title, description: original.description,
      dueAt: original.dueAt, reminderAt: original.reminderAt,
      priority: original.priority, category: original.category, iconKey: original.iconKey,
      colorValue: original.colorValue, repeat: original.repeat, notes: original.notes,
      photoPaths: original.photoPaths, audioPaths: original.audioPaths,
      subtasks: original.subtasks.map((Subtask s) => Subtask(
        id: newId(), title: s.title, createdAt: now, dueAt: s.dueAt, sortOrder: s.sortOrder,
      )).toList(),
      createdAt: now, updatedAt: now,
    );
    await _repo.upsertTask(copy);
    await TaskReminderService.instance.scheduleTask(copy);
    final AppData data = _current;
    state = AsyncData<AppData>(data.copyWith(tasks: <Task>[...data.tasks, copy]));
    await _recordTaskActivity(copy, 'task_duplicated', occurredAt: now);
    return copy;
  }

  Future<void> deleteTask(String taskId) async {
    final Task? task = _current.taskById(taskId);
    if (task == null) return;
    await _recordTaskActivity(task, 'task_deleted');
    await _repo.deleteTask(taskId);
    await TaskReminderService.instance.cancelTask(taskId);
    final AppData data = _current;
    state = AsyncData<AppData>(data.copyWith(tasks: data.tasks.where((Task t) => t.id != taskId).toList()));
    await _cleanupOrphanedAttachments(<String>{...task.photoPaths, ...task.audioPaths});
  }

  Future<void> toggleSubtask(String taskId, String subtaskId) async {
    final AppData data = _current;
    final Task? task = data.taskById(taskId);
    // Allow subtasks to be reopened after automatic parent completion.
    // The parent status is recalculated below from the updated child states.
    if (task == null || task.isPaused) return;
    final Subtask? selected = task.subtasks.where((Subtask s) => s.id == subtaskId).firstOrNull;
    if (selected == null) return;
    final DateTime now = DateTime.now();
    final bool completing = !selected.isCompleted;
    final List<Subtask> subtasks = task.subtasks.map((Subtask s) => s.id != subtaskId ? s : s.copyWith(
      isCompleted: completing,
      completedAt: completing ? now : null,
      clearCompletedAt: !completing,
    )).toList();
    final bool allDone = subtasks.isNotEmpty && subtasks.every((Subtask s) => s.isCompleted);
    final Task updated = task.copyWith(
      subtasks: subtasks,
      isCompleted: allDone,
      completedAt: allDone ? (task.completedAt ?? now) : null,
      clearCompletedAt: !allDone,
      updatedAt: now,
    );
    await _repo.upsertTask(updated);
    await TaskReminderService.instance.scheduleTask(updated);
    final List<Task> tasks = List<Task>.of(data.tasks);
    tasks[tasks.indexWhere((Task t) => t.id == taskId)] = updated;
    state = AsyncData<AppData>(data.copyWith(tasks: tasks));
    final Subtask changed = subtasks.firstWhere((Subtask s) => s.id == subtaskId);
    await _recordTaskActivity(updated, completing ? 'subtask_completed' : 'subtask_reopened', entityId: subtaskId, entityType: 'subtask', subtask: changed, occurredAt: now);
    if (task.isCompleted != updated.isCompleted) {
      await _recordTaskActivity(updated, allDone ? 'task_completed_automatic' : 'task_reopened_automatic', occurredAt: now);
      if (allDone) await _createNextRepeat(updated);
    }
  }

  Future<void> reorderSubtasks(String taskId, List<Subtask> subtasks) async {
    final Task? task = _current.taskById(taskId);
    if (task == null) return;
    final List<Subtask> ordered = <Subtask>[
      for (int i = 0; i < subtasks.length; i++) subtasks[i].copyWith(sortOrder: i),
    ];
    await saveTask(task.copyWith(subtasks: ordered));
  }

  Future<List<TaskActivity>> taskActivitiesFor(String taskId) async => _current.activitiesForTask(taskId);

  // -------------------------------------------------------------- categories

  Future<void> saveCategory(HabitCategory category) async {
    if (category.name.trim().isEmpty) {
      throw ArgumentError('Please enter a category name.');
    }
    await _repo.upsertCategory(category);
    final AppData data = _current;
    final List<HabitCategory> list = List<HabitCategory>.of(data.categories);
    final int i = list.indexWhere((HabitCategory c) => c.id == category.id);
    if (i >= 0) {
      list[i] = category;
    } else {
      list.add(category);
    }
    state = AsyncData<AppData>(data.copyWith(categories: list));
  }

  Future<void> deleteCategory(String categoryId) async {
    await _repo.deleteCategory(categoryId);
    final AppData data = _current;
    state = AsyncData<AppData>(
      data.copyWith(
        categories:
            data.categories.where((HabitCategory c) => c.id != categoryId).toList(),
        habits: data.habits
            .map((Habit h) =>
                h.categoryId == categoryId ? h.copyWith(clearCategory: true) : h)
            .toList(),
      ),
    );
  }

  // ------------------------------------------------------------------- notes

  Future<void> saveNote(Note note) async {
    await _repo.upsertNote(note);
    final AppData data = _current;
    final List<Note> list = List<Note>.of(data.notes);
    final int i = list.indexWhere((Note n) => n.id == note.id);
    if (i >= 0) {
      list[i] = note;
    } else {
      list.add(note);
    }
    state = AsyncData<AppData>(data.copyWith(notes: list));
  }

  Future<void> deleteNote(String noteId) async {
    await _repo.deleteNote(noteId);
    final AppData data = _current;
    state = AsyncData<AppData>(
      data.copyWith(notes: data.notes.where((Note n) => n.id != noteId).toList()),
    );
  }
}

final AsyncNotifierProvider<AppDataNotifier, AppData> appDataProvider =
    AsyncNotifierProvider<AppDataNotifier, AppData>(AppDataNotifier.new);
final reminderPermissionProvider =
    FutureProvider.autoDispose<ReminderPermissionStatus>(
  (ref) => TaskReminderService.instance.checkPermissions(),
);

/// Stats for every habit, recomputed only when data or the date changes.
final Provider<Map<String, HabitStats>> habitStatsProvider =
    Provider<Map<String, HabitStats>>((Ref ref) {
  final AppData? data = ref.watch(appDataProvider).valueOrNull;
  if (data == null) return const <String, HabitStats>{};
  final HabitEngine engine = ref.watch(habitEngineProvider);
  return <String, HabitStats>{
    for (final Habit h in data.habits)
      h.id: engine.stats(h, data.recordsFor(h.id)),
  };
});

/// Overall Habit Score as a percentage (0..100).
final Provider<double> overallScoreProvider = Provider<double>((Ref ref) {
  final AppData? data = ref.watch(appDataProvider).valueOrNull;
  if (data == null) return 0;
  final Map<String, HabitStats> stats = ref.watch(habitStatsProvider);
  final HabitEngine engine = ref.watch(habitEngineProvider);
  final Iterable<HabitStats> active = data.activeHabits
      .map((Habit h) => stats[h.id])
      .whereType<HabitStats>();
  return engine.overallScore(active) * 100;
});

extension _StateFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
