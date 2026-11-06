import '../models/models.dart';

DateTime dayOnly(DateTime value) => DateTime(value.year, value.month, value.day);

/// Whether [task] is scheduled for [selectedDate]. A reminder starts the
/// visible window and the deadline ends it, both inclusively. If only one of
/// those dates exists, the task is shown on that date only.
bool isTaskScheduledOnDate(Task task, DateTime selectedDate) {
  if (task.isPaused) return false;
  final DateTime? startValue = task.reminderAt ?? task.dueAt;
  if (startValue == null) return false;
  final DateTime start = dayOnly(startValue);
  final DateTime selected = dayOnly(selectedDate);
  // A reminder-only task remains active from its reminder date until it is
  // completed or given a deadline. With a deadline, visibility ends that day.
  if (task.dueAt == null) return !selected.isBefore(start);
  final DateTime end = dayOnly(task.dueAt!);
  if (start.isAfter(end)) return false;
  return !selected.isBefore(start) && !selected.isAfter(end);
}

/// Kept as a compatibility helper for callers/tests: visibility now means
/// scheduled on the selected date, not an indefinitely carried overdue task.
bool isTaskVisibleOnDate(Task task, DateTime selectedDate) =>
    isTaskScheduledOnDate(task, selectedDate);

/// Whether an incomplete task was already past its deadline by [selectedDate].
/// The list filter decides whether overdue tasks are eligible to be displayed.
bool isTaskOverdueOnDate(Task task, DateTime selectedDate) {
  if (task.isCompleted || task.isPaused || task.dueAt == null) return false;
  return dayOnly(task.dueAt!).isBefore(dayOnly(selectedDate));
}

enum TaskSort { defaultOrder, priority, deadline, categoryAscending, categoryDescending }

enum TaskListFilter { all, today, due, selectedDate }

List<Task> filterAndSortTasks(
  Iterable<Task> tasks, {
  required TaskListFilter filter,
  required DateTime selectedDate,
  String? category,
  TaskSort sort = TaskSort.defaultOrder,
  bool includeCompleted = true,
  DateTime? todayOverride,
}) {
  final DateTime selected = dayOnly(selectedDate);
  final DateTime today = dayOnly(todayOverride ?? DateTime.now());
  final bool isToday = selected.isAtSameMomentAs(today);
  final bool includeOverdue = filter == TaskListFilter.today && isToday;

  final List<Task> result = tasks.where((Task task) {
    if (!includeCompleted && task.isCompleted) return false;
    if (category != null && category.isNotEmpty && task.category != category) return false;
    final bool completedOnSelectedDate = task.isCompleted &&
        task.completedAt != null &&
        dayOnly(task.completedAt!).isAtSameMomentAs(selected);
    switch (filter) {
      case TaskListFilter.all:
        return true;
      case TaskListFilter.today:
        return isTaskScheduledOnDate(task, selected) ||
            completedOnSelectedDate ||
            (includeOverdue && isTaskOverdueOnDate(task, selected));
      case TaskListFilter.due:
      case TaskListFilter.selectedDate:
        return isTaskScheduledOnDate(task, selected) || completedOnSelectedDate;
    }
  }).toList();

  int defaultCompare(Task a, Task b) {
    if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
    if (a.isPaused != b.isPaused) return a.isPaused ? 1 : -1;
    final bool aOverdue = includeOverdue && isTaskOverdueOnDate(a, selected);
    final bool bOverdue = includeOverdue && isTaskOverdueOnDate(b, selected);
    if (aOverdue != bOverdue) return aOverdue ? -1 : 1;
    final DateTime aDue = a.dueAt ?? DateTime(9999);
    final DateTime bDue = b.dueAt ?? DateTime(9999);
    final int due = aDue.compareTo(bDue);
    return due != 0 ? due : b.createdAt.compareTo(a.createdAt);
  }

  result.sort((Task a, Task b) {
    switch (sort) {
      case TaskSort.defaultOrder:
        return defaultCompare(a, b);
      case TaskSort.priority:
        final int p = b.priority.index.compareTo(a.priority.index);
        return p != 0 ? p : defaultCompare(a, b);
      case TaskSort.deadline:
        final int d = (a.dueAt ?? DateTime(9999)).compareTo(b.dueAt ?? DateTime(9999));
        return d != 0 ? d : defaultCompare(a, b);
      case TaskSort.categoryAscending:
        final int c = a.category.toLowerCase().compareTo(b.category.toLowerCase());
        return c != 0 ? c : defaultCompare(a, b);
      case TaskSort.categoryDescending:
        final int c = b.category.toLowerCase().compareTo(a.category.toLowerCase());
        return c != 0 ? c : defaultCompare(a, b);
    }
  });
  return result;
}

class TaskDayAnalytics {
  const TaskDayAnalytics({
    required this.day,
    required this.taskCompletions,
    required this.subtaskCompletions,
    required this.lateCompletions,
    required this.weightedScore,
  });
  final DateTime day;
  final int taskCompletions;
  final int subtaskCompletions;
  final int lateCompletions;
  final double weightedScore;
  int get workUnits => taskCompletions + subtaskCompletions;
}

class TaskAnalyticsSummary {
  const TaskAnalyticsSummary({
    required this.totalTasks,
    required this.completedTasks,
    required this.incompleteTasks,
    required this.overdueTasks,
    required this.completionPercent,
    required this.onTimePercent,
    required this.weightedScore,
    required this.currentStreak,
    required this.bestStreak,
    required this.days,
  });
  final int totalTasks;
  final int completedTasks;
  final int incompleteTasks;
  final int overdueTasks;
  final double completionPercent;
  final double onTimePercent;
  final double weightedScore;
  final int currentStreak;
  final int bestStreak;
  final List<TaskDayAnalytics> days;
}

class TaskHistoryItem {
  const TaskHistoryItem({required this.id, required this.title, this.dueAt, this.isCompleted = false});
  final String id;
  final String title;
  final DateTime? dueAt;
  final bool isCompleted;
}

class TaskDayBreakdown {
  const TaskDayBreakdown({
    required this.day,
    required this.scheduledTasks,
    required this.pendingTasks,
    required this.overdueTasks,
    required this.completedSubtasks,
    required this.incompleteSubtasks,
    required this.overdueSubtasks,
  });
  final DateTime day;
  final List<TaskHistoryItem> scheduledTasks;
  final List<TaskHistoryItem> pendingTasks;
  final List<TaskHistoryItem> overdueTasks;
  final List<TaskHistoryItem> completedSubtasks;
  final List<TaskHistoryItem> incompleteSubtasks;
  final List<TaskHistoryItem> overdueSubtasks;
}

/// Analytics are calculated from immutable activity events, not just today's
/// current task flags. For tasks with subtasks, subtask completions are the
/// work units; automatic parent completion is excluded to avoid double-counting.
class TaskAnalyticsEngine {
  const TaskAnalyticsEngine();

  /// Reconstructs the selected date from the most recent persisted snapshot at
  /// or before that day's end. For tasks with no history snapshots, current
  /// model data is used only as a graceful fallback.
  TaskDayBreakdown breakdownForDay({
    required List<TaskActivity> activities,
    required List<Task> currentTasks,
    required DateTime day,
  }) {
    final DateTime selected = dayOnly(day);
    final DateTime endOfDay = DateTime(selected.year, selected.month, selected.day, 23, 59, 59, 999);
    final Map<String, List<TaskActivity>> byTask = <String, List<TaskActivity>>{};
    for (final TaskActivity event in activities) {
      byTask.putIfAbsent(event.taskId, () => <TaskActivity>[]).add(event);
    }
    final Set<String> ids = <String>{
      ...currentTasks.map((Task task) => task.id),
      ...activities.where((TaskActivity event) => !event.occurredAt.isAfter(endOfDay)).map((TaskActivity event) => event.taskId),
    };
    final List<TaskHistoryItem> scheduled = <TaskHistoryItem>[];
    final List<TaskHistoryItem> pending = <TaskHistoryItem>[];
    final List<TaskHistoryItem> overdue = <TaskHistoryItem>[];
    final List<TaskHistoryItem> incompleteSubtasks = <TaskHistoryItem>[];
    final List<TaskHistoryItem> overdueSubtasks = <TaskHistoryItem>[];

    bool isOverdueAtDayEnd(DateTime? due, DateTime selectedDay) {
      if (due == null) return false;
      final DateTime dueDay = dayOnly(due);
      if (dueDay.isBefore(selectedDay)) return true;
      return false;
    }

    for (final String id in ids) {
      final List<TaskActivity> events = byTask[id] ?? <TaskActivity>[];
      final Task? current = currentTasks.where((Task task) => task.id == id).firstOrNull;
      TaskActivity? latest;
      for (final TaskActivity event in events) {
        if (event.occurredAt.isAfter(endOfDay)) continue;
        if (latest == null || event.occurredAt.isAfter(latest.occurredAt)) latest = event;
      }
      final DateTime? created = current?.createdAt ?? events
          .where((TaskActivity event) => event.eventType == 'task_created' || event.eventType == 'task_duplicated')
          .map((TaskActivity event) => event.occurredAt)
          .fold<DateTime?>(null, (DateTime? earlier, DateTime value) => earlier == null || value.isBefore(earlier) ? value : earlier);
      if (created != null && dayOnly(created).isAfter(selected)) continue;
      if (latest?.eventType == 'task_deleted') continue;
      final Map<String, dynamic> data = latest?.snapshot ?? <String, dynamic>{};
      if (data.isEmpty && current == null) continue;
      final String title = (data['title'] as String?) ?? current?.title ?? 'Deleted task';
      final DateTime? due = DateTime.tryParse('${data['dueAt'] ?? ''}') ?? current?.dueAt;
      final DateTime? reminder = DateTime.tryParse('${data['reminderAt'] ?? ''}') ?? current?.reminderAt;
      final bool completed = data['isCompleted'] is bool ? data['isCompleted'] as bool : current?.isCompleted ?? false;
      final bool paused = data['isPaused'] is bool ? data['isPaused'] as bool : current?.isPaused ?? false;
      final DateTime? visibleFrom = reminder ?? due;
      final bool visible = !completed && !paused && visibleFrom != null && !dayOnly(visibleFrom).isAfter(selected);
      final bool overdueNow = visible && isOverdueAtDayEnd(due, selected);
      final TaskHistoryItem item = TaskHistoryItem(id: id, title: title, dueAt: due, isCompleted: completed);
      if ((due != null && dayOnly(due).isAtSameMomentAs(selected)) ||
          (visibleFrom != null && dayOnly(visibleFrom).isAtSameMomentAs(selected))) {
        scheduled.add(item);
      }
      if (visible && overdueNow) overdue.add(item);
      if (visible && !overdueNow) pending.add(item);

      final Object? rawSubtasks = data['subtasks'];
      final List<dynamic> children = rawSubtasks is List
          ? rawSubtasks
          : (current?.subtasks.map((Subtask child) => <String, dynamic>{
              'id': child.id,
              'title': child.title,
              'dueAt': child.dueAt?.toIso8601String(),
              'isCompleted': child.isCompleted,
            }).toList() ?? <dynamic>[]);
      for (final dynamic childRaw in children) {
        if (childRaw is! Map) continue;
        final Map<String, dynamic> child = Map<String, dynamic>.from(childRaw);
        final DateTime? childDue = DateTime.tryParse('${child['dueAt'] ?? ''}');
        final bool childCompleted = child['isCompleted'] == true;
        final TaskHistoryItem childItem = TaskHistoryItem(
          id: '${child['id'] ?? ''}',
          title: (child['title'] as String?) ?? 'Subtask',
          dueAt: childDue,
          isCompleted: childCompleted,
        );
        if (!childCompleted) {
          incompleteSubtasks.add(childItem);
          if (isOverdueAtDayEnd(childDue, selected)) overdueSubtasks.add(childItem);
        }
      }
    }

    final Map<String, TaskHistoryItem> completedChildMap = <String, TaskHistoryItem>{};
    for (final TaskActivity event in activities) {
      if (event.entityType != 'subtask' || event.eventType != 'subtask_completed' || !dayOnly(event.occurredAt).isAtSameMomentAs(selected)) continue;
      final Map<String, dynamic> data = event.snapshot;
      completedChildMap[event.entityId] = TaskHistoryItem(
        id: event.entityId,
        title: (data['subtaskTitle'] as String?) ?? 'Subtask',
        dueAt: DateTime.tryParse('${data['subtaskDueAt'] ?? ''}'),
        isCompleted: true,
      );
    }
    int byTitle(TaskHistoryItem a, TaskHistoryItem b) => a.title.toLowerCase().compareTo(b.title.toLowerCase());
    scheduled.sort(byTitle);
    pending.sort(byTitle);
    overdue.sort(byTitle);
    incompleteSubtasks.sort(byTitle);
    overdueSubtasks.sort(byTitle);
    final List<TaskHistoryItem> completedSubtasks = completedChildMap.values.toList()..sort(byTitle);
    return TaskDayBreakdown(
      day: selected,
      scheduledTasks: scheduled,
      pendingTasks: pending,
      overdueTasks: overdue,
      completedSubtasks: completedSubtasks,
      incompleteSubtasks: incompleteSubtasks,
      overdueSubtasks: overdueSubtasks,
    );
  }

  TaskAnalyticsSummary summarize({
    required List<TaskActivity> activities,
    required List<Task> currentTasks,
    required DateTime start,
    required DateTime end,
  }) {
    final DateTime first = dayOnly(start);
    final DateTime last = dayOnly(end);
    if (last.isBefore(first)) {
      return const TaskAnalyticsSummary(
        totalTasks: 0, completedTasks: 0, incompleteTasks: 0, overdueTasks: 0,
        completionPercent: 0, onTimePercent: 0, weightedScore: 0,
        currentStreak: 0, bestStreak: 0, days: <TaskDayAnalytics>[],
      );
    }
    final List<TaskActivity> inRange = activities.where((TaskActivity a) {
      final DateTime eventDay = dayOnly(a.occurredAt);
      return !eventDay.isBefore(first) && !eventDay.isAfter(last);
    }).toList();
    final Map<String, List<TaskActivity>> byTask = <String, List<TaskActivity>>{};
    for (final TaskActivity a in activities) {
      byTask.putIfAbsent(a.taskId, () => <TaskActivity>[]).add(a);
    }
    final Set<String> ids = <String>{
      ...inRange.map((TaskActivity a) => a.taskId),
      ...currentTasks.map((Task t) => t.id),
    };
    int totalTasks = 0;
    int completedTasks = 0;
    int incompleteTasks = 0;
    int overdueTasks = 0;
    for (final String id in ids) {
      final List<TaskActivity> events = byTask[id] ?? <TaskActivity>[];
      final Task? current = currentTasks.where((Task t) => t.id == id).firstOrNull;
      final List<TaskActivity> creationEvents = events.where((TaskActivity a) =>
          a.eventType == 'task_created' || a.eventType == 'task_duplicated').toList();
      DateTime? createdAt = current?.createdAt;
      for (final TaskActivity event in creationEvents) {
        if (createdAt == null || event.occurredAt.isBefore(createdAt)) createdAt = event.occurredAt;
      }
      // A task created after the selected period did not exist in that period.
      if (createdAt != null && dayOnly(createdAt).isAfter(last)) continue;

      TaskActivity? latestBeforeEnd;
      for (final TaskActivity event in events) {
        if (dayOnly(event.occurredAt).isAfter(last)) continue;
        if (latestBeforeEnd == null || event.occurredAt.isAfter(latestBeforeEnd.occurredAt)) {
          latestBeforeEnd = event;
        }
      }
      final Map<String, dynamic> snapshot = latestBeforeEnd?.snapshot ?? <String, dynamic>{};
      // New tasks always have a creation snapshot. For old/corrupt data, use
      // the current model only if a snapshot is unavailable.
      if (snapshot.isEmpty && current == null) continue;
      final DateTime? due = DateTime.tryParse('${snapshot['dueAt'] ?? ''}') ?? current?.dueAt;
      final bool isCompleted = snapshot['isCompleted'] is bool
          ? snapshot['isCompleted'] as bool
          : (current?.isCompleted == true && current!.completedAt != null && !dayOnly(current.completedAt!).isAfter(last));
      final bool isPaused = snapshot['isPaused'] is bool
          ? snapshot['isPaused'] as bool
          : current?.isPaused ?? false;
      final bool createdInRange = createdAt != null && !dayOnly(createdAt).isBefore(first) && !dayOnly(createdAt).isAfter(last);
      final bool dueInRange = due != null && !dayOnly(due).isBefore(first) && !dayOnly(due).isAfter(last);
      final bool completedInRange = events.any((TaskActivity a) =>
          (a.eventType == 'task_completed' || a.eventType == 'task_completed_automatic') &&
          !dayOnly(a.occurredAt).isBefore(first) && !dayOnly(a.occurredAt).isAfter(last));
      final bool subtaskCompletedInRange = events.any((TaskActivity a) =>
          a.entityType == 'subtask' && a.eventType == 'subtask_completed' &&
          !dayOnly(a.occurredAt).isBefore(first) && !dayOnly(a.occurredAt).isAfter(last));
      // A task participates in a range if it was created, due, completed, or
      // had a subtask completed in that range. Status is measured as of the
      // range end from immutable snapshots.
      if (createdInRange || dueInRange || completedInRange || subtaskCompletedInRange) {
        totalTasks++;
        if (isCompleted) {
          completedTasks++;
        } else {
          incompleteTasks++;
          if (due != null && dayOnly(due).isBefore(last) && !isPaused) overdueTasks++;
        }
      }
    }

    final List<TaskDayAnalytics> days = <TaskDayAnalytics>[];
    int streak = 0;
    int bestStreak = 0;
    for (DateTime day = first; !day.isAfter(last); day = DateTime(day.year, day.month, day.day + 1)) {
      final List<TaskActivity> dayEvents = inRange.where((TaskActivity a) => dayOnly(a.occurredAt).isAtSameMomentAs(day)).toList();
      int taskDone = 0;
      int subtaskDone = 0;
      int late = 0;
      double score = 0;
      for (final TaskActivity a in dayEvents) {
        final Map<String, dynamic> data = a.snapshot;
        final TaskPriority priority = TaskPriority.values.where((TaskPriority p) => p.name == data['priority']).firstOrNull ?? TaskPriority.medium;
        final double weight = switch (priority) { TaskPriority.low => 1, TaskPriority.medium => 2, TaskPriority.high => 3 };
        if (a.eventType == 'subtask_completed') {
          subtaskDone++;
          score += weight;
          final DateTime? due = DateTime.tryParse('${data['subtaskDueAt'] ?? ''}');
          if (due != null && dayOnly(a.occurredAt).isAfter(dayOnly(due))) late++;
        } else if (a.eventType == 'task_completed' && data['hasSubtasks'] != true) {
          taskDone++;
          score += weight;
          final DateTime? due = DateTime.tryParse('${data['dueAt'] ?? ''}');
          if (due != null && dayOnly(a.occurredAt).isAfter(dayOnly(due))) late++;
        }
      }
      days.add(TaskDayAnalytics(day: day, taskCompletions: taskDone, subtaskCompletions: subtaskDone, lateCompletions: late, weightedScore: score));
      if (taskDone + subtaskDone > 0) {
        streak++;
        if (streak > bestStreak) bestStreak = streak;
      } else {
        streak = 0;
      }
    }
    final int totalUnits = days.fold<int>(0, (int sum, TaskDayAnalytics d) => sum + d.workUnits);
    final int lateUnits = days.fold<int>(0, (int sum, TaskDayAnalytics d) => sum + d.lateCompletions);
    final double score = days.fold<double>(0, (double sum, TaskDayAnalytics d) => sum + d.weightedScore);
    return TaskAnalyticsSummary(
      totalTasks: totalTasks,
      completedTasks: completedTasks,
      incompleteTasks: incompleteTasks,
      overdueTasks: overdueTasks,
      completionPercent: totalTasks == 0 ? 0 : completedTasks * 100 / totalTasks,
      onTimePercent: totalUnits == 0 ? 0 : (totalUnits - lateUnits) * 100 / totalUnits,
      weightedScore: score,
      currentStreak: streak,
      bestStreak: bestStreak,
      days: days,
    );
  }
}

extension _TaskEngineFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
