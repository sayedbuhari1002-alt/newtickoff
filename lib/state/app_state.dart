import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/date_utils.dart';
import '../core/utils/ids.dart';
import '../data/repositories/app_repository.dart';
import '../data/services/task_reminder_service.dart';
import '../domain/logic/achievements.dart';
import '../domain/logic/habit_engine.dart';
import '../domain/models/models.dart';
import 'app_data.dart';
import 'app_settings.dart';

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
    final List<Expense> expenses = await repo.loadExpenses();
    final List<ExpenseCategory> expenseCategories = await repo.loadExpenseCategories();
    final Map<String, Map<int, String>> achievements =
        await repo.loadAchievements();
    final List<Task> tasks = await repo.loadTasks();
    final List<TaskActivity> taskActivities = await repo.loadTaskActivities();
    final List<TaskProgressEvent> taskProgressEvents = await repo.loadTaskProgressEvents();
    final List<TaskTemplate> taskTemplates = await repo.loadTaskTemplates();
    final List<Assignment> assignments = await repo.loadAssignments();
    final List<ProductivityTargetChange> productivityTargets = await repo.loadProductivityTargets();
    final Map<String, double> productivityTargetOverrides = await repo.loadProductivityTargetOverrides();
    final List<DistractionCategory> distractionCategories = await repo.loadDistractionCategories();
    final List<DistractionLog> distractionLogs = await repo.loadDistractionLogs();
    final List<AppUsageRecord> appUsageRecords = await repo.loadAppUsageRecords();
    final List<AppUsageDailyTotal> appUsageDailyTotals = await repo.loadAppUsageDailyTotals();
    final Map<String, String> settings = await repo.loadSettings();
    // Record the first day this version's live-state scoring model is active.
    // Historical dates before this boundary continue using the old scoring
    // calculation, so upgrading does not silently change existing history.
    final String scoringStartKey = AppSettingKeys.productivityScoringStartDate;
    final String? storedScoringStart = settings[scoringStartKey];
    if (storedScoringStart == null || DateTime.tryParse(storedScoringStart) == null) {
      final String effectiveDate = dateKey(ref.read(todayProvider));
      await repo.saveSetting(scoringStartKey, effectiveDate);
      settings[scoringStartKey] = effectiveDate;
    }

    final Map<String, Map<String, CompletionRecord>> index =
        <String, Map<String, CompletionRecord>>{};
    for (final CompletionRecord r in records) {
      index.putIfAbsent(r.habitId, () => <String, CompletionRecord>{})[r.dateKey] = r;
    }

    // Reconcile only the still-open calendar day on launch. This also repairs
    // a current-day completion created by an older app build before the user
    // upgrades: the final settings currently shown by the habit form become
    // the snapshot that will be read after midnight. Past dates are untouched.
    final String openDateKey = dateKey(ref.read(todayProvider));
    for (final Habit habit in habits) {
      final CompletionRecord? openDayRecord = index[habit.id]?[openDateKey];
      if (openDayRecord == null) continue;
      final CompletionRecord refreshed =
          _refreshHabitDaySnapshot(openDayRecord, habit);
      if (refreshed != openDayRecord) {
        await repo.upsertCompletion(refreshed);
        index[habit.id]![openDateKey] = refreshed;
      }
    }

    AppData data = AppData(
      habits: habits,
      categories: categories,
      completions: index,
      achievements: achievements,
      notes: notes,
      expenses: expenses,
      expenseCategories: expenseCategories,
      tasks: tasks,
      taskActivities: taskActivities,
      taskProgressEvents: taskProgressEvents,
      taskTemplates: taskTemplates,
      assignments: assignments,
      productivityTargets: productivityTargets,
      productivityTargetOverrides: productivityTargetOverrides,
      distractionCategories: distractionCategories,
      distractionLogs: distractionLogs,
      appUsageRecords: appUsageRecords,
      appUsageDailyTotals: appUsageDailyTotals,
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

  CompletionRecord _refreshHabitDaySnapshot(
    CompletionRecord record,
    Habit habit,
  ) {
    return record.copyWith(
      productivityPoints: habit.productivityPoints,
      quitPenalty: habit.quitPenalty,
      habitType: habit.type.name,
      trackingMethod: habit.tracking.name,
      dailyGoalSnapshot: habit.dailyGoal,
      clearDailyGoalSnapshot: habit.dailyGoal == null,
      checklistItemIds: habit.checklist
          .map((ChecklistItem item) => item.id)
          .toSet(),
    );
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

    // A completion record snapshots the scoring configuration the first time
    // a habit is touched on a date. If the habit is edited later on that same
    // current date, refresh only today's snapshot so the live score and the
    // score shown after midnight use the same final daily configuration.
    // Records for every earlier date remain immutable.
    final String todayKey = dateKey(today);
    final CompletionRecord? existingTodayRecord =
        data.recordsFor(habit.id)[todayKey];
    CompletionRecord? refreshedTodayRecord;
    if (existingTodayRecord != null) {
      refreshedTodayRecord =
          _refreshHabitDaySnapshot(existingTodayRecord, habit);
      await _repo.upsertCompletion(refreshedTodayRecord);
    }

    final List<Habit> habits = List<Habit>.of(data.habits);
    final int i = habits.indexWhere((Habit h) => h.id == habit.id);
    if (i >= 0) {
      habits[i] = habit;
    } else {
      habits.add(habit);
    }
    Map<String, Map<String, CompletionRecord>> completions = data.completions;
    if (refreshedTodayRecord != null) {
      final Map<String, CompletionRecord> records =
          Map<String, CompletionRecord>.of(data.recordsFor(habit.id));
      records[todayKey] = refreshedTodayRecord;
      completions = <String, Map<String, CompletionRecord>>{
        ...data.completions,
        habit.id: records,
      };
    }
    data = data.copyWith(habits: habits, completions: completions);
    data = await _syncAchievements(data, habit);
    state = AsyncData<AppData>(data);
    // Reminder scheduling uses platform channels and may be slow or
    // unavailable (for example, during widget tests or while Android is
    // starting). It is not part of the local save transaction and must not
    // delay form navigation after the repository and app state are updated.
    unawaited(_scheduleHabitInBackground(
      habit,
      requestPermissions: habit.reminder.enabled || (habit.tracking == TrackingMethod.checklist && habit.checklist.any((ChecklistItem item) => item.reminder.enabled)),
      skipToday: skipToday,
    ));
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
    // The habit is already deleted locally. Cancelling Android notifications
    // is cleanup and must not hold the delete action or its navigation open.
    unawaited(_cancelHabitInBackground(habitId));
  }

  Future<void> _scheduleHabitInBackground(
    Habit habit, {
    required bool requestPermissions,
    required bool skipToday,
  }) async {
    try {
      await TaskReminderService.instance.scheduleHabit(
        habit,
        requestPermissions: requestPermissions,
        skipToday: skipToday,
      );
    } catch (error, stackTrace) {
      // Keep platform/plugin failures out of the local persistence path.
      // The service also records its user-facing scheduling issue when
      // possible; this catch is a final guard against unhandled async errors.
      debugPrint('Background habit reminder scheduling failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _cancelHabitInBackground(String habitId) async {
    try {
      await TaskReminderService.instance.cancelHabit(habitId);
    } catch (error, stackTrace) {
      debugPrint('Background habit reminder cancellation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
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
    final CompletionRecord updated = change(base).copyWith(
      updatedAt: now,
      productivityPoints: base.productivityPoints ?? habit.productivityPoints,
      quitPenalty: base.quitPenalty ?? habit.quitPenalty,
      habitType: base.habitType ?? habit.type.name,
      trackingMethod: base.trackingMethod ?? habit.tracking.name,
      dailyGoalSnapshot: base.dailyGoalSnapshot ?? habit.dailyGoal,
      checklistItemIds: base.checklistItemIds ?? habit.checklist.map((ChecklistItem item) => item.id).toSet(),
    );

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
    final DateTime today = dateOnly(DateTime.now());
    final CompletionRecord? currentDayRecord = forHabit[dateKey(today)];
    final bool completedToday = habit.type == HabitType.build &&
        HabitEngine(today: today).isCompleted(habit, currentDayRecord);
    if (habit.type == HabitType.build || habit.tracking == TrackingMethod.checklist) {
      // Completion state is already persisted and published. Rescheduling the
      // platform alarm is follow-up work and must not block the interaction.
      unawaited(_scheduleHabitInBackground(
        habit,
        requestPermissions: false,
        skipToday: completedToday,
      ));
    }
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
      final bool templateStillUses = data.taskTemplates.any((TaskTemplate template) =>
          template.photoPaths.contains(path) || template.audioPaths.contains(path));
      if (taskStillUses || noteStillUses || templateStillUses || path.trim().isEmpty) continue;
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
        'parentTaskId': task.parentTaskId,
        'isGroup': task.isGroup,
        'taskType': task.taskType.name,
        'progressMode': task.progressMode.name,
        'progressValue': task.progressValue,
        'progressTarget': task.progressTarget,
        'progressUnit': task.progressUnit,
        'difficultyScore': task.difficultyScore,
        // Snapshot the child set for historical day breakdowns after children
        // are edited, removed, or the parent task is deleted.
        'subtasks': task.subtasks.map((Subtask s) => <String, dynamic>{
          'id': s.id,
          'title': s.title,
          'dueAt': s.dueAt?.toIso8601String(),
          'isCompleted': s.isCompleted,
          'completedAt': s.completedAt?.toIso8601String(),
          'sortOrder': s.sortOrder,
          'difficultyScore': s.difficultyScore,
        }).toList(),
        if (subtask != null) ...<String, dynamic>{
          'subtaskId': subtask.id,
          'subtaskTitle': subtask.title,
          'subtaskDueAt': subtask.dueAt?.toIso8601String(),
          'subtaskCompleted': subtask.isCompleted,
          'subtaskCompletedAt': subtask.completedAt?.toIso8601String(),
          'subtaskDifficultyScore': subtask.difficultyScore,
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
    final bool shouldBeCompleted = task.taskType == TaskType.progressive
        ? task.progressPercent >= 100
        : task.subtasks.isNotEmpty
            ? task.subtasks.every((Subtask subtask) => subtask.isCompleted)
            : task.isCompleted;
    final Task saved = task.copyWith(
      isCompleted: shouldBeCompleted,
      completedAt: shouldBeCompleted ? (task.completedAt ?? now) : null,
      clearCompletedAt: !shouldBeCompleted,
      updatedAt: now,
    );
    await _repo.upsertTask(saved);
    await TaskReminderService.instance.scheduleTask(saved, requestPermissions: (saved.reminderAt != null || saved.dueAt != null || saved.subtasks.any((Subtask item) => item.reminderAt != null)) && !saved.isCompleted && !saved.isPaused);
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
      } else if (previous.title != subtask.title || previous.dueAt != subtask.dueAt || previous.reminderAt != subtask.reminderAt || previous.sortOrder != subtask.sortOrder) {
        await _recordTaskActivity(saved, 'subtask_updated', entityId: subtask.id, entityType: 'subtask', subtask: subtask, occurredAt: now);
      }
    }
    for (final Subtask previous in before.values) {
      if (!after.containsKey(previous.id)) {
        await _recordTaskActivity(saved, 'subtask_deleted', entityId: previous.id, entityType: 'subtask', subtask: previous, occurredAt: now);
      }
    }
    if (saved.parentTaskId != null) {
      await _refreshGroupCompletion(saved.parentTaskId!);
    }
  }

  Future<void> setTaskCompleted(String taskId, bool completed) async {
    final AppData data = _current;
    final Task? current = data.taskById(taskId);
    if (current == null) return;
    if (current.isPaused && completed) return;
    final List<Task> childTasks = data.childrenForTask(taskId);
    if (completed && (current.subtasks.any((Subtask s) => !s.isCompleted) || childTasks.any((Task t) => !t.isCompleted))) {
      throw ArgumentError('Complete all child tasks and checklist items before completing this task.');
    }
    if (current.isCompleted == completed) return;
    final DateTime now = DateTime.now();
    final Task updated = current.copyWith(
      isCompleted: completed,
      completedAt: completed ? now : null,
      clearCompletedAt: !completed,
      progressValue: current.taskType == TaskType.progressive
          ? (completed ? (current.progressMode == TaskProgressMode.percentage ? 100 : current.progressTarget) : 0)
          : current.progressValue,
      updatedAt: now,
    );
    await _repo.upsertTask(updated);
    await TaskReminderService.instance.scheduleTask(updated);
    TaskProgressEvent? progressEvent;
    if (current.taskType == TaskType.progressive && current.progressValue != updated.progressValue) {
      progressEvent = TaskProgressEvent(
        id: newId(), taskId: taskId,
        previousValue: current.progressValue, newValue: updated.progressValue,
        previousPercent: current.progressPercent, newPercent: updated.progressPercent,
        progressDelta: updated.progressPercent - current.progressPercent,
        occurredAt: now, note: completed ? 'Marked complete' : 'Reopened',
        difficultyScore: current.difficultyScore,
      );
      await _repo.addTaskProgressEvent(progressEvent);
    }
    final List<Task> tasks = List<Task>.of(data.tasks);
    tasks[tasks.indexWhere((Task t) => t.id == taskId)] = updated;
    state = AsyncData<AppData>(data.copyWith(
      tasks: tasks,
      taskProgressEvents: progressEvent == null ? data.taskProgressEvents : <TaskProgressEvent>[...data.taskProgressEvents, progressEvent],
    ));
    await _recordTaskActivity(updated, completed ? 'task_completed' : 'task_reopened', occurredAt: now);
    if (updated.parentTaskId != null) await _refreshGroupCompletion(updated.parentTaskId!);
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
      id: newId(), title: s.title, createdAt: now, dueAt: shift(s.dueAt), reminderAt: shift(s.reminderAt), sortOrder: s.sortOrder,
    )).toList();
    final Task next = Task(
      id: newId(), title: completed.title, description: completed.description,
      dueAt: shift(completed.dueAt), reminderAt: shift(completed.reminderAt),
      priority: completed.priority, category: completed.category, iconKey: completed.iconKey,
      colorValue: completed.colorValue, repeat: completed.repeat, notes: completed.notes,
      photoPaths: completed.photoPaths, audioPaths: completed.audioPaths,
      subtasks: children,
      parentTaskId: completed.parentTaskId,
      taskType: completed.taskType,
      progressMode: completed.progressMode,
      progressValue: 0,
      progressTarget: completed.progressTarget,
      progressUnit: completed.progressUnit,
      difficultyScore: completed.difficultyScore,
      createdAt: now, updatedAt: now,
    );
    await _repo.upsertTask(next);
    await TaskReminderService.instance.scheduleTask(next);
    final AppData data = _current;
    state = AsyncData<AppData>(data.copyWith(tasks: <Task>[...data.tasks, next]));
    await _recordTaskActivity(next, 'task_created', occurredAt: now);
    if (next.parentTaskId != null) await _refreshGroupCompletion(next.parentTaskId!);
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
    if (days <= 0) return;
    final AppData data = _current;
    final Task? root = data.taskById(taskId);
    if (root == null) return;
    final List<Task> affected = <Task>[root, ...data.childrenForTask(taskId)];
    for (final Task task in affected) {
      final Task updated = task.copyWith(
        dueAt: task.dueAt?.add(Duration(days: days)),
        reminderAt: task.reminderAt?.add(Duration(days: days)),
        subtasks: task.subtasks.map((Subtask subtask) => subtask.copyWith(
          dueAt: subtask.dueAt?.add(Duration(days: days)),
          reminderAt: subtask.reminderAt?.add(Duration(days: days)),
        )).toList(),
        updatedAt: DateTime.now(),
      );
      await _repo.upsertTask(updated);
      await TaskReminderService.instance.scheduleTask(updated);
      final AppData latest = _current;
      final List<Task> tasks = List<Task>.of(latest.tasks);
      final int index = tasks.indexWhere((Task item) => item.id == updated.id);
      if (index >= 0) tasks[index] = updated;
      state = AsyncData<AppData>(latest.copyWith(tasks: tasks));
      await _recordTaskActivity(updated, 'task_postponed');
    }
  }

  Future<Task?> duplicateTask(String taskId) async {
    final AppData data = _current;
    final Task? original = data.taskById(taskId);
    if (original == null) return null;
    final DateTime now = DateTime.now();
    Task freshCopy(Task source, {String? parentId, bool group = false}) => Task(
      id: newId(), title: source.title, description: source.description,
      dueAt: source.dueAt, reminderAt: source.reminderAt,
      priority: source.priority, category: source.category, iconKey: source.iconKey,
      colorValue: source.colorValue, isPaused: false,
      repeat: source.repeat, notes: source.notes,
      photoPaths: source.photoPaths, audioPaths: source.audioPaths,
      parentTaskId: parentId ?? source.parentTaskId,
      isGroup: group,
      taskType: source.taskType,
      progressMode: source.progressMode,
      progressValue: 0,
      progressTarget: source.progressTarget,
      progressUnit: source.progressUnit,
      difficultyScore: source.difficultyScore,
      sortOrder: source.sortOrder,
      subtasks: source.subtasks.map((Subtask s) => Subtask(
        id: newId(), title: s.title, createdAt: now, dueAt: s.dueAt,
        reminderAt: s.reminderAt, sortOrder: s.sortOrder,
      )).toList(),
      createdAt: now, updatedAt: now,
    );

    final bool originalIsGroup = data.isGroupTask(original);
    final Task copy = freshCopy(original, group: originalIsGroup);
    await _repo.upsertTask(copy);
    await TaskReminderService.instance.scheduleTask(copy);
    AppData latest = _current;
    state = AsyncData<AppData>(latest.copyWith(tasks: <Task>[...latest.tasks, copy]));
    await _recordTaskActivity(copy, 'task_duplicated', occurredAt: now);

    if (!originalIsGroup && copy.parentTaskId != null) {
      await _refreshGroupCompletion(copy.parentTaskId!);
    }
    if (originalIsGroup) {
      for (final Task child in data.childrenForTask(original.id)) {
        final Task childCopy = freshCopy(child, parentId: copy.id);
        await _repo.upsertTask(childCopy);
        await TaskReminderService.instance.scheduleTask(childCopy);
        latest = _current;
        state = AsyncData<AppData>(latest.copyWith(tasks: <Task>[...latest.tasks, childCopy]));
        await _recordTaskActivity(childCopy, 'task_duplicated', occurredAt: now);
      }
    }
    return copy;
  }

  Future<void> deleteTask(String taskId, {bool deleteChildren = false}) async {
    final AppData data = _current;
    final Task? task = data.taskById(taskId);
    if (task == null) return;
    final String? previousParentId = task.parentTaskId;
    final List<Task> children = data.childrenForTask(taskId);
    if (!deleteChildren) {
      for (final Task child in children) {
        final Task detached = child.copyWith(clearParentTaskId: true, updatedAt: DateTime.now());
        await _repo.upsertTask(detached);
        final AppData latest = _current;
        final List<Task> tasks = List<Task>.of(latest.tasks);
        final int index = tasks.indexWhere((Task item) => item.id == detached.id);
        if (index >= 0) tasks[index] = detached;
        state = AsyncData<AppData>(latest.copyWith(tasks: tasks));
        await _recordTaskActivity(detached, 'task_removed_from_group');
      }
    } else {
      for (final Task child in children) {
        await _recordTaskActivity(child, 'task_deleted');
        await _repo.deleteTask(child.id);
        await TaskReminderService.instance.cancelTask(child.id);
      }
    }
    await _recordTaskActivity(task, 'task_deleted');
    await _repo.deleteTask(taskId);
    await TaskReminderService.instance.cancelTask(taskId);
    final AppData latest = _current;
    state = AsyncData<AppData>(latest.copyWith(tasks: latest.tasks.where((Task t) => t.id != taskId && (!deleteChildren || !children.any((Task c) => c.id == t.id))).toList()));
    await _cleanupOrphanedAttachments(<String>{...task.photoPaths, ...task.audioPaths, ...children.expand((Task c) => <String>[...c.photoPaths, ...c.audioPaths])});
    if (previousParentId != null && _current.taskById(previousParentId) != null) {
      await _refreshGroupCompletion(previousParentId);
    }
  }


  Future<void> updateTaskProgress(String taskId, double newValue, {String note = ''}) async {
    if (!newValue.isFinite) throw ArgumentError('Progress must be a finite number.');
    final AppData data = _current;
    final Task? current = data.taskById(taskId);
    if (current == null || current.taskType != TaskType.progressive || current.isPaused) return;
    final double bounded = newValue.clamp(0, current.progressTarget).toDouble();
    if ((bounded - current.progressValue).abs() < 0.000001) return;
    final double previousPercent = current.progressPercent;
    final double nextPercent = current.progressMode == TaskProgressMode.count
        ? (bounded / current.progressTarget * 100).clamp(0, 100).toDouble()
        : bounded.clamp(0, 100).toDouble();
    final DateTime now = DateTime.now();
    final bool completed = nextPercent >= 100;
    final Task updated = current.copyWith(
      progressValue: bounded,
      isCompleted: completed,
      completedAt: completed ? (current.completedAt ?? now) : null,
      clearCompletedAt: !completed,
      updatedAt: now,
    );
    await _repo.upsertTask(updated);
    // Progress persistence must not wait on the platform notification plugin.
    // Reminder scheduling is best-effort background work; in widget tests (and
    // on devices where notification services are slow) waiting here can leave
    // the progress control in its saving state even though the task was saved.
    unawaited(TaskReminderService.instance.scheduleTask(updated));
    final TaskProgressEvent event = TaskProgressEvent(
      id: newId(), taskId: taskId,
      previousValue: current.progressValue, newValue: bounded,
      previousPercent: previousPercent, newPercent: nextPercent,
      progressDelta: nextPercent - previousPercent,
      occurredAt: now, note: note,
      difficultyScore: current.difficultyScore,
    );
    await _repo.addTaskProgressEvent(event);
    final AppData latest = _current;
    final List<Task> tasks = List<Task>.of(latest.tasks);
    final int index = tasks.indexWhere((Task item) => item.id == taskId);
    if (index >= 0) tasks[index] = updated;
    state = AsyncData<AppData>(latest.copyWith(
      tasks: tasks,
      taskProgressEvents: <TaskProgressEvent>[...latest.taskProgressEvents, event],
    ));
    await _recordTaskActivity(updated, 'task_progress_updated', occurredAt: now);
    if (current.isCompleted != updated.isCompleted) {
      await _recordTaskActivity(updated, updated.isCompleted ? 'task_completed' : 'task_reopened', occurredAt: now);
    }
    if (current.isCompleted != updated.isCompleted && updated.parentTaskId != null) {
      await _refreshGroupCompletion(updated.parentTaskId!);
    }
    if (completed && !current.isCompleted) await _createNextRepeat(updated);
  }

  Future<void> _refreshGroupCompletion(String parentId) async {
    final AppData data = _current;
    final Task? parent = data.taskById(parentId);
    if (parent == null || !data.isGroupTask(parent)) return;
    final List<Task> children = data.childrenForTask(parentId);
    final bool allDone = children.isNotEmpty && children.every((Task child) => child.isCompleted);
    if (parent.isCompleted == allDone) return;
    final DateTime now = DateTime.now();
    final Task updated = parent.copyWith(
      isCompleted: allDone,
      completedAt: allDone ? now : null,
      clearCompletedAt: !allDone,
      updatedAt: now,
    );
    await _repo.upsertTask(updated);
    await TaskReminderService.instance.scheduleTask(updated);
    final AppData latest = _current;
    final List<Task> tasks = List<Task>.of(latest.tasks);
    final int index = tasks.indexWhere((Task item) => item.id == parentId);
    if (index >= 0) tasks[index] = updated;
    state = AsyncData<AppData>(latest.copyWith(tasks: tasks));
    await _recordTaskActivity(updated, allDone ? 'task_group_completed_automatic' : 'task_group_reopened_automatic', occurredAt: now);
  }

  Future<Task?> createTaskGroup(String title, List<String> taskIds) async {
    final String trimmed = title.trim();
    if (trimmed.isEmpty) throw ArgumentError('Enter a parent task name.');
    final DateTime now = DateTime.now();
    final Task parent = Task(
      id: newId(), title: trimmed, createdAt: now, updatedAt: now,
      isGroup: true, difficultyScore: 1.0,
    );
    await saveTask(parent);
    await moveTasksToGroup(taskIds, parent.id);
    return _current.taskById(parent.id);
  }

  Future<void> moveTasksToGroup(List<String> taskIds, String parentId) async {
    final AppData data = _current;
    final Task? parent = data.taskById(parentId);
    if (parent == null || parent.parentTaskId != null) throw ArgumentError('Choose a top-level parent task.');
    final List<Task> selected = <Task>[];
    for (final String id in taskIds.toSet()) {
      final Task? task = data.taskById(id);
      if (task == null || task.id == parentId) continue;
      if (data.childrenForTask(task.id).isNotEmpty || task.isGroup) {
        throw ArgumentError('Move individual tasks, not an existing parent group.');
      }
      if (task.parentTaskId != parentId) selected.add(task);
    }
    if (selected.isEmpty) return;
    final List<Task> updatedTasks = List<Task>.of(data.tasks);
    int nextOrder = data.childrenForTask(parentId).length;
    final Set<String> previousParents = selected.map((Task task) => task.parentTaskId).whereType<String>().where((String id) => id != parentId).toSet();
    for (final Task task in selected) {
      final Task updated = task.copyWith(parentTaskId: parentId, sortOrder: nextOrder++, updatedAt: DateTime.now());
      await _repo.upsertTask(updated);
      final int index = updatedTasks.indexWhere((Task item) => item.id == task.id);
      if (index >= 0) updatedTasks[index] = updated;
      await _recordTaskActivity(updated, 'task_moved_to_group');
    }
    await _repo.upsertTask(parent.copyWith(isGroup: true, updatedAt: DateTime.now()));
    final AppData latest = _current;
    final Task groupedParent = parent.copyWith(isGroup: true, updatedAt: DateTime.now());
    final int parentIndex = updatedTasks.indexWhere((Task item) => item.id == parentId);
    if (parentIndex >= 0) updatedTasks[parentIndex] = groupedParent;
    state = AsyncData<AppData>(latest.copyWith(tasks: updatedTasks));
    await _recordTaskActivity(groupedParent, 'task_group_updated');
    for (final String previousParent in previousParents) {
      if (_current.taskById(previousParent) != null) await _refreshGroupCompletion(previousParent);
    }
    await _refreshGroupCompletion(parentId);
  }

  Future<void> saveTaskTemplate(TaskTemplate template) async {
    if (template.name.trim().isEmpty) throw ArgumentError('Enter a template name.');
    if (!template.difficultyScore.isFinite || template.difficultyScore < 1 || template.difficultyScore > 10) throw ArgumentError('Template difficulty must be between 1 and 10.');
    if (template.taskType == TaskType.progressive && (!template.progressTarget.isFinite || template.progressTarget <= 0)) throw ArgumentError('Progress target must be greater than zero.');
    if (template.subtasks.any((Subtask item) => item.title.trim().isEmpty)) throw ArgumentError('Subtask names cannot be empty.');
    if (template.subtasks.any((Subtask item) => !item.difficultyScore.isFinite || item.difficultyScore < 1 || item.difficultyScore > 10)) throw ArgumentError('Subtask difficulty must be between 1 and 10.');
    final bool duplicateName = _current.taskTemplates.any((TaskTemplate existing) =>
      existing.id != template.id && existing.name.trim().toLowerCase() == template.name.trim().toLowerCase());
    if (duplicateName) throw ArgumentError('A template with this name already exists.');
    final AppData before = _current;
    final TaskTemplate? old = before.taskTemplates.where((TaskTemplate item) => item.id == template.id).firstOrNull;
    final TaskTemplate saved = template.copyWith(name: template.name.trim(), updatedAt: DateTime.now());
    await _repo.upsertTaskTemplate(saved);
    final AppData data = _current;
    final List<TaskTemplate> templates = List<TaskTemplate>.of(data.taskTemplates);
    final int index = templates.indexWhere((TaskTemplate item) => item.id == saved.id);
    if (index >= 0) templates[index] = saved; else templates.add(saved);
    templates.sort((TaskTemplate a, TaskTemplate b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    state = AsyncData<AppData>(data.copyWith(taskTemplates: templates));
    if (old != null) {
      final Set<String> retained = <String>{...saved.photoPaths, ...saved.audioPaths};
      await _cleanupOrphanedAttachments(<String>{...old.photoPaths, ...old.audioPaths}.where((String path) => !retained.contains(path)));
    }
  }

  Future<void> deleteTaskTemplate(String templateId) async {
    final AppData before = _current;
    final TaskTemplate? removed = before.taskTemplates.where((TaskTemplate item) => item.id == templateId).firstOrNull;
    await _repo.deleteTaskTemplate(templateId);
    final AppData data = _current;
    state = AsyncData<AppData>(data.copyWith(taskTemplates: data.taskTemplates.where((TaskTemplate item) => item.id != templateId).toList()));
    if (removed != null) {
      await _cleanupOrphanedAttachments(<String>{...removed.photoPaths, ...removed.audioPaths});
    }
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
      if (updated.parentTaskId != null) await _refreshGroupCompletion(updated.parentTaskId!);
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

  // ------------------------------------------------------------ productivity

  String _dateKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> saveDefaultProductivityTarget(double target) async {
    if (!target.isFinite || target <= 0 || target > 1000) throw ArgumentError('Daily target must be greater than zero and no more than 1000.');
    final DateTime tomorrow = DateTime.now().add(const Duration(days: 1));
    final String effective = _dateKey(DateTime(tomorrow.year, tomorrow.month, tomorrow.day));
    final ProductivityTargetChange change = ProductivityTargetChange(effectiveDate: effective, target: target);
    await _repo.upsertProductivityTarget(change);
    final AppData data = _current;
    final List<ProductivityTargetChange> changes = <ProductivityTargetChange>[...data.productivityTargets.where((ProductivityTargetChange v) => v.effectiveDate != effective), change]..sort((a, b) => a.effectiveDate.compareTo(b.effectiveDate));
    state = AsyncData<AppData>(data.copyWith(productivityTargets: changes));
  }

  Future<void> setProductivityTargetForDate(DateTime date, double target) async {
    if (!target.isFinite || target <= 0 || target > 1000) throw ArgumentError('Daily target must be greater than zero and no more than 1000.');
    final String key = _dateKey(date);
    await _repo.upsertProductivityTargetOverride(key, target);
    final AppData data = _current;
    state = AsyncData<AppData>(data.copyWith(productivityTargetOverrides: <String, double>{...data.productivityTargetOverrides, key: target}));
  }

  Future<void> clearProductivityTargetOverride(DateTime date) async {
    final String key = _dateKey(date);
    await _repo.deleteProductivityTargetOverride(key);
    final AppData data = _current;
    final Map<String, double> values = Map<String, double>.of(data.productivityTargetOverrides)..remove(key);
    state = AsyncData<AppData>(data.copyWith(productivityTargetOverrides: values));
  }

  Future<void> saveAssignment(Assignment assignment) async {
    final String? problem = assignment.validate();
    if (problem != null) throw ArgumentError(problem);
    final AppData data = _current;
    final Assignment? old = data.assignments.where((Assignment value) => value.id == assignment.id).firstOrNull;
    final DateTime now = DateTime.now();
    final Assignment saved = assignment.copyWith(
      completedAt: assignment.isCompleted ? (assignment.completedAt ?? (old?.completedAt) ?? now) : assignment.completedAt,
      completedPoints: assignment.isCompleted ? (assignment.completedPoints ?? old?.completedPoints ?? assignment.difficultyScore) : assignment.completedPoints,
      updatedAt: now,
    );
    await _repo.upsertAssignment(saved);
    final List<Assignment> values = List<Assignment>.of(data.assignments);
    final int index = values.indexWhere((Assignment value) => value.id == saved.id);
    if (index < 0) values.add(saved); else values[index] = saved;
    state = AsyncData<AppData>(data.copyWith(assignments: values));
  }

  Future<void> deleteAssignment(String id) async {
    await _repo.deleteAssignment(id);
    final AppData data = _current;
    state = AsyncData<AppData>(data.copyWith(assignments: data.assignments.where((Assignment value) => value.id != id).toList()));
  }

  Future<void> saveDistractionCategory(DistractionCategory category) async {
    final String name = category.name.trim();
    if (name.isEmpty) throw ArgumentError('Enter a distraction category name.');
    if (!category.severityPointsPerHour.isFinite || category.severityPointsPerHour < 0 || category.severityPointsPerHour > 100) throw ArgumentError('Severity must be between 0 and 100 points per hour.');
    final Set<String> packages = category.packageNames.map((String value) => value.trim()).where((String value) => value.isNotEmpty).toSet();
    if (category.autoTrack && packages.isEmpty) throw ArgumentError('Choose at least one installed app to enable automatic tracking.');
    for (final MapEntry<String, int> entry in category.dailyAllowanceMinutesByPackage.entries) {
      if (entry.value < 0 || entry.value > 1440) {
        throw ArgumentError('Daily app allowances must be between 0 and 1440 minutes.');
      }
    }
    String normalise(String value) => value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    final bool duplicate = _current.distractionCategories.any((DistractionCategory value) => value.id != category.id && normalise(value.name) == normalise(name));
    if (duplicate) throw ArgumentError('A category with this name already exists.');
    final Set<String> otherPackages = <String>{
      for (final DistractionCategory value in _current.distractionCategories.where((DistractionCategory value) => value.id != category.id))
        if (value.autoTrack) ...value.packageNames.map((String packageName) => packageName.trim()),
    };
    if (category.autoTrack && category.packageNames.any((String packageName) => otherPackages.contains(packageName.trim()))) {
      throw ArgumentError('An app can be assigned to only one automatic tracking category.');
    }
    await _repo.upsertDistractionCategory(category);
    final AppData data = _current;
    final List<DistractionCategory> values = List<DistractionCategory>.of(data.distractionCategories);
    final int index = values.indexWhere((DistractionCategory value) => value.id == category.id);
    if (index < 0) values.add(category); else values[index] = category;
    values.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    state = AsyncData<AppData>(data.copyWith(distractionCategories: values));
  }

  Future<void> deleteDistractionCategory(String id) async {
    await _repo.deleteDistractionCategory(id);
    final AppData data = _current;
    state = AsyncData<AppData>(data.copyWith(
      distractionCategories: data.distractionCategories.where((DistractionCategory value) => value.id != id).toList(),
      distractionLogs: data.distractionLogs.where((DistractionLog value) => value.categoryId != id).toList(),
      appUsageRecords: data.appUsageRecords.where((AppUsageRecord value) => value.categoryId != id).toList(),
      appUsageDailyTotals: data.appUsageDailyTotals.where((AppUsageDailyTotal value) => value.categoryId != id).toList(),
    ));
  }

  Future<void> saveDistractionLog(DistractionLog log) async {
    if (!log.endAt.isAfter(log.startAt)) throw ArgumentError('The distraction duration must be greater than zero.');
    if (!_current.distractionCategories.any((DistractionCategory value) => value.id == log.categoryId)) throw ArgumentError('Choose an existing distraction category.');
    final DistractionCategory category = _current.distractionCategories.firstWhere((DistractionCategory value) => value.id == log.categoryId);
    final DistractionLog savedLog = DistractionLog(
      id: log.id, categoryId: log.categoryId, startAt: log.startAt, endAt: log.endAt,
      details: log.details, severityPointsPerHour: log.severityPointsPerHour ?? category.severityPointsPerHour,
    );
    await _repo.upsertDistractionLog(savedLog);
    final AppData data = _current;
    final List<DistractionLog> values = List<DistractionLog>.of(data.distractionLogs);
    final int index = values.indexWhere((DistractionLog value) => value.id == savedLog.id);
    if (index < 0) values.add(savedLog); else values[index] = savedLog;
    state = AsyncData<AppData>(data.copyWith(distractionLogs: values));
  }

  Future<void> deleteDistractionLog(String id) async {
    await _repo.deleteDistractionLog(id);
    final AppData data = _current;
    state = AsyncData<AppData>(data.copyWith(distractionLogs: data.distractionLogs.where((DistractionLog value) => value.id != id).toList()));
  }

  Future<void> replaceAutomaticUsageForDate(
    DateTime date,
    List<AppUsageRecord> records, {
    List<AppUsageDailyTotal> dailyTotals = const <AppUsageDailyTotal>[],
  }) async {
    final String key = _dateKey(date);
    await _repo.deleteAppUsageRecordsForDate(key);
    await _repo.deleteAppUsageDailyTotalsForDate(key);
    final Map<String, DistractionCategory> categories = <String, DistractionCategory>{
      for (final DistractionCategory value in _current.distractionCategories) value.id: value,
    };
    final List<AppUsageRecord> savedRecords = <AppUsageRecord>[];
    for (final AppUsageRecord record in records) {
      if (!record.endAt.isAfter(record.startAt)) continue;
      final DistractionCategory? category = categories[record.categoryId];
      final AppUsageRecord saved = AppUsageRecord(
        id: record.id, categoryId: record.categoryId, packageName: record.packageName,
        startAt: record.startAt, endAt: record.endAt,
        severityPointsPerHour: record.severityPointsPerHour ?? category?.severityPointsPerHour,
        dailyAllowanceMinutes: record.dailyAllowanceMinutes,
      );
      await _repo.upsertAppUsageRecord(saved);
      savedRecords.add(saved);
    }
    final List<AppUsageDailyTotal> savedTotals = <AppUsageDailyTotal>[];
    for (final AppUsageDailyTotal total in dailyTotals) {
      if (total.dateKey != key || !categories.containsKey(total.categoryId)) continue;
      await _repo.upsertAppUsageDailyTotal(total);
      savedTotals.add(total);
    }
    final AppData data = _current;
    final DateTime start = DateTime(date.year, date.month, date.day);
    final DateTime end = start.add(const Duration(days: 1));
    final List<AppUsageRecord> keepRecords = data.appUsageRecords.where((AppUsageRecord record) => !record.startAt.isBefore(end) || !record.endAt.isAfter(start)).toList();
    final List<AppUsageDailyTotal> keepTotals = data.appUsageDailyTotals.where((AppUsageDailyTotal total) => total.dateKey != key).toList();
    state = AsyncData<AppData>(data.copyWith(
      appUsageRecords: <AppUsageRecord>[...keepRecords, ...savedRecords],
      appUsageDailyTotals: <AppUsageDailyTotal>[...keepTotals, ...savedTotals],
    ));
  }

  Future<void> scheduleTaskForDate(String taskId, DateTime date) async {
    final Task? task = _current.taskById(taskId);
    if (task == null || task.isCompleted || task.isPaused || _current.isGroupTask(task)) return;
    final DateTime day = DateTime(date.year, date.month, date.day);
    final Task updated = task.copyWith(scheduledDate: day, updatedAt: DateTime.now());
    await _repo.upsertTask(updated);
    final AppData data = _current;
    final List<Task> tasks = List<Task>.of(data.tasks);
    final int index = tasks.indexWhere((Task value) => value.id == taskId);
    if (index >= 0) tasks[index] = updated;
    state = AsyncData<AppData>(data.copyWith(tasks: tasks));
    await _recordTaskActivity(updated, 'task_scheduled', occurredAt: DateTime.now());
  }

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

  // --------------------------------------------------------------- expenses

  Future<void> saveExpense(Expense expense) async {
    final String? issue = expense.validate();
    if (issue != null) throw ArgumentError(issue);
    await _repo.upsertExpense(expense);
    final AppData data = _current;
    final List<Expense> expenses = List<Expense>.of(data.expenses);
    final int index = expenses.indexWhere((Expense e) => e.id == expense.id);
    if (index < 0) {
      expenses.add(expense);
    } else {
      expenses[index] = expense;
    }
    state = AsyncData<AppData>(data.copyWith(expenses: expenses));
  }

  Future<void> deleteExpense(String expenseId) async {
    await _repo.deleteExpense(expenseId);
    final AppData data = _current;
    state = AsyncData<AppData>(data.copyWith(
      expenses: data.expenses.where((Expense e) => e.id != expenseId).toList(),
    ));
  }

  Future<void> saveExpenseCategory(ExpenseCategory category) async {
    final String name = category.name.trim();
    if (name.isEmpty) throw ArgumentError('Enter a category name.');
    final bool duplicate = _current.expenseCategories.any((ExpenseCategory c) =>
        c.id != category.id && c.name.toLowerCase() == name.toLowerCase());
    if (duplicate) throw ArgumentError('That expense category already exists.');
    final ExpenseCategory saved = category.copyWith(name: name);
    await _repo.upsertExpenseCategory(saved);
    final AppData data = _current;
    final List<ExpenseCategory> categories = List<ExpenseCategory>.of(data.expenseCategories);
    final int index = categories.indexWhere((ExpenseCategory c) => c.id == saved.id);
    if (index < 0) {
      categories.add(saved);
    } else {
      categories[index] = saved;
    }
    state = AsyncData<AppData>(data.copyWith(expenseCategories: categories));
  }

  Future<void> deleteExpenseCategory(String categoryId) async {
    final ExpenseCategory? category = _current.expenseCategoryById(categoryId);
    if (category == null || category.isBuiltIn) return;
    await _repo.deleteExpenseCategory(categoryId);
    final AppData data = _current;
    final List<Expense> expenses = data.expenses.map((Expense e) =>
      e.categoryId == categoryId ? e.copyWith(clearCategory: true) : e).toList();
    state = AsyncData<AppData>(data.copyWith(
      expenseCategories: data.expenseCategories.where((ExpenseCategory c) => c.id != categoryId).toList(),
      expenses: expenses,
    ));
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
