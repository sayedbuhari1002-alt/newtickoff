import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tickoff_replacement/domain/logic/productivity_engine.dart';
import 'package:tickoff_replacement/domain/models/models.dart';
import 'package:tickoff_replacement/state/app_data.dart';

void main() {
  const ProductivityEngine engine = ProductivityEngine();
  final DateTime day = DateTime(2026, 11, 8);
  const String key = '2026-11-08';

  ProductivityDayScore calculate({
    DateTime? scoreDate,
    DateTime? today,
    List<Habit> habits = const <Habit>[],
    Map<String, Map<String, CompletionRecord>> completions = const <String, Map<String, CompletionRecord>>{},
    List<Task> tasks = const <Task>[],
    List<TaskActivity> activities = const <TaskActivity>[],
    List<TaskProgressEvent> progressEvents = const <TaskProgressEvent>[],
    List<Assignment> assignments = const <Assignment>[],
    List<DistractionCategory> categories = const <DistractionCategory>[],
    List<DistractionLog> logs = const <DistractionLog>[],
    List<AppUsageRecord> usage = const <AppUsageRecord>[],
    DateTime? scoringStart,
  }) => engine.calculateDay(
    date: scoreDate ?? day,
    target: 15,
    habits: habits,
    completions: completions,
    tasks: tasks,
    activities: activities,
    progressEvents: progressEvents,
    assignments: assignments,
    distractionCategories: categories,
    distractionLogs: logs,
    appUsageRecords: usage,
    today: today ?? DateTime(2026, 11, 10),
    currentStateScoringStartDate: scoringStart,
  );

  test('Build Habit count completion awards proportional decimal points; Quit slip is penalty only', () {
    final Habit build = Habit(
      id: 'build', title: 'Read', createdAt: day,
      tracking: TrackingMethod.count, dailyGoal: 5, productivityPoints: 3.5,
    );
    final Habit quit = Habit(
      id: 'quit', title: 'Avoid scrolling', createdAt: day,
      type: HabitType.quit, quitPenalty: 2.25,
    );
    final score = calculate(
      habits: <Habit>[build, quit],
      completions: <String, Map<String, CompletionRecord>>{
        'build': <String, CompletionRecord>{key: CompletionRecord(habitId: 'build', dateKey: key, updatedAt: day, count: 2.5, productivityPoints: 3.5)},
        'quit': <String, CompletionRecord>{key: CompletionRecord(habitId: 'quit', dateKey: key, updatedAt: day, slipped: true)},
      },
    );
    expect(score.achievementPoints, closeTo(1.75, 0.0001));
    expect(score.penaltyPoints, closeTo(2.25, 0.0001));
    expect(score.netScore, 0);
    expect(score.rawNetScore, closeTo(-0.5, 0.0001));
  });

  test('Checklist Build Habit earns only the completed-item fraction', () {
    final Habit habit = Habit(
      id: 'checklist', title: 'Morning routine', createdAt: day,
      tracking: TrackingMethod.checklist, productivityPoints: 2.7,
      checklist: const <ChecklistItem>[
        ChecklistItem(id: 'a', title: 'Plan'),
        ChecklistItem(id: 'b', title: 'Read'),
        ChecklistItem(id: 'c', title: 'Exercise'),
      ],
    );
    final score = calculate(
      habits: <Habit>[habit],
      completions: <String, Map<String, CompletionRecord>>{
        'checklist': <String, CompletionRecord>{key: CompletionRecord(habitId: 'checklist', dateKey: key, updatedAt: day, checkedItemIds: const <String>{'a', 'c'})},
      },
    );
    expect(score.achievementPoints, closeTo(1.8, 0.0001));
  });

  test('Habit scoring uses saved type, tracking goal and checklist snapshots after habit edits', () {
    final Habit editedHabit = Habit(
      id: 'habit-history', title: 'Now a quit habit', createdAt: day,
      type: HabitType.quit, tracking: TrackingMethod.tick, dailyGoal: 1,
      productivityPoints: 4.5, quitPenalty: 4.0,
      archivedAt: DateTime(2026, 11, 9),
    );
    final CompletionRecord historical = CompletionRecord(
      habitId: 'habit-history', dateKey: key, updatedAt: day,
      count: 2.5, productivityPoints: 3.5, quitPenalty: 2.0,
      habitType: 'build', trackingMethod: 'count', dailyGoalSnapshot: 5,
    );
    final ProductivityDayScore score = calculate(
      habits: <Habit>[editedHabit],
      completions: <String, Map<String, CompletionRecord>>{
        'habit-history': <String, CompletionRecord>{key: historical},
      },
    );
    expect(score.achievementPoints, closeTo(1.75, 0.0001));
    expect(score.penaltyPoints, 0);
  });

  test('historical habit score uses the final difficulty saved for that date', () {
    final DateTime yesterday = DateTime(2026, 11, 13);
    final DateTime today = DateTime(2026, 11, 14);
    final Habit habit = Habit(
      id: 'updated-habit', title: 'Exam revision', createdAt: day,
      productivityPoints: 3,
    );
    final CompletionRecord record = CompletionRecord(
      habitId: habit.id, dateKey: '2026-11-13', updatedAt: yesterday,
      done: true, productivityPoints: 1,
      habitType: HabitType.build.name, trackingMethod: TrackingMethod.tick.name,
      dailyGoalSnapshot: 1, checklistItemIds: const <String>{},
    );

    final ProductivityDayScore score = calculate(
      scoreDate: yesterday,
      today: today,
      habits: <Habit>[habit],
      completions: <String, Map<String, CompletionRecord>>{
        habit.id: <String, CompletionRecord>{record.dateKey: record},
      },
    );

    expect(score.achievementPoints, 1);
    expect(score.contributions.single.points, 1);
  });

  test('Standard task and subtask awards use stored snapshots and decimal weights', () {
    final DateTime completedAt = DateTime(2026, 11, 8, 14);
    final List<TaskActivity> activities = <TaskActivity>[
      TaskActivity(
        id: 'task-event', taskId: 'deleted-task', entityId: 'deleted-task',
        entityType: 'task', eventType: 'task_completed', occurredAt: completedAt,
        snapshotJson: jsonEncode(<String, Object?>{'title': 'Research', 'difficultyScore': 2.5, 'hasSubtasks': false, 'isGroup': false}),
      ),
      TaskActivity(
        id: 'subtask-event', taskId: 'parent', entityId: 'subtask-1',
        entityType: 'subtask', eventType: 'subtask_completed', occurredAt: completedAt,
        snapshotJson: jsonEncode(<String, Object?>{'subtaskTitle': 'Write introduction', 'subtaskDifficultyScore': 1.7}),
      ),
    ];
    final score = calculate(activities: activities);
    expect(score.achievementPoints, closeTo(4.2, 0.0001));
    expect(score.contributions.map((ProductivityContribution value) => value.label), containsAll(<String>['Research', 'Write introduction']));
  });

  test('Legacy incomplete activity snapshots retain event-based progressive fallback', () {
    final Task task = Task(
      id: 'progress', title: 'Read textbook', createdAt: day, updatedAt: day,
      taskType: TaskType.progressive, progressMode: TaskProgressMode.percentage,
      progressValue: 70, difficultyScore: 2.5,
    );
    final List<TaskProgressEvent> events = <TaskProgressEvent>[
      TaskProgressEvent(id: 'p1', taskId: task.id, previousValue: 0, newValue: 50, previousPercent: 0, newPercent: 50, progressDelta: 50, occurredAt: DateTime(2026, 11, 7, 10), difficultyScore: 2.5),
      TaskProgressEvent(id: 'p2', taskId: task.id, previousValue: 50, newValue: 30, previousPercent: 50, newPercent: 30, progressDelta: -20, occurredAt: DateTime(2026, 11, 8, 9), difficultyScore: 2.5),
      TaskProgressEvent(id: 'p3', taskId: task.id, previousValue: 30, newValue: 70, previousPercent: 30, newPercent: 70, progressDelta: 40, occurredAt: DateTime(2026, 11, 8, 11), difficultyScore: 2.5),
      TaskProgressEvent(id: 'p4', taskId: task.id, previousValue: 70, newValue: 60, previousPercent: 70, newPercent: 60, progressDelta: -10, occurredAt: DateTime(2026, 11, 8, 13), difficultyScore: 2.5),
    ];
    final TaskActivity completionActivity = TaskActivity(
      id: 'progress-completed', taskId: task.id, entityId: task.id, entityType: 'task',
      eventType: 'task_completed', occurredAt: DateTime(2026, 11, 8, 11),
      snapshotJson: jsonEncode(<String, Object?>{'title': task.title, 'taskType': 'progressive', 'difficultyScore': 2.5}),
    );
    final score = calculate(tasks: <Task>[task], progressEvents: events, activities: <TaskActivity>[completionActivity]);
    expect(score.achievementPoints, closeTo(0.5, 0.0001));
  });

  test('Historical task scores survive a later task-type edit', () {
    final Task nowStandard = Task(
      id: 'formerly-progressive', title: 'Read a course', createdAt: day,
      updatedAt: day, taskType: TaskType.standard, difficultyScore: 2.5,
    );
    final TaskProgressEvent event = TaskProgressEvent(
      id: 'progress-before-edit', taskId: nowStandard.id,
      previousValue: 40, newValue: 60, previousPercent: 40,
      newPercent: 60, progressDelta: 20,
      occurredAt: DateTime(2026, 11, 8, 10), difficultyScore: 2.5,
    );
    final Task nowProgressive = Task(
      id: 'formerly-standard', title: 'Submit report', createdAt: day,
      updatedAt: day, taskType: TaskType.progressive, progressValue: 0,
      difficultyScore: 3.0,
    );
    final TaskActivity standardCompletion = TaskActivity(
      id: 'standard-before-edit', taskId: nowProgressive.id,
      entityId: nowProgressive.id, entityType: 'task',
      eventType: 'task_completed', occurredAt: DateTime(2026, 11, 8, 11),
      snapshotJson: jsonEncode(<String, Object?>{
        'title': 'Submit report', 'taskType': 'standard',
        'difficultyScore': 3.0, 'isGroup': false, 'hasSubtasks': false,
      }),
    );
    final ProductivityDayScore score = calculate(
      tasks: <Task>[nowStandard, nowProgressive],
      progressEvents: <TaskProgressEvent>[event],
      activities: <TaskActivity>[standardCompletion],
    );
    expect(score.achievementPoints, closeTo(3.5, 0.0001));
  });

  test('Assignment points are awarded on first completion date', () {
    final Assignment assignment = Assignment(
      id: 'assignment', title: 'Submit lab record', createdAt: day,
      updatedAt: day, difficultyScore: 3.25, isCompleted: true,
      completedAt: DateTime(2026, 11, 8, 16), completedPoints: 2.75,
    );
    final score = calculate(assignments: <Assignment>[assignment]);
    expect(score.achievementPoints, closeTo(2.75, 0.0001));
  });

  test('Overlapping manual and automatic distraction time is charged only once at highest severity', () {
    final DistractionCategory manualCategory = DistractionCategory(
      id: 'manual', name: 'Social media', severityPointsPerHour: 2,
      createdAt: day,
    );
    final DistractionCategory automaticCategory = DistractionCategory(
      id: 'automatic', name: 'Video apps', severityPointsPerHour: 4,
      createdAt: day,
    );
    final score = calculate(
      categories: <DistractionCategory>[manualCategory, automaticCategory],
      logs: <DistractionLog>[
        DistractionLog(id: 'manual-log', categoryId: 'manual', startAt: DateTime(2026, 11, 8, 12), endAt: DateTime(2026, 11, 8, 13), severityPointsPerHour: 2),
      ],
      usage: <AppUsageRecord>[
        AppUsageRecord(id: 'usage', categoryId: 'automatic', packageName: 'com.example.video', startAt: DateTime(2026, 11, 8, 12, 30), endAt: DateTime(2026, 11, 8, 13, 30), severityPointsPerHour: 4),
      ],
    );
    // 30 min x 2 points/hour + 60 min x 4 points/hour = 5 points.
    expect(score.penaltyPoints, closeTo(5, 0.0001));
  });

  test('Automatic app penalties begin only after that app exceeds its daily allowance', () {
    final DistractionCategory category = DistractionCategory(
      id: 'social-apps', name: 'Social apps', severityPointsPerHour: 60,
      createdAt: day, autoTrack: true,
      packageNames: const <String>['com.instagram.android'],
      // The category is now configured for 60 minutes, but these saved
      // sessions retain the 30-minute allowance that applied when recorded.
      dailyAllowanceMinutesByPackage: const <String, int>{'com.instagram.android': 60},
    );
    final ProductivityDayScore score = calculate(
      categories: <DistractionCategory>[category],
      usage: <AppUsageRecord>[
        AppUsageRecord(
          id: 'instagram-1', categoryId: category.id,
          packageName: 'com.instagram.android',
          startAt: DateTime(2026, 11, 8, 12),
          endAt: DateTime(2026, 11, 8, 12, 20),
          severityPointsPerHour: 60, dailyAllowanceMinutes: 30,
        ),
        AppUsageRecord(
          id: 'instagram-2', categoryId: category.id,
          packageName: 'com.instagram.android',
          startAt: DateTime(2026, 11, 8, 14),
          endAt: DateTime(2026, 11, 8, 14, 45),
          severityPointsPerHour: 60, dailyAllowanceMinutes: 30,
        ),
      ],
    );
    // Total usage is 65 minutes. The first 30 minutes are free, so only
    // 35 minutes at 60 points/hour are deducted.
    expect(score.penaltyPoints, closeTo(35, 0.0001));
  });

  test('Automatic app usage within the daily allowance has no penalty', () {
    final DistractionCategory category = DistractionCategory(
      id: 'social-apps', name: 'Social apps', severityPointsPerHour: 60,
      createdAt: day, autoTrack: true,
      packageNames: const <String>['com.instagram.android'],
      dailyAllowanceMinutesByPackage: const <String, int>{'com.instagram.android': 30},
    );
    final ProductivityDayScore score = calculate(
      categories: <DistractionCategory>[category],
      usage: <AppUsageRecord>[
        AppUsageRecord(
          id: 'instagram-1', categoryId: category.id,
          packageName: 'com.instagram.android',
          startAt: DateTime(2026, 11, 8, 12),
          endAt: DateTime(2026, 11, 8, 12, 30),
          severityPointsPerHour: 60, dailyAllowanceMinutes: 30,
        ),
      ],
    );
    expect(score.penaltyPoints, 0);
  });

  test('Target overrides affect one date while defaults apply from their effective date', () {
    final AppData data = AppData(
      productivityTargets: const <ProductivityTargetChange>[
        ProductivityTargetChange(effectiveDate: '0001-01-01', target: 15),
        ProductivityTargetChange(effectiveDate: '2026-11-10', target: 20),
      ],
      productivityTargetOverrides: const <String, double>{'2026-11-11': 12.5},
    );
    expect(data.targetForDate(DateTime(2026, 11, 9)), 15);
    expect(data.targetForDate(DateTime(2026, 11, 10)), 20);
    expect(data.targetForDate(DateTime(2026, 11, 11)), 12.5);
    expect(data.targetForDate(DateTime(2026, 11, 12)), 20);
  });

  test('Suggestions include upcoming and unscheduled leaf tasks but exclude today and overdue work', () {
    Task task(String id, {TaskPriority priority = TaskPriority.medium, DateTime? dueAt, DateTime? scheduledDate, bool completed = false, bool paused = false, bool isGroup = false, String? parentTaskId, double difficulty = 1}) => Task(
      id: id, title: id, createdAt: day, updatedAt: day, priority: priority,
      dueAt: dueAt, scheduledDate: scheduledDate, isCompleted: completed,
      isPaused: paused, isGroup: isGroup, parentTaskId: parentTaskId,
      difficultyScore: difficulty,
    );
    final recommendations = engine.recommendTasks(
      date: day,
      remainingTarget: 5,
      tasks: <Task>[
        task('overdue-high', priority: TaskPriority.high, dueAt: DateTime(2026, 11, 7)),
        task('group-parent', isGroup: true),
        task('future-deadline', dueAt: DateTime(2026, 11, 10), difficulty: 8),
        task('future-plan', scheduledDate: DateTime(2026, 11, 9)),
        task('today-plan', scheduledDate: day),
        task('unscheduled', priority: TaskPriority.high, difficulty: 6),
        task('completed', completed: true),
        task('paused', paused: true),
      ],
    );
    final Set<String> ids = recommendations.map((RecommendedTask value) => value.task.id).toSet();
    expect(ids, <String>{'future-deadline', 'future-plan', 'unscheduled'});
    expect(ids, isNot(contains('today-plan')));
    expect(ids, isNot(contains('overdue-high')));
    expect(ids, isNot(contains('group-parent')));
    expect(ids, isNot(contains('completed')));
    expect(ids, isNot(contains('paused')));
    expect(recommendations.first.task.id, 'future-deadline');
  });

  test('A child task may be suggested without suggesting its group parent', () {
    final Task parent = Task(
      id: 'parent', title: 'Project', createdAt: day, updatedAt: day,
      isGroup: true,
    );
    final Task child = Task(
      id: 'child', title: 'Write documentation', createdAt: day, updatedAt: day,
      parentTaskId: parent.id, priority: TaskPriority.high,
    );
    final List<RecommendedTask> recommendations = engine.recommendTasks(
      tasks: <Task>[parent, child], date: day, remainingTarget: 5,
    );
    expect(recommendations.map((RecommendedTask value) => value.task.id).toList(), <String>['child']);
  });

  test('Today habit points follow the current saved count and checklist state', () {
    final DateTime now = DateTime.now();
    final String todayKey = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final Habit countHabit = Habit(
      id: 'reading', title: 'Reading', createdAt: now,
      tracking: TrackingMethod.count, dailyGoal: 10, productivityPoints: 10,
    );
    final Habit checklistHabit = Habit(
      id: 'routine', title: 'Routine', createdAt: now,
      tracking: TrackingMethod.checklist, productivityPoints: 5,
      checklist: const <ChecklistItem>[
        ChecklistItem(id: 'one', title: 'Stretch'),
        ChecklistItem(id: 'two', title: 'Read'),
        ChecklistItem(id: 'three', title: 'Plan'),
        ChecklistItem(id: 'four', title: 'Walk'),
        ChecklistItem(id: 'five', title: 'Water'),
      ],
    );
    final CompletionRecord countRecord = CompletionRecord(
      habitId: countHabit.id, dateKey: todayKey, updatedAt: now, count: 2.5,
    );
    final CompletionRecord checklistRecord = CompletionRecord(
      habitId: checklistHabit.id, dateKey: todayKey, updatedAt: now,
      checkedItemIds: const <String>{'one', 'two'},
    );
    final Map<String, Map<String, CompletionRecord>> records = <String, Map<String, CompletionRecord>>{
      countHabit.id: <String, CompletionRecord>{todayKey: countRecord},
      checklistHabit.id: <String, CompletionRecord>{todayKey: checklistRecord},
    };
    final ProductivityDayScore partiallyComplete = calculate(
      scoreDate: now,
      today: now,
      habits: <Habit>[countHabit, checklistHabit],
      completions: records,
    );
    expect(partiallyComplete.achievementPoints, closeTo(4.5, 0.0001));

    final ProductivityDayScore reset = calculate(
      scoreDate: now,
      today: now,
      habits: <Habit>[countHabit, checklistHabit],
      completions: <String, Map<String, CompletionRecord>>{
        countHabit.id: <String, CompletionRecord>{todayKey: countRecord.copyWith(count: 0)},
        checklistHabit.id: <String, CompletionRecord>{todayKey: checklistRecord.copyWith(checkedItemIds: const <String>{})},
      },
    );
    expect(reset.achievementPoints, 0);
  });

  test('Today progressive task score follows net current progress from day start', () {
    final DateTime now = DateTime.now();
    final Task task = Task(
      id: 'cisco', title: 'Cisco', createdAt: now, updatedAt: now,
      taskType: TaskType.progressive, progressValue: 20,
      difficultyScore: 5,
    );
    final TaskProgressEvent event = TaskProgressEvent(
      id: 'progress-20', taskId: task.id, previousValue: 0, newValue: 20,
      previousPercent: 0, newPercent: 20, progressDelta: 20,
      occurredAt: now, difficultyScore: 5,
    );
    final ProductivityDayScore atTwenty = calculate(
      scoreDate: now,
      today: now,
      tasks: <Task>[task],
      progressEvents: <TaskProgressEvent>[event],
    );
    expect(atTwenty.achievementPoints, closeTo(1, 0.0001));

    final Task reducedTask = task.copyWith(progressValue: 10, isCompleted: false, clearCompletedAt: true);
    final TaskProgressEvent reduction = TaskProgressEvent(
      id: 'progress-10', taskId: task.id, previousValue: 20, newValue: 10,
      previousPercent: 20, newPercent: 10, progressDelta: -10,
      occurredAt: now.add(const Duration(seconds: 30)), difficultyScore: 5,
    );
    final ProductivityDayScore atTen = calculate(
      scoreDate: now,
      today: now,
      tasks: <Task>[reducedTask],
      progressEvents: <TaskProgressEvent>[event, reduction],
    );
    expect(atTen.achievementPoints, closeTo(0.5, 0.0001));

    final Task resetTask = task.copyWith(progressValue: 0, isCompleted: false, clearCompletedAt: true);
    final TaskProgressEvent reset = TaskProgressEvent(
      id: 'progress-zero', taskId: task.id, previousValue: 20, newValue: 0,
      previousPercent: 20, newPercent: 0, progressDelta: -20,
      occurredAt: now.add(const Duration(minutes: 1)), difficultyScore: 5,
    );
    final ProductivityDayScore atZero = calculate(
      scoreDate: now,
      today: now,
      tasks: <Task>[resetTask],
      progressEvents: <TaskProgressEvent>[event, reset],
    );
    expect(atZero.achievementPoints, 0);
  });

  test('Progressive task slider changes are scored only above the day-start value', () {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final Task task = Task(
      id: 'training', title: 'Training',
      createdAt: today.subtract(const Duration(days: 1)), updatedAt: now,
      taskType: TaskType.progressive, progressValue: 10,
      difficultyScore: 5,
    );
    final DateTime morning = today.add(const Duration(hours: 9));
    final List<TaskProgressEvent> events = <TaskProgressEvent>[
      TaskProgressEvent(
        id: 'training-up', taskId: task.id,
        previousValue: 10, newValue: 36,
        previousPercent: 10, newPercent: 36, progressDelta: 26,
        occurredAt: morning, difficultyScore: 5,
      ),
      TaskProgressEvent(
        id: 'training-back', taskId: task.id,
        previousValue: 36, newValue: 10,
        previousPercent: 36, newPercent: 10, progressDelta: -26,
        occurredAt: morning.add(const Duration(minutes: 2)), difficultyScore: 5,
      ),
    ];
    final ProductivityDayScore returnedToYesterday = calculate(
      scoreDate: today,
      today: today,
      tasks: <Task>[task],
      progressEvents: events,
    );
    expect(returnedToYesterday.achievementPoints, 0);

    final Task finalTwenty = task.copyWith(progressValue: 20, updatedAt: now);
    final List<TaskProgressEvent> partialEvents = <TaskProgressEvent>[
      events.first,
      TaskProgressEvent(
        id: 'training-partial', taskId: task.id,
        previousValue: 36, newValue: 20,
        previousPercent: 36, newPercent: 20, progressDelta: -16,
        occurredAt: morning.add(const Duration(minutes: 3)), difficultyScore: 5,
      ),
    ];
    final ProductivityDayScore partialNet = calculate(
      scoreDate: today,
      today: today,
      tasks: <Task>[finalTwenty],
      progressEvents: partialEvents,
    );
    expect(partialNet.achievementPoints, closeTo(0.5, 0.0001));
  });

  test('Count-based progressive tasks use their current saved count as a fraction of target', () {
    final DateTime now = DateTime.now();
    final Task task = Task(
      id: 'count-progress', title: 'Cisco chapters', createdAt: now,
      updatedAt: now, taskType: TaskType.progressive,
      progressMode: TaskProgressMode.count, progressValue: 5,
      progressTarget: 10, progressUnit: 'chapters', difficultyScore: 8,
    );
    final TaskProgressEvent event = TaskProgressEvent(
      id: 'count-progress-event', taskId: task.id,
      previousValue: 0, newValue: 5, previousPercent: 0,
      newPercent: 50, progressDelta: 50, occurredAt: now,
      difficultyScore: 8,
    );
    final ProductivityDayScore half = calculate(
      scoreDate: now, today: now, tasks: <Task>[task],
      progressEvents: <TaskProgressEvent>[event],
    );
    expect(half.achievementPoints, 4);

    final Task reduced = task.copyWith(progressValue: 2.5, updatedAt: now.add(const Duration(minutes: 1)));
    final ProductivityDayScore reducedScore = calculate(
      scoreDate: now, today: now, tasks: <Task>[reduced],
      progressEvents: <TaskProgressEvent>[event, TaskProgressEvent(
        id: 'count-progress-reduced', taskId: task.id,
        previousValue: 5, newValue: 2.5, previousPercent: 50,
        newPercent: 25, progressDelta: -25,
        occurredAt: now.add(const Duration(minutes: 1)), difficultyScore: 8,
      )],
    );
    expect(reducedScore.achievementPoints, 2);
  });

  test('Dates before activation keep the previous progressive-event score', () {
    final DateTime now = DateTime.now();
    final DateTime oldDay = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 2));
    final Task task = Task(
      id: 'legacy-progress', title: 'Old Cisco task', createdAt: oldDay,
      updatedAt: oldDay.add(const Duration(hours: 11)),
      taskType: TaskType.progressive, progressValue: 0, difficultyScore: 5,
    );
    final List<TaskProgressEvent> events = <TaskProgressEvent>[
      TaskProgressEvent(id: 'legacy-20', taskId: task.id, previousValue: 0, newValue: 20, previousPercent: 0, newPercent: 20, progressDelta: 20, occurredAt: oldDay.add(const Duration(hours: 9)), difficultyScore: 5),
      TaskProgressEvent(id: 'legacy-zero', taskId: task.id, previousValue: 20, newValue: 0, previousPercent: 20, newPercent: 0, progressDelta: -20, occurredAt: oldDay.add(const Duration(hours: 11)), difficultyScore: 5),
    ];
    final TaskActivity finalState = TaskActivity(
      id: 'legacy-final-state', taskId: task.id, entityId: task.id,
      entityType: 'task', eventType: 'task_progress_updated',
      occurredAt: oldDay.add(const Duration(hours: 11)),
      snapshotJson: jsonEncode(<String, Object?>{
        'title': task.title, 'isCompleted': false, 'completedAt': null,
        'isGroup': false, 'hasSubtasks': false, 'subtaskCount': 0,
        'taskType': 'progressive', 'progressValue': 0,
        'progressTarget': 100, 'progressMode': 'percentage',
        'difficultyScore': 5, 'subtasks': <Object>[],
      }),
    );

    final ProductivityDayScore preserved = calculate(
      scoreDate: oldDay, today: now, scoringStart: now,
      tasks: <Task>[task], activities: <TaskActivity>[finalState],
      progressEvents: events,
    );
    final ProductivityDayScore newModel = calculate(
      scoreDate: oldDay, today: now, scoringStart: oldDay,
      tasks: <Task>[task], activities: <TaskActivity>[finalState],
      progressEvents: events,
    );
    expect(preserved.achievementPoints, 1);
    expect(newModel.achievementPoints, 0);
  });

  test('Progressive task end-of-day snapshots preserve earlier scores after later resets', () {
    final DateTime today = DateTime.now();
    final DateTime monday = DateTime(today.year, today.month, today.day).subtract(const Duration(days: 2));
    final DateTime tuesday = monday.add(const Duration(days: 1));
    final Task task = Task(
      id: 'progress-history', title: 'Study Cisco', createdAt: monday,
      updatedAt: tuesday, taskType: TaskType.progressive,
      progressValue: 0, difficultyScore: 5,
    );
    TaskActivity snapshot(String id, String eventType, DateTime at, double progress) => TaskActivity(
      id: id, taskId: task.id, entityId: task.id, entityType: 'task',
      eventType: eventType, occurredAt: at,
      snapshotJson: jsonEncode(<String, Object?>{
        'title': task.title, 'difficultyScore': 5, 'isGroup': false,
        'hasSubtasks': false, 'subtaskCount': 0, 'isCompleted': false,
        'completedAt': null, 'taskType': 'progressive',
        'progressMode': 'percentage', 'progressValue': progress,
        'progressTarget': 100, 'subtasks': <Object>[],
      }),
    );
    final List<TaskActivity> activities = <TaskActivity>[
      snapshot('monday-progress', 'task_progress_updated', monday.add(const Duration(hours: 18)), 20),
      snapshot('tuesday-reset', 'task_progress_updated', tuesday.add(const Duration(hours: 9)), 0),
    ];
    final List<TaskProgressEvent> events = <TaskProgressEvent>[
      TaskProgressEvent(id: 'monday-event', taskId: task.id, previousValue: 0, newValue: 20, previousPercent: 0, newPercent: 20, progressDelta: 20, occurredAt: monday.add(const Duration(hours: 18)), difficultyScore: 5),
      TaskProgressEvent(id: 'tuesday-event', taskId: task.id, previousValue: 20, newValue: 0, previousPercent: 20, newPercent: 0, progressDelta: -20, occurredAt: tuesday.add(const Duration(hours: 9)), difficultyScore: 5),
    ];
    final ProductivityDayScore mondayScore = calculate(scoreDate: monday, today: today, scoringStart: monday, tasks: <Task>[task], activities: activities, progressEvents: events);
    final ProductivityDayScore tuesdayScore = calculate(scoreDate: tuesday, today: today, scoringStart: monday, tasks: <Task>[task], activities: activities, progressEvents: events);
    expect(mondayScore.achievementPoints, closeTo(1, 0.0001));
    expect(tuesdayScore.achievementPoints, 0);
  });

  test('historical progressive task awards only the net progress earned that day', () {
    final DateTime today = DateTime(2026, 11, 14);
    final DateTime firstDay = DateTime(2026, 11, 12);
    final DateTime secondDay = DateTime(2026, 11, 13);
    final Task currentTask = Task(
      id: 'training-history', title: 'Cisco Training',
      createdAt: firstDay, updatedAt: secondDay.add(const Duration(hours: 17)),
      taskType: TaskType.progressive, progressValue: 15,
      difficultyScore: 5,
    );

    TaskActivity snapshot(String id, DateTime at, double progress) => TaskActivity(
      id: id, taskId: currentTask.id, entityId: currentTask.id,
      entityType: 'task', eventType: 'task_progress_updated', occurredAt: at,
      snapshotJson: jsonEncode(<String, Object?>{
        'title': currentTask.title,
        'difficultyScore': 5,
        'isGroup': false,
        'hasSubtasks': false,
        'subtaskCount': 0,
        'isCompleted': false,
        'completedAt': null,
        'taskType': 'progressive',
        'progressMode': 'percentage',
        'progressValue': progress,
        'progressTarget': 100,
        'subtasks': <Object>[],
      }),
    );

    final List<TaskActivity> activities = <TaskActivity>[
      snapshot('day-one-end', firstDay.add(const Duration(hours: 18)), 10),
      snapshot('day-two-end', secondDay.add(const Duration(hours: 17)), 15),
    ];
    final List<TaskProgressEvent> events = <TaskProgressEvent>[
      TaskProgressEvent(
        id: 'day-one-progress', taskId: currentTask.id,
        previousValue: 0, newValue: 10, previousPercent: 0,
        newPercent: 10, progressDelta: 10,
        occurredAt: firstDay.add(const Duration(hours: 18)), difficultyScore: 5,
      ),
      TaskProgressEvent(
        id: 'day-two-progress', taskId: currentTask.id,
        previousValue: 10, newValue: 15, previousPercent: 10,
        newPercent: 15, progressDelta: 5,
        occurredAt: secondDay.add(const Duration(hours: 17)), difficultyScore: 5,
      ),
    ];

    final ProductivityDayScore firstDayScore = calculate(
      scoreDate: firstDay, today: today, scoringStart: firstDay,
      tasks: <Task>[currentTask], activities: activities,
      progressEvents: events,
    );
    final ProductivityDayScore secondDayScore = calculate(
      scoreDate: secondDay, today: today, scoringStart: firstDay,
      tasks: <Task>[currentTask], activities: activities,
      progressEvents: events,
    );

    expect(firstDayScore.achievementPoints, closeTo(0.5, 0.0001));
    expect(secondDayScore.achievementPoints, closeTo(0.25, 0.0001));
    expect(secondDayScore.contributions.single.detail,
        '15.0% cumulative · +5.0% that day');
  });

  test('historical progressive slider returning to its start value earns zero', () {
    final DateTime today = DateTime(2026, 11, 14);
    final DateTime yesterday = DateTime(2026, 11, 13);
    final Task task = Task(
      id: 'training-return', title: 'Training',
      createdAt: yesterday.subtract(const Duration(days: 1)),
      updatedAt: yesterday.add(const Duration(hours: 11)),
      taskType: TaskType.progressive, progressValue: 10, difficultyScore: 5,
    );
    TaskActivity activity(String id, DateTime at, double progress) => TaskActivity(
      id: id, taskId: task.id, entityId: task.id, entityType: 'task',
      eventType: 'task_progress_updated', occurredAt: at,
      snapshotJson: jsonEncode(<String, Object?>{
        'title': task.title, 'difficultyScore': 5, 'isGroup': false,
        'hasSubtasks': false, 'subtaskCount': 0, 'isCompleted': false,
        'completedAt': null, 'taskType': 'progressive',
        'progressMode': 'percentage', 'progressValue': progress,
        'progressTarget': 100, 'subtasks': <Object>[],
      }),
    );
    final DateTime first = yesterday.add(const Duration(hours: 9));
    final List<TaskProgressEvent> events = <TaskProgressEvent>[
      TaskProgressEvent(
        id: 'up', taskId: task.id, previousValue: 10, newValue: 36,
        previousPercent: 10, newPercent: 36, progressDelta: 26,
        occurredAt: first, difficultyScore: 5,
      ),
      TaskProgressEvent(
        id: 'back', taskId: task.id, previousValue: 36, newValue: 10,
        previousPercent: 36, newPercent: 10, progressDelta: -26,
        occurredAt: first.add(const Duration(minutes: 2)), difficultyScore: 5,
      ),
    ];
    final ProductivityDayScore score = calculate(
      scoreDate: yesterday, today: today, scoringStart: yesterday,
      tasks: <Task>[task],
      activities: <TaskActivity>[
        activity('up-snapshot', first, 36),
        activity('back-snapshot', first.add(const Duration(minutes: 2)), 10),
      ],
      progressEvents: events,
    );
    expect(score.achievementPoints, 0);
  });

  test('Inline subtask history uses the checked state saved at each day end', () {
    final DateTime now = DateTime.now();
    final DateTime monday = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 2));
    final DateTime tuesday = monday.add(const Duration(days: 1));
    final Task parent = Task(
      id: 'history-parent', title: 'Project plan', createdAt: monday,
      updatedAt: tuesday,
      subtasks: <Subtask>[Subtask(
        id: 'research', title: 'Research', createdAt: monday,
        isCompleted: false, difficultyScore: 2,
      )],
    );
    TaskActivity subtaskSnapshot(String id, String type, DateTime at, bool checked, DateTime? completedAt) => TaskActivity(
      id: id, taskId: parent.id, entityId: 'research', entityType: 'subtask',
      eventType: type, occurredAt: at,
      snapshotJson: jsonEncode(<String, Object?>{
        'title': parent.title, 'difficultyScore': 4, 'isGroup': false,
        'hasSubtasks': true, 'subtaskCount': 1, 'isCompleted': false,
        'completedAt': null, 'taskType': 'standard',
        'subtasks': <Object>[
          <String, Object?>{
            'id': 'research', 'title': 'Research', 'isCompleted': checked,
            'completedAt': completedAt?.toIso8601String(), 'difficultyScore': 2,
          },
        ],
      }),
    );
    final List<TaskActivity> activities = <TaskActivity>[
      subtaskSnapshot('checked-monday', 'subtask_completed', monday.add(const Duration(hours: 10)), true, monday.add(const Duration(hours: 10))),
      subtaskSnapshot('unchecked-tuesday', 'subtask_uncompleted', tuesday.add(const Duration(hours: 11)), false, null),
    ];
    final ProductivityDayScore mondayScore = calculate(scoreDate: monday, today: now, scoringStart: monday, tasks: <Task>[parent], activities: activities);
    final ProductivityDayScore tuesdayScore = calculate(scoreDate: tuesday, today: now, scoringStart: monday, tasks: <Task>[parent], activities: activities);
    expect(mondayScore.achievementPoints, 2);
    expect(tuesdayScore.achievementPoints, 0);
  });

  test('Today standard tasks and inline subtasks score only while currently completed', () {
    final DateTime now = DateTime.now();
    final Task standard = Task(
      id: 'standard', title: 'Cisco quiz', createdAt: now, updatedAt: now,
      isCompleted: false, difficultyScore: 6,
    );
    final TaskActivity staleCompletion = TaskActivity(
      id: 'stale', taskId: standard.id, entityId: standard.id,
      entityType: 'task', eventType: 'task_completed', occurredAt: now,
      snapshotJson: jsonEncode(<String, Object?>{'title': 'Cisco quiz', 'difficultyScore': 6, 'isGroup': false, 'hasSubtasks': false}),
    );
    final Task checklist = Task(
      id: 'parent', title: 'Project', createdAt: now, updatedAt: now,
      subtasks: <Subtask>[
        Subtask(id: 'a', title: 'Design', createdAt: now, isCompleted: true, completedAt: now, difficultyScore: 2),
        Subtask(id: 'b', title: 'Implement', createdAt: now, isCompleted: false, difficultyScore: 3),
      ],
    );
    final ProductivityDayScore score = calculate(
      scoreDate: now,
      today: now,
      tasks: <Task>[standard, checklist],
      activities: <TaskActivity>[staleCompletion],
    );
    expect(score.achievementPoints, closeTo(2, 0.0001));
    expect(score.contributions.map((ProductivityContribution item) => item.label), <String>['Design']);

    final Task uncheckedChecklist = checklist.copyWith(
      subtasks: checklist.subtasks.map((Subtask item) => item.copyWith(
        isCompleted: false,
        clearCompletedAt: true,
      )).toList(),
    );
    final ProductivityDayScore uncheckedScore = calculate(
      scoreDate: now,
      today: now,
      tasks: <Task>[uncheckedChecklist],
    );
    expect(uncheckedScore.achievementPoints, 0);

    final Task completedStandard = standard.copyWith(isCompleted: true, completedAt: now);
    final ProductivityDayScore completedScore = calculate(
      scoreDate: now,
      today: now,
      tasks: <Task>[completedStandard],
    );
    expect(completedScore.achievementPoints, 6);
  });

  test('First-class task groups score current completed children, never the parent', () {
    final DateTime now = DateTime.now();
    final Task parent = Task(
      id: 'group', title: 'Project', createdAt: now, updatedAt: now,
      isGroup: true, isCompleted: true, completedAt: now, difficultyScore: 10,
    );
    final Task childDone = Task(
      id: 'child-done', title: 'Research', createdAt: now, updatedAt: now,
      parentTaskId: parent.id, isCompleted: true, completedAt: now,
      difficultyScore: 3,
    );
    final Task childOpen = Task(
      id: 'child-open', title: 'Write report', createdAt: now, updatedAt: now,
      parentTaskId: parent.id, difficultyScore: 4,
    );
    final ProductivityDayScore score = calculate(
      scoreDate: now,
      today: now,
      tasks: <Task>[parent, childDone, childOpen],
    );
    expect(score.achievementPoints, 3);
    expect(score.contributions.map((ProductivityContribution item) => item.label), <String>['Research']);
  });

  test('Changing a task today does not rewrite its previous-day score', () {
    final DateTime now = DateTime.now();
    final DateTime previousDay = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
    final Task reopened = Task(
      id: 'monday-task', title: 'Monday work', createdAt: previousDay,
      updatedAt: now, isCompleted: false, difficultyScore: 4,
    );
    final TaskActivity completedYesterday = TaskActivity(
      id: 'monday-completion', taskId: reopened.id, entityId: reopened.id,
      entityType: 'task', eventType: 'task_completed', occurredAt: previousDay.add(const Duration(hours: 10)),
      snapshotJson: jsonEncode(<String, Object?>{
        'title': 'Monday work', 'difficultyScore': 4, 'isGroup': false,
        'hasSubtasks': false, 'subtaskCount': 0, 'isCompleted': true,
        'completedAt': previousDay.add(const Duration(hours: 10)).toIso8601String(),
        'taskType': 'standard', 'subtasks': <Object>[],
      }),
    );
    final TaskActivity reopenedToday = TaskActivity(
      id: 'tuesday-reopen', taskId: reopened.id, entityId: reopened.id,
      entityType: 'task', eventType: 'task_reopened', occurredAt: now,
      snapshotJson: jsonEncode(<String, Object?>{
        'title': 'Monday work', 'difficultyScore': 4, 'isGroup': false,
        'hasSubtasks': false, 'subtaskCount': 0, 'isCompleted': false,
        'completedAt': null, 'taskType': 'standard', 'subtasks': <Object>[],
      }),
    );
    final ProductivityDayScore historical = calculate(
      scoreDate: previousDay,
      today: now,
      scoringStart: previousDay,
      tasks: <Task>[reopened],
      activities: <TaskActivity>[completedYesterday, reopenedToday],
    );
    final ProductivityDayScore today = calculate(
      scoreDate: now,
      today: now,
      tasks: <Task>[reopened],
      activities: <TaskActivity>[completedYesterday, reopenedToday],
    );
    expect(historical.achievementPoints, 4);
    expect(today.achievementPoints, 0);
  });
}
