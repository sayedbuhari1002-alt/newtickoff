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
    List<Habit> habits = const <Habit>[],
    Map<String, Map<String, CompletionRecord>> completions = const <String, Map<String, CompletionRecord>>{},
    List<Task> tasks = const <Task>[],
    List<TaskActivity> activities = const <TaskActivity>[],
    List<TaskProgressEvent> progressEvents = const <TaskProgressEvent>[],
    List<Assignment> assignments = const <Assignment>[],
    List<DistractionCategory> categories = const <DistractionCategory>[],
    List<DistractionLog> logs = const <DistractionLog>[],
    List<AppUsageRecord> usage = const <AppUsageRecord>[],
  }) => engine.calculateDay(
    date: day,
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

  test('Progressive task awards only new high-water progress and never re-awards regressed work', () {
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

  test('Recommendations exclude future scheduled, completed, paused and already scheduled tasks', () {
    Task task(String id, {TaskPriority priority = TaskPriority.medium, DateTime? dueAt, DateTime? scheduledDate, bool completed = false, bool paused = false, bool isGroup = false, String? parentTaskId}) => Task(
      id: id, title: id, createdAt: day, updatedAt: day, priority: priority,
      dueAt: dueAt, scheduledDate: scheduledDate, isCompleted: completed,
      isPaused: paused, isGroup: isGroup, parentTaskId: parentTaskId,
    );
    final recommendations = engine.recommendTasks(
      date: day,
      remainingTarget: 5,
      tasks: <Task>[
        task('urgent-high', priority: TaskPriority.high, dueAt: DateTime(2026, 11, 8, 18)),
        task('group-parent', isGroup: true),
        task('group-child', parentTaskId: 'group-parent'),
        task('future-deadline', dueAt: DateTime(2026, 11, 10)),
        task('future-plan', scheduledDate: DateTime(2026, 11, 9)),
        task('today-plan', scheduledDate: day),
        task('completed', completed: true),
        task('paused', paused: true),
      ],
    );
    expect(recommendations.map((RecommendedTask value) => value.task.id).toSet(), <String>{'urgent-high', 'group-child'});
    expect(recommendations.first.task.id, 'urgent-high');
  });
}
