import '../models/models.dart';

class ProductivityContribution {
  const ProductivityContribution({required this.label, required this.points, required this.kind, this.detail = ''});
  final String label;
  final double points;
  final String kind;
  final String detail;
}

class ProductivityDayScore {
  const ProductivityDayScore({
    required this.date,
    required this.target,
    required this.achievementPoints,
    required this.penaltyPoints,
    required this.netScore,
    required this.rawNetScore,
    required this.contributions,
    required this.penalties,
  });
  final DateTime date;
  final double target;
  final double achievementPoints;
  final double penaltyPoints;
  /// Display score is clamped at zero. The raw value remains available for diagnostics.
  final double netScore;
  final double rawNetScore;
  final List<ProductivityContribution> contributions;
  final List<ProductivityContribution> penalties;
  double get targetProgress => target <= 0 ? 0 : (netScore / target).clamp(0, 1).toDouble();
}

class RecommendedTask {
  const RecommendedTask({required this.task, required this.score, required this.reason});
  final Task task;
  final double score;
  final String reason;
}

class ProductivityEngine {
  const ProductivityEngine();

  ProductivityDayScore calculateDay({
    required DateTime date,
    required double target,
    required List<Habit> habits,
    required Map<String, Map<String, CompletionRecord>> completions,
    required List<Task> tasks,
    required List<TaskActivity> activities,
    required List<TaskProgressEvent> progressEvents,
    required List<Assignment> assignments,
    required List<DistractionCategory> distractionCategories,
    required List<DistractionLog> distractionLogs,
    required List<AppUsageRecord> appUsageRecords,
  }) {
    final DateTime start = DateTime(date.year, date.month, date.day);
    final DateTime end = start.add(const Duration(days: 1));
    final String key = _dateKey(date);
    final List<ProductivityContribution> positive = <ProductivityContribution>[];
    final List<ProductivityContribution> negative = <ProductivityContribution>[];

    for (final Habit habit in habits) {
      final CompletionRecord? record = completions[habit.id]?[key];
      if (record == null) continue;
      final DateTime? archivedAt = habit.archivedAt;
      if (archivedAt != null && DateTime(archivedAt.year, archivedAt.month, archivedAt.day).isBefore(start)) continue;
      final String recordedType = record.habitType ?? habit.type.name;
      if (recordedType == HabitType.quit.name) {
        if (record.slipped && (record.quitPenalty ?? habit.quitPenalty) > 0) {
          negative.add(ProductivityContribution(label: habit.title, points: record.quitPenalty ?? habit.quitPenalty, kind: 'Quit Habit slip', detail: 'Explicit slip recorded'));
        }
        continue;
      }
      final double fraction = _habitFraction(habit, record);
      if (fraction > 0) {
        final double points = (record.productivityPoints ?? habit.productivityPoints) * fraction;
        positive.add(ProductivityContribution(label: habit.title, points: points, kind: 'Build Habit', detail: '${(fraction * 100).toStringAsFixed(0)}% completion'));
      }
    }

    final Map<String, Task> taskById = <String, Task>{for (final Task task in tasks) task.id: task};
    final Map<String, List<TaskProgressEvent>> progressByTask = <String, List<TaskProgressEvent>>{};
    for (final TaskProgressEvent event in progressEvents) {
      progressByTask.putIfAbsent(event.taskId, () => <TaskProgressEvent>[]).add(event);
    }
    for (final List<TaskProgressEvent> events in progressByTask.values) {
      events.sort((TaskProgressEvent a, TaskProgressEvent b) => a.occurredAt.compareTo(b.occurredAt));
    }
    final Map<String, Map<String, dynamic>> latestTaskSnapshots = <String, Map<String, dynamic>>{};
    for (final TaskActivity activity in activities.toList()
      ..sort((TaskActivity a, TaskActivity b) => a.occurredAt.compareTo(b.occurredAt))) {
      if (activity.entityType == 'task') latestTaskSnapshots[activity.taskId] = activity.snapshot;
    }
    for (final MapEntry<String, List<TaskProgressEvent>> entry in progressByTask.entries) {
      final Task? task = taskById[entry.key];
      final Map<String, dynamic> historical = latestTaskSnapshots[entry.key] ?? <String, dynamic>{};
      // A progress event can only be written for a Progressive task. Do not
      // consult the task's current type here: changing its type later must not
      // erase points earned by earlier progress events. Container structures
      // remain excluded to avoid scoring a parent as well as its children.
      final bool isContainer = historical.containsKey('isGroup')
          ? historical['isGroup'] == true || historical['hasSubtasks'] == true ||
              ((historical['subtaskCount'] as num?)?.toInt() ?? 0) > 0
          : task?.isGroup == true || task?.subtasks.isNotEmpty == true ||
              (task != null && tasks.any((Task child) => child.parentTaskId == task.id));
      if (isContainer) continue;
      final String title = task?.title ?? (historical['title'] as String? ?? entry.key);
      // The first event may start above zero for tasks migrated from a build
      // that did not yet record their initial progress. Treat that previous
      // percentage as already earned, rather than awarding it retroactively.
      double highWater = entry.value.first.previousPercent.clamp(0, 100).toDouble();
      for (final TaskProgressEvent event in entry.value) {
        final double nextHigh = event.newPercent > highWater ? event.newPercent : highWater;
        final double newlyReached = (nextHigh - highWater).clamp(0, 100).toDouble();
        if (newlyReached > 0 && _sameDay(event.occurredAt, date)) {
          positive.add(ProductivityContribution(label: title, points: event.difficultyScore * newlyReached / 100, kind: 'Progressive Task', detail: '${newlyReached.toStringAsFixed(1)}% newly reached'));
        }
        highWater = nextHigh;
      }
    }

    // Standard task completions: the earliest genuine completion only. Groups and
    // checklist parents are organisational containers, never independently scored.
    final Set<String> awardedStandardTasks = <String>{};
    final List<TaskActivity> orderedActivities = List<TaskActivity>.of(activities)
      ..sort((TaskActivity a, TaskActivity b) => a.occurredAt.compareTo(b.occurredAt));
    final Set<String> awardedSubtasks = <String>{};
    for (final TaskActivity event in orderedActivities) {
      if (event.entityType == 'subtask' && event.eventType == 'subtask_completed') {
        final String childId = event.entityId;
        if (awardedSubtasks.add(childId) && _sameDay(event.occurredAt, date)) {
          final Map<String, dynamic> snapshot = event.snapshot;
          final String title = (snapshot['subtaskTitle'] as String?) ?? childId;
          final double difficulty = (snapshot['subtaskDifficultyScore'] as num?)?.toDouble() ?? 1.0;
          positive.add(ProductivityContribution(label: title, points: difficulty, kind: 'Subtask', detail: 'Completed'));
        }
      }
      if (event.entityType != 'task' || event.eventType != 'task_completed') continue;
      final Map<String, dynamic> snapshot = event.snapshot;
      final Task? task = taskById[event.taskId];
      final bool wasProgressive = snapshot.containsKey('taskType')
          ? snapshot['taskType'] == 'progressive'
          : task?.taskType == TaskType.progressive;
      if (wasProgressive) continue;
      final bool wasContainer = snapshot.containsKey('isGroup')
          ? snapshot['isGroup'] == true || snapshot['hasSubtasks'] == true ||
              ((snapshot['subtaskCount'] as num?)?.toInt() ?? 0) > 0
          : task?.isGroup == true || task?.subtasks.isNotEmpty == true ||
              (task != null && tasks.any((Task child) => child.parentTaskId == task.id));
      if (wasContainer) continue;
      if (!awardedStandardTasks.add(event.taskId)) continue;
      if (_sameDay(event.occurredAt, date)) {
        final String title = (snapshot['title'] as String?) ?? task?.title ?? event.taskId;
        final double difficulty = (snapshot['difficultyScore'] as num?)?.toDouble() ?? task?.difficultyScore ?? 1.0;
        positive.add(ProductivityContribution(label: title, points: difficulty, kind: 'Task', detail: 'Completed'));
      }
    }

    for (final Assignment assignment in assignments) {
      final DateTime? completed = assignment.completedAt;
      if (completed != null && _sameDay(completed, date)) {
        positive.add(ProductivityContribution(label: assignment.title, points: assignment.completedPoints ?? assignment.difficultyScore, kind: 'Assignment', detail: 'First completion'));
      }
    }

    final Map<String, DistractionCategory> categoryById = <String, DistractionCategory>{
      for (final DistractionCategory category in distractionCategories) category.id: category,
    };
    final List<_ScoredInterval> scoredIntervals = <_ScoredInterval>[];
    for (final DistractionLog log in distractionLogs) {
      final DistractionCategory? category = categoryById[log.categoryId];
      final double severity = log.severityPointsPerHour ?? category?.severityPointsPerHour ?? 0;
      if (category != null && severity > 0) {
        _addScoredInterval(scoredIntervals, category, log.startAt, log.endAt, start, end, severity: severity);
      }
    }
    for (final AppUsageRecord record in appUsageRecords) {
      final DistractionCategory? category = categoryById[record.categoryId];
      final double severity = record.severityPointsPerHour ?? category?.severityPointsPerHour ?? 0;
      if (category != null && severity > 0) {
        _addScoredInterval(scoredIntervals, category, record.startAt, record.endAt, start, end, severity: severity);
      }
    }
    // Merge all overlapping manual and automatic intervals, even when the user
    // assigned them to different categories. In an overlapping segment only
    // the highest configured severity is charged, preventing duplicate time.
    if (scoredIntervals.isNotEmpty) {
      final List<DateTime> boundaries = <DateTime>{
        for (final _ScoredInterval interval in scoredIntervals) interval.start,
        for (final _ScoredInterval interval in scoredIntervals) interval.end,
      }.toList()..sort();
      final Map<String, double> penaltyByCategory = <String, double>{};
      final Map<String, String> labelByCategory = <String, String>{};
      final Map<String, double> minutesByCategory = <String, double>{};
      for (int i = 0; i < boundaries.length - 1; i++) {
        final DateTime segmentStart = boundaries[i];
        final DateTime segmentEnd = boundaries[i + 1];
        if (!segmentEnd.isAfter(segmentStart)) continue;
        final List<_ScoredInterval> active = scoredIntervals.where((_ScoredInterval v) =>
          !v.start.isAfter(segmentStart) && !v.end.isBefore(segmentEnd)).toList();
        if (active.isEmpty) continue;
        active.sort((_ScoredInterval a, _ScoredInterval b) => b.severity.compareTo(a.severity));
        final _ScoredInterval winner = active.first;
        final double minutes = segmentEnd.difference(segmentStart).inSeconds / 60;
        penaltyByCategory.update(winner.categoryId, (double old) => old + minutes / 60 * winner.severity, ifAbsent: () => minutes / 60 * winner.severity);
        labelByCategory[winner.categoryId] = winner.categoryName;
        minutesByCategory.update(winner.categoryId, (double old) => old + minutes, ifAbsent: () => minutes);
      }
      for (final String categoryId in penaltyByCategory.keys) {
        negative.add(ProductivityContribution(
          label: labelByCategory[categoryId] ?? 'Distraction',
          points: penaltyByCategory[categoryId]!,
          kind: 'Distraction',
          detail: '${minutesByCategory[categoryId]!.toStringAsFixed(0)} min (overlapping time counted once)',
        ));
      }
    }

    final double earned = positive.fold<double>(0, (double total, ProductivityContribution c) => total + c.points);
    final double penalties = negative.fold<double>(0, (double total, ProductivityContribution c) => total + c.points);
    final double raw = earned - penalties;
    return ProductivityDayScore(
      date: start,
      target: target,
      achievementPoints: earned,
      penaltyPoints: penalties,
      rawNetScore: raw,
      netScore: raw.clamp(0, double.infinity).toDouble(),
      contributions: positive,
      penalties: negative,
    );
  }

  List<RecommendedTask> recommendTasks({
    required List<Task> tasks,
    required DateTime date,
    required double remainingTarget,
  }) {
    final DateTime today = DateTime(date.year, date.month, date.day);
    final List<RecommendedTask> result = <RecommendedTask>[];
    for (final Task task in tasks) {
      if (task.isCompleted || task.isPaused || task.isGroup || tasks.any((Task child) => child.parentTaskId == task.id)) continue;
      if (task.scheduledDate != null) {
        final DateTime scheduled = DateTime(task.scheduledDate!.year, task.scheduledDate!.month, task.scheduledDate!.day);
        if (!scheduled.isBefore(today)) continue;
      }
      if (task.dueAt != null) {
        final DateTime due = DateTime(task.dueAt!.year, task.dueAt!.month, task.dueAt!.day);
        // Recommendations focus on unplanned and overdue work. Future-dated work
        // remains for its planned date instead of being pulled forward.
        if (due.isAfter(today)) continue;
      }
      final double priority = switch (task.priority) {
        TaskPriority.high => 1.0,
        TaskPriority.medium => 0.55,
        TaskPriority.low => 0.2,
      };
      final DateTime? dueDate = task.dueAt == null
          ? null
          : DateTime(task.dueAt!.year, task.dueAt!.month, task.dueAt!.day);
      final int overdueDays = dueDate == null ? 0 : today.difference(dueDate).inDays;
      final double urgency = dueDate == null
          ? 0.12
          : (0.90 + (overdueDays.clamp(0, 30) / 30) * 0.10).clamp(0, 1).toDouble();
      final double contribution = remainingTarget <= 0
          ? 0
          : (task.difficultyScore / remainingTarget).clamp(0, 1).toDouble();
      final double unscheduled = task.scheduledDate == null ? 1.0 : 0.0;
      final double score = priority * 0.40 + urgency * 0.40 + contribution * 0.15 + unscheduled * 0.05;
      final String deadlineReason = dueDate == null
          ? 'no deadline'
          : overdueDays > 0
              ? 'overdue by $overdueDays day(s)'
              : 'deadline is today';
      final String reason = '${task.priority.name[0].toUpperCase()}${task.priority.name.substring(1)} priority · $deadlineReason · ${task.difficultyScore.toStringAsFixed(1)} points';
      result.add(RecommendedTask(task: task, score: score, reason: reason));
    }
    result.sort((RecommendedTask a, RecommendedTask b) => b.score.compareTo(a.score));
    return result;
  }

  double _habitFraction(Habit habit, CompletionRecord record) {
    switch (record.trackingMethod ?? habit.tracking.name) {
      case 'tick':
        return record.done ? 1 : 0;
      case 'count':
        final double goal = record.dailyGoalSnapshot ?? habit.dailyGoal ?? 1;
        return goal <= 0 ? 0 : (record.count / goal).clamp(0, 1).toDouble();
      case 'checklist':
        final Set<String> checklistIds = record.checklistItemIds ?? habit.checklist.map((ChecklistItem item) => item.id).toSet();
        if (checklistIds.isEmpty) return 0;
        return (record.checkedItemIds.intersection(checklistIds).length / checklistIds.length).clamp(0, 1).toDouble();
      default:
        return 0;
    }
  }

  void _addScoredInterval(List<_ScoredInterval> target, DistractionCategory category, DateTime from, DateTime to, DateTime dayStart, DateTime dayEnd, {required double severity}) {
    final DateTime clippedStart = from.isBefore(dayStart) ? dayStart : from;
    final DateTime clippedEnd = to.isAfter(dayEnd) ? dayEnd : to;
    if (clippedEnd.isAfter(clippedStart)) {
      target.add(_ScoredInterval(clippedStart, clippedEnd, category.id, category.name, severity));
    }
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

class _ScoredInterval {
  const _ScoredInterval(this.start, this.end, this.categoryId, this.categoryName, this.severity);
  final DateTime start;
  final DateTime end;
  final String categoryId;
  final String categoryName;
  final double severity;
}
