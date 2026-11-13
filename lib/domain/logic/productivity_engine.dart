import '../models/models.dart';
import 'task_engine.dart';

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
    DateTime? today,
    DateTime? currentStateScoringStartDate,
  }) {
    final DateTime start = DateTime(date.year, date.month, date.day);
    final DateTime end = start.add(const Duration(days: 1));
    final String key = _dateKey(date);
    final List<ProductivityContribution> positive = <ProductivityContribution>[];
    final List<ProductivityContribution> negative = <ProductivityContribution>[];

    final bool isToday = _sameDay(date, today ?? DateTime.now());
    for (final Habit habit in habits) {
      final CompletionRecord? record = completions[habit.id]?[key];
      if (record == null) continue;
      final DateTime? archivedAt = habit.archivedAt;
      if (archivedAt != null && DateTime(archivedAt.year, archivedAt.month, archivedAt.day).isBefore(start)) continue;
      // Today's points use the current habit configuration and saved input.
      // Earlier dates continue to use the configuration snapshot stored with
      // that day's CompletionRecord, so later habit edits do not rewrite them.
      final String recordedType = isToday ? habit.type.name : (record.habitType ?? habit.type.name);
      if (recordedType == HabitType.quit.name) {
        final double penalty = isToday ? habit.quitPenalty : (record.quitPenalty ?? habit.quitPenalty);
        if (record.slipped && penalty > 0) {
          negative.add(ProductivityContribution(label: habit.title, points: penalty, kind: 'Quit Habit slip', detail: 'Explicit slip recorded'));
        }
        continue;
      }
      final double fraction = isToday ? _currentHabitFraction(habit, record) : _habitFraction(habit, record);
      if (fraction > 0) {
        final double pointValue = isToday ? habit.productivityPoints : (record.productivityPoints ?? habit.productivityPoints);
        positive.add(ProductivityContribution(label: habit.title, points: pointValue * fraction, kind: 'Build Habit', detail: '${(fraction * 100).toStringAsFixed(0)}% completion'));
      }
    }

    final DateTime? scoringStart = currentStateScoringStartDate == null
        ? null
        : DateTime(currentStateScoringStartDate.year, currentStateScoringStartDate.month, currentStateScoringStartDate.day);
    final bool usesNewScoringModel = scoringStart != null && !DateTime(date.year, date.month, date.day).isBefore(scoringStart);
    if (isToday) {
      _addCurrentTaskContributions(
        date: date,
        tasks: tasks,
        progressEvents: progressEvents,
        positive: positive,
      );
    } else if (usesNewScoringModel) {
      _addHistoricalTaskContributions(
        date: date,
        tasks: tasks,
        activities: activities,
        progressEvents: progressEvents,
        positive: positive,
      );
    } else {
      _addLegacyHistoricalTaskContributions(
        date: date,
        tasks: tasks,
        activities: activities,
        progressEvents: progressEvents,
        positive: positive,
      );
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
    // Apply each app's daily grace period before building penalty intervals.
    // The allowance is snapshotted on every AppUsageRecord so later edits to a
    // category do not retroactively alter already-recorded days.
    final Map<String, List<AppUsageRecord>> usageByPackage = <String, List<AppUsageRecord>>{};
    for (final AppUsageRecord record in appUsageRecords) {
      final DistractionCategory? category = categoryById[record.categoryId];
      final double severity = record.severityPointsPerHour ?? category?.severityPointsPerHour ?? 0;
      if (category == null || severity <= 0 ||
          !record.startAt.isBefore(end) || !record.endAt.isAfter(start)) {
        continue;
      }
      usageByPackage.putIfAbsent(record.packageName, () => <AppUsageRecord>[]).add(record);
    }
    for (final List<AppUsageRecord> sessions in usageByPackage.values) {
      sessions.sort((AppUsageRecord a, AppUsageRecord b) => a.startAt.compareTo(b.startAt));
      final AppUsageRecord firstSession = sessions.first;
      final int allowanceMillis = firstSession.dailyAllowanceMinutes.clamp(0, 1440).toInt() * 60000;
      int consumedMillis = 0;
      DateTime? previousSessionEnd;

      for (final AppUsageRecord record in sessions) {
        DateTime sessionStart = record.startAt.isBefore(start) ? start : record.startAt;
        final DateTime sessionEnd = record.endAt.isAfter(end) ? end : record.endAt;
        // Avoid consuming or charging duplicate time if the native event feed
        // happens to contain overlapping sessions for the same package.
        if (previousSessionEnd != null && sessionStart.isBefore(previousSessionEnd)) {
          sessionStart = previousSessionEnd;
        }
        if (!sessionEnd.isAfter(sessionStart)) continue;

        final int durationMillis = sessionEnd.difference(sessionStart).inMilliseconds;
        final int allowanceRemaining = allowanceMillis > consumedMillis
            ? allowanceMillis - consumedMillis
            : 0;
        final int exemptMillis = durationMillis < allowanceRemaining
            ? durationMillis
            : allowanceRemaining;
        consumedMillis += durationMillis;
        previousSessionEnd = sessionEnd;

        final DateTime chargeStart = sessionStart.add(Duration(milliseconds: exemptMillis));
        final DistractionCategory? recordCategory = categoryById[record.categoryId];
        final double recordSeverity = record.severityPointsPerHour ?? recordCategory?.severityPointsPerHour ?? 0;
        if (recordCategory != null && recordSeverity > 0 && sessionEnd.isAfter(chargeStart)) {
          _addScoredInterval(
            scoredIntervals,
            recordCategory,
            chargeStart,
            sessionEnd,
            start,
            end,
            severity: recordSeverity,
          );
        }
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
    final DateTime selectedDay = dayOnly(date);
    final List<RecommendedTask> result = <RecommendedTask>[];

    for (final Task task in tasks) {
      final bool hasChildren = tasks.any((Task child) => child.parentTaskId == task.id);
      if (task.isCompleted || task.isPaused || task.isGroup || hasChildren) continue;

      // Keep the recommendation list separate from Today's Tasks. Anything
      // already visible on the selected day or already overdue belongs in the
      // day list, not in Suggested Next.
      if (isTaskScheduledOnDate(task, selectedDay) ||
          isTaskOverdueOnDate(task, selectedDay)) {
        continue;
      }

      final DateTime? dueDate = task.dueAt == null ? null : dayOnly(task.dueAt!);
      final DateTime? plannedDate = task.scheduledDate == null
          ? (task.reminderAt == null ? null : dayOnly(task.reminderAt!))
          : dayOnly(task.scheduledDate!);
      final int daysToDue = dueDate == null ? 9999 : dueDate.difference(selectedDay).inDays;
      final int daysToPlan = plannedDate == null ? 9999 : plannedDate.difference(selectedDay).inDays;

      final double priorityWeight = switch (task.priority) {
        TaskPriority.high => 1.0,
        TaskPriority.medium => 0.65,
        TaskPriority.low => 0.30,
      };
      final double urgencyWeight = dueDate != null
          ? daysToDue <= 1
              ? 1.0
              : daysToDue <= 7
                  ? 0.85
                  : daysToDue <= 30
                      ? 0.65
                      : 0.45
          : plannedDate != null && daysToPlan > 0
              ? daysToPlan <= 7 ? 0.75 : 0.50
              : 0.35;
      final double difficultyWeight =
          (task.difficultyScore.clamp(1.0, 10.0) / 10.0).toDouble();
      final double targetFit = remainingTarget <= 0
          ? 0.0
          : (task.difficultyScore / remainingTarget).clamp(0.0, 1.0).toDouble();
      final double scheduleWeight = plannedDate != null && daysToPlan > 0 ? 1.0 : 0.45;
      final double score = priorityWeight * 0.40 +
          urgencyWeight * 0.35 +
          difficultyWeight * 0.15 +
          targetFit * 0.07 +
          scheduleWeight * 0.03;

      final List<String> reasons = <String>[];
      reasons.add('${task.priority.name[0].toUpperCase()}${task.priority.name.substring(1)} priority');
      if (dueDate != null) {
        reasons.add('Due ${_relativeDateLabel(dueDate, selectedDay)}');
      }
      if (plannedDate != null && daysToPlan > 0) {
        reasons.add('Planned ${_relativeDateLabel(plannedDate, selectedDay)}');
      } else if (plannedDate != null && daysToPlan < 0) {
        reasons.add('Previously planned');
      } else if (dueDate == null && plannedDate == null) {
        reasons.add('Unscheduled');
      }
      reasons.add('${task.difficultyScore.toStringAsFixed(task.difficultyScore == task.difficultyScore.roundToDouble() ? 0 : 1)} points');
      result.add(RecommendedTask(task: task, score: score, reason: reasons.join(' · ')));
    }

    result.sort((RecommendedTask a, RecommendedTask b) {
      final int scoreOrder = b.score.compareTo(a.score);
      if (scoreOrder != 0) return scoreOrder;
      final DateTime aDue = a.task.dueAt ?? DateTime(9999);
      final DateTime bDue = b.task.dueAt ?? DateTime(9999);
      final int dueOrder = aDue.compareTo(bDue);
      if (dueOrder != 0) return dueOrder;
      return b.task.priority.index.compareTo(a.task.priority.index);
    });
    return result.take(3).toList();
  }

  String _relativeDateLabel(DateTime value, DateTime from) {
    final int difference = dayOnly(value).difference(dayOnly(from)).inDays;
    if (difference == 0) return 'today';
    if (difference == 1) return 'tomorrow';
    if (difference > 1 && difference <= 7) return 'in $difference days';
    return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}';
  }

  /// Today's score follows the currently saved task state relative to the
  /// progress value at the start of the day. Moving a slider up and then back
  /// to yesterday's value therefore removes all provisional points for today.
  void _addCurrentTaskContributions({
    required DateTime date,
    required List<Task> tasks,
    required List<TaskProgressEvent> progressEvents,
    required List<ProductivityContribution> positive,
  }) {
    final Map<String, List<TaskProgressEvent>> todayEventsByTask = <String, List<TaskProgressEvent>>{};
    for (final TaskProgressEvent event in progressEvents) {
      if (_sameDay(event.occurredAt, date)) {
        todayEventsByTask.putIfAbsent(event.taskId, () => <TaskProgressEvent>[]).add(event);
      }
    }

    bool isContainer(Task task) => task.isGroup || task.subtasks.isNotEmpty ||
        tasks.any((Task child) => child.parentTaskId == task.id);

    for (final Task task in tasks) {
      final bool container = isContainer(task);

      if (!container && task.taskType == TaskType.progressive) {
        final List<TaskProgressEvent> taskEvents =
            List<TaskProgressEvent>.of(todayEventsByTask[task.id] ?? const <TaskProgressEvent>[])
              ..sort((TaskProgressEvent a, TaskProgressEvent b) => a.occurredAt.compareTo(b.occurredAt));
        final bool createdToday = _sameDay(task.createdAt, date);
        if (taskEvents.isNotEmpty || createdToday) {
          // A task created today starts at zero for today's scoring. Existing
          // tasks start from the value immediately before their first update
          // today, not from their absolute saved progress.
          final double startOfDayPercent = createdToday
              ? 0
              : taskEvents.first.previousPercent.clamp(0, 100).toDouble();
          final double netProgressToday =
              (task.progressPercent - startOfDayPercent).clamp(0, 100).toDouble();
          if (netProgressToday > 0) {
            positive.add(ProductivityContribution(
              label: task.title,
              points: task.difficultyScore * netProgressToday / 100,
              kind: 'Progressive Task',
              detail: '${netProgressToday.toStringAsFixed(1)}% net progress today',
            ));
          }
        }
      } else if (!container && task.isCompleted && task.completedAt != null && _sameDay(task.completedAt!, date)) {
        positive.add(ProductivityContribution(
          label: task.title,
          points: task.difficultyScore,
          kind: 'Task',
          detail: 'Currently completed today',
        ));
      }

      // Inline checklist subtasks are scored individually. Their parent is a
      // container and is deliberately not awarded a second time.
      for (final Subtask subtask in task.subtasks) {
        if (subtask.isCompleted && subtask.completedAt != null && _sameDay(subtask.completedAt!, date)) {
          positive.add(ProductivityContribution(
            label: subtask.title,
            points: subtask.difficultyScore,
            kind: 'Subtask',
            detail: 'Currently completed today',
          ));
        }
      }
    }
  }

  /// Preserves the scoring calculation that existed before this update.
  /// It is used only for historical dates before the new scoring model became
  /// active on this installation.
  void _addLegacyHistoricalTaskContributions({
    required DateTime date,
    required List<Task> tasks,
    required List<TaskActivity> activities,
    required List<TaskProgressEvent> progressEvents,
    required List<ProductivityContribution> positive,
  }) {
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

  }

  /// Previous dates remain based on immutable activity snapshots. Editing a
  /// task today therefore cannot rewrite an already recorded daily score.
  void _addHistoricalTaskContributions({
    required DateTime date,
    required List<Task> tasks,
    required List<TaskActivity> activities,
    required List<TaskProgressEvent> progressEvents,
    required List<ProductivityContribution> positive,
  }) {
    final DateTime dayEnd = DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
    final Map<String, Task> taskById = <String, Task>{for (final Task task in tasks) task.id: task};
    final Map<String, TaskActivity> latestSnapshotByTask = <String, TaskActivity>{};
    final Set<String> progressChangedOnDay = <String>{};
    final Set<String> createdOnDay = <String>{};

    for (final TaskActivity activity in activities) {
      if ((activity.entityType != 'task' && activity.entityType != 'subtask') || activity.occurredAt.isAfter(dayEnd)) continue;
      final TaskActivity? previous = latestSnapshotByTask[activity.taskId];
      if (previous == null || !activity.occurredAt.isBefore(previous.occurredAt)) {
        latestSnapshotByTask[activity.taskId] = activity;
      }
      if (_sameDay(activity.occurredAt, date) &&
          (activity.eventType == 'task_created' || activity.eventType == 'task_duplicated')) {
        createdOnDay.add(activity.taskId);
      }
    }
    for (final TaskProgressEvent event in progressEvents) {
      if (_sameDay(event.occurredAt, date)) progressChangedOnDay.add(event.taskId);
    }

    final Set<String> taskIds = <String>{...latestSnapshotByTask.keys, ...taskById.keys};
    final Set<String> legacyTaskIds = <String>{};
    for (final String taskId in taskIds) {
      final Task? task = taskById[taskId];
      final TaskActivity? latest = latestSnapshotByTask[taskId];
      final Map<String, dynamic> snapshot = latest?.snapshot ?? <String, dynamic>{};

      // Current-format immutable snapshots contain the task completion and
      // progress fields. They reconstruct the state at the end of this date,
      // even if the task was reopened or edited on a later date.
      final bool hasStateSnapshot = snapshot.containsKey('isCompleted') ||
          snapshot.containsKey('progressValue') || snapshot.containsKey('subtasks');
      if (!hasStateSnapshot) {
        legacyTaskIds.add(taskId);
        continue;
      }

      final bool hasContainerSnapshot = snapshot.containsKey('isGroup') ||
          snapshot.containsKey('hasSubtasks') || snapshot.containsKey('subtaskCount');
      final bool isContainer = hasContainerSnapshot
          ? snapshot['isGroup'] == true || snapshot['hasSubtasks'] == true ||
              ((snapshot['subtaskCount'] as num?)?.toInt() ?? 0) > 0
          : task?.isGroup == true || task?.subtasks.isNotEmpty == true ||
              tasks.any((Task child) => child.parentTaskId == taskId);
      final String title = (snapshot['title'] as String?) ?? task?.title ?? taskId;
      final String taskType = (snapshot['taskType'] as String?) ?? task?.taskType.name ?? TaskType.standard.name;

      if (taskType == TaskType.progressive.name && !isContainer) {
        final bool changedThatDay = progressChangedOnDay.contains(taskId) ||
            createdOnDay.contains(taskId) || (task != null && _sameDay(task.createdAt, date));
        if (!changedThatDay) continue;
        final double progressValue = (snapshot['progressValue'] as num?)?.toDouble() ?? task?.progressValue ?? 0;
        final double progressTarget = (snapshot['progressTarget'] as num?)?.toDouble() ?? task?.progressTarget ?? 100;
        final String progressMode = (snapshot['progressMode'] as String?) ?? task?.progressMode.name ?? TaskProgressMode.percentage.name;
        final double currentPercent = progressMode == TaskProgressMode.count.name
            ? (progressTarget <= 0 ? 0 : (progressValue / progressTarget * 100).clamp(0, 100).toDouble())
            : progressValue.clamp(0, 100).toDouble();
        final double difficulty = (snapshot['difficultyScore'] as num?)?.toDouble() ?? task?.difficultyScore ?? 1;
        if (currentPercent > 0) {
          positive.add(ProductivityContribution(
            label: title,
            points: difficulty * currentPercent / 100,
            kind: 'Progressive Task',
            detail: '${currentPercent.toStringAsFixed(1)}% end-of-day progress',
          ));
        }
      } else if (!isContainer) {
        final bool completed = snapshot['isCompleted'] == true;
        final DateTime? completedAt = snapshot.containsKey('completedAt')
            ? DateTime.tryParse('${snapshot['completedAt'] ?? ''}')
            : task?.completedAt;
        if (completed && completedAt != null && _sameDay(completedAt, date)) {
          final double difficulty = (snapshot['difficultyScore'] as num?)?.toDouble() ?? task?.difficultyScore ?? 1;
          positive.add(ProductivityContribution(label: title, points: difficulty, kind: 'Task', detail: 'Completed and still complete at day end'));
        }
      }

      // Inline checklist subtasks are read from the task snapshot for this
      // date, not from the task's later live state.
      final Object? rawSubtasks = snapshot['subtasks'];
      final List<dynamic> subtaskSnapshots = rawSubtasks is List
          ? rawSubtasks
          : (task?.subtasks.map((Subtask item) => <String, dynamic>{
                'id': item.id,
                'title': item.title,
                'isCompleted': item.isCompleted,
                'completedAt': item.completedAt?.toIso8601String(),
                'difficultyScore': item.difficultyScore,
              }).toList() ?? <dynamic>[]);
      for (final dynamic raw in subtaskSnapshots) {
        if (raw is! Map) continue;
        final Map<String, dynamic> child = Map<String, dynamic>.from(raw);
        final DateTime? completedAt = DateTime.tryParse('${child['completedAt'] ?? ''}');
        if (child['isCompleted'] == true && completedAt != null && _sameDay(completedAt, date)) {
          positive.add(ProductivityContribution(
            label: (child['title'] as String?) ?? (child['id'] as String?) ?? 'Subtask',
            points: (child['difficultyScore'] as num?)?.toDouble() ?? 1,
            kind: 'Subtask',
            detail: 'Completed and still checked at day end',
          ));
        }
      }
    }

    // Backward compatibility for older or partial snapshots (including records
    // written before task-state fields were included). These retain the prior
    // event-based interpretation without affecting complete modern snapshots.
    if (legacyTaskIds.isEmpty) return;
    final Map<String, List<TaskProgressEvent>> progressByTask = <String, List<TaskProgressEvent>>{};
    for (final TaskProgressEvent event in progressEvents.where((TaskProgressEvent event) => legacyTaskIds.contains(event.taskId))) {
      progressByTask.putIfAbsent(event.taskId, () => <TaskProgressEvent>[]).add(event);
    }
    for (final List<TaskProgressEvent> events in progressByTask.values) {
      events.sort((TaskProgressEvent a, TaskProgressEvent b) => a.occurredAt.compareTo(b.occurredAt));
    }
    for (final String taskId in legacyTaskIds) {
      final Task? task = taskById[taskId];
      final TaskActivity? latest = latestSnapshotByTask[taskId];
      final Map<String, dynamic> historical = latest?.snapshot ?? <String, dynamic>{};
      final bool isContainer = historical['isGroup'] == true || historical['hasSubtasks'] == true ||
          ((historical['subtaskCount'] as num?)?.toInt() ?? 0) > 0 || task?.isGroup == true ||
          task?.subtasks.isNotEmpty == true || tasks.any((Task child) => child.parentTaskId == taskId);
      if (isContainer) continue;
      final String title = task?.title ?? (historical['title'] as String? ?? taskId);
      final List<TaskProgressEvent> events = progressByTask[taskId] ?? const <TaskProgressEvent>[];
      if (events.isNotEmpty) {
        double highWater = events.first.previousPercent.clamp(0, 100).toDouble();
        for (final TaskProgressEvent event in events) {
          final double nextHigh = event.newPercent > highWater ? event.newPercent : highWater;
          final double newlyReached = (nextHigh - highWater).clamp(0, 100).toDouble();
          if (newlyReached > 0 && _sameDay(event.occurredAt, date)) {
            positive.add(ProductivityContribution(label: title, points: event.difficultyScore * newlyReached / 100, kind: 'Progressive Task', detail: '${newlyReached.toStringAsFixed(1)}% legacy progress event'));
          }
          highWater = nextHigh;
        }
      }
    }

    final List<TaskActivity> orderedActivities = activities.toList()
      ..sort((TaskActivity a, TaskActivity b) => a.occurredAt.compareTo(b.occurredAt));
    final Set<String> awardedStandardTasks = <String>{};
    final Set<String> awardedSubtasks = <String>{};
    for (final TaskActivity event in orderedActivities) {
      if (!legacyTaskIds.contains(event.taskId)) continue;
      if (event.entityType == 'subtask' && event.eventType == 'subtask_completed') {
        if (awardedSubtasks.add(event.entityId) && _sameDay(event.occurredAt, date)) {
          final Map<String, dynamic> snapshot = event.snapshot;
          positive.add(ProductivityContribution(
            label: (snapshot['subtaskTitle'] as String?) ?? event.entityId,
            points: (snapshot['subtaskDifficultyScore'] as num?)?.toDouble() ?? 1,
            kind: 'Subtask', detail: 'Completed (legacy activity)',
          ));
        }
      }
      if (event.entityType != 'task' || event.eventType != 'task_completed') continue;
      final Map<String, dynamic> snapshot = event.snapshot;
      final Task? task = taskById[event.taskId];
      final bool progressive = snapshot['taskType'] == TaskType.progressive.name ||
          (snapshot['taskType'] == null && task?.taskType == TaskType.progressive);
      if (progressive) continue;
      if (!awardedStandardTasks.add(event.taskId)) continue;
      if (_sameDay(event.occurredAt, date)) {
        positive.add(ProductivityContribution(
          label: (snapshot['title'] as String?) ?? task?.title ?? event.taskId,
          points: (snapshot['difficultyScore'] as num?)?.toDouble() ?? task?.difficultyScore ?? 1,
          kind: 'Task', detail: 'Completed (legacy activity)',
        ));
      }
    }
  }

  double _currentHabitFraction(Habit habit, CompletionRecord record) {
    switch (habit.tracking) {
      case TrackingMethod.tick:
        return record.done ? 1 : 0;
      case TrackingMethod.count:
        final double goal = habit.dailyGoal ?? 1;
        return goal <= 0 ? 0 : (record.count / goal).clamp(0, 1).toDouble();
      case TrackingMethod.checklist:
        final Set<String> activeIds = habit.checklist.map((ChecklistItem item) => item.id).toSet();
        if (activeIds.isEmpty) return 0;
        final int checked = record.checkedItemIds.intersection(activeIds).length;
        return (checked / activeIds.length).clamp(0, 1).toDouble();
    }
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
