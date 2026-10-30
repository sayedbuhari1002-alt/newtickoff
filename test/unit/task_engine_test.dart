import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tickoff_replacement/domain/logic/task_engine.dart';
import 'package:tickoff_replacement/domain/models/models.dart';

DateTime d(int day, {int month = 11}) => DateTime(2026, month, day);

Task makeTask({
  String id = 't1',
  String title = 'Task',
  DateTime? dueAt,
  DateTime? reminderAt,
  TaskPriority priority = TaskPriority.medium,
  String category = 'Study',
  bool completed = false,
  bool paused = false,
  DateTime? completedAt,
  List<Subtask> subtasks = const <Subtask>[],
}) => Task(
      id: id,
      title: title,
      dueAt: dueAt,
      reminderAt: reminderAt,
      priority: priority,
      category: category,
      isCompleted: completed,
      completedAt: completedAt,
      isPaused: paused,
      subtasks: subtasks,
      createdAt: DateTime(2026, 10, 20),
      updatedAt: DateTime(2026, 10, 20),
    );

TaskActivity activity({
  required String id,
  required String taskId,
  required DateTime at,
  required String event,
  required Map<String, dynamic> snapshot,
  String entityType = 'task',
  String? entityId,
}) => TaskActivity(
      id: id,
      taskId: taskId,
      entityId: entityId ?? taskId,
      entityType: entityType,
      eventType: event,
      occurredAt: at,
      snapshotJson: jsonEncode(snapshot),
    );

Map<String, dynamic> snapshot({
  bool completed = false,
  DateTime? dueAt,
  bool hasSubtasks = false,
  String priority = 'high',
  bool paused = false,
  DateTime? subtaskDueAt,
}) => <String, dynamic>{
      'title': 'Task',
      'dueAt': dueAt?.toIso8601String(),
      'priority': priority,
      'isCompleted': completed,
      'isPaused': paused,
      'hasSubtasks': hasSubtasks,
      if (subtaskDueAt != null) 'subtaskDueAt': subtaskDueAt.toIso8601String(),
    };

void main() {
  group('Reminder-window visibility and overdue filtering', () {
    final Task task = makeTask(dueAt: d(4), reminderAt: d(3));

    test('task is visible from its reminder date through its deadline only', () {
      expect(isTaskScheduledOnDate(task, d(2)), isFalse);
      expect(isTaskScheduledOnDate(task, d(3)), isTrue);
      expect(isTaskScheduledOnDate(task, d(4)), isTrue);
      expect(isTaskScheduledOnDate(task, d(5)), isFalse);
    });

    test('without a reminder, task appears only on its deadline date', () {
      final Task noReminder = makeTask(dueAt: d(4), reminderAt: null);
      expect(isTaskScheduledOnDate(noReminder, d(3)), isFalse);
      expect(isTaskScheduledOnDate(noReminder, d(4)), isTrue);
      expect(isTaskScheduledOnDate(noReminder, d(5)), isFalse);
    });

    test('a reminder without a deadline remains active from its reminder date', () {
      final Task reminderOnly = makeTask(dueAt: null, reminderAt: d(3));
      expect(isTaskScheduledOnDate(reminderOnly, d(2)), isFalse);
      expect(isTaskScheduledOnDate(reminderOnly, d(3)), isTrue);
      expect(isTaskScheduledOnDate(reminderOnly, d(4)), isTrue);
    });

    test('previous incomplete task appears as overdue in Today only', () {
      final Task overdue = makeTask(dueAt: d(4), reminderAt: d(3));
      expect(isTaskOverdueOnDate(overdue, d(5)), isTrue);
      final List<Task> todayList = filterAndSortTasks(
        <Task>[overdue],
        filter: TaskListFilter.today,
        selectedDate: d(5),
        todayOverride: d(5),
      );
      final List<Task> historicalOrFutureDateList = filterAndSortTasks(
        <Task>[overdue],
        filter: TaskListFilter.selectedDate,
        selectedDate: d(5),
        todayOverride: d(5),
      );
      expect(todayList.map((Task t) => t.id), <String>['t1']);
      expect(historicalOrFutureDateList, isEmpty);
    });

    test('same-day deadline never becomes overdue before the next day', () {
      final Task dueToday = makeTask(dueAt: DateTime(2026, 11, 4, 9));
      expect(isTaskOverdueOnDate(dueToday, DateTime(2026, 11, 4, 23, 59)), isFalse);
      expect(isTaskOverdueOnDate(dueToday, DateTime(2026, 11, 5)), isTrue);
    });

    test('paused tasks are not scheduled on a date', () {
      expect(isTaskScheduledOnDate(makeTask(dueAt: d(4), paused: true), d(4)), isFalse);
    });
  });

  test('category filtering and sorting still work without a priority filter', () {
    final List<Task> tasks = <Task>[
      makeTask(id: 'high', title: 'High', dueAt: d(7), priority: TaskPriority.high, category: 'Study'),
      makeTask(id: 'low', title: 'Low', dueAt: d(7), priority: TaskPriority.low, category: 'Study'),
      makeTask(id: 'other-category', title: 'Other', dueAt: d(7), priority: TaskPriority.medium, category: 'Work'),
    ];
    final List<Task> byCategory = filterAndSortTasks(
      tasks,
      filter: TaskListFilter.all,
      selectedDate: d(3),
      category: 'Study',
      sort: TaskSort.priority,
    );
    expect(byCategory.map((Task t) => t.id), <String>['high', 'low']);

    final List<Task> byName = filterAndSortTasks(
      tasks,
      filter: TaskListFilter.all,
      selectedDate: d(3),
      sort: TaskSort.categoryDescending,
    );
    expect(byName.first.category, 'Work');
  });

  test('subtask activity is attributed to its own completion date while parent remains incomplete', () {
    final Task current = makeTask(
      id: 'parent',
      dueAt: null,
      completed: false,
      subtasks: <Subtask>[
        Subtask(id: 's1', title: 'Step 1', createdAt: d(20, month: 10), isCompleted: true, completedAt: d(26)),
        Subtask(id: 's2', title: 'Step 2', createdAt: d(20, month: 10), isCompleted: true, completedAt: d(27)),
        Subtask(id: 's3', title: 'Step 3', createdAt: d(20, month: 10)),
      ],
    );
    final List<TaskActivity> events = <TaskActivity>[
      activity(id: 'created', taskId: 'parent', at: d(20, month: 10), event: 'task_created', snapshot: snapshot(hasSubtasks: true)),
      activity(id: 's1-done', taskId: 'parent', entityId: 's1', entityType: 'subtask', at: d(26), event: 'subtask_completed', snapshot: snapshot(hasSubtasks: true, subtaskDueAt: d(26))),
      activity(id: 's2-done', taskId: 'parent', entityId: 's2', entityType: 'subtask', at: d(27), event: 'subtask_completed', snapshot: snapshot(hasSubtasks: true, subtaskDueAt: d(26))),
    ];
    final TaskAnalyticsSummary report = const TaskAnalyticsEngine().summarize(
      activities: events,
      currentTasks: <Task>[current],
      start: d(26),
      end: d(27),
    );
    expect(report.days[0].subtaskCompletions, 1);
    expect(report.days[1].subtaskCompletions, 1);
    expect(report.days[0].taskCompletions, 0);
    expect(report.days[1].taskCompletions, 0);
    expect(report.days[0].weightedScore, 3);
    expect(report.days[1].lateCompletions, 1);
    expect(report.totalTasks, 1);
    expect(report.completedTasks, 0);
    expect(report.incompleteTasks, 1);
  });

  test('a late task completion is counted on the actual completion date', () {
    final Task task = makeTask(id: 'late-task', dueAt: d(3), completed: true, completedAt: d(5));
    final List<TaskActivity> events = <TaskActivity>[
      activity(id: 'created', taskId: 'late-task', at: d(1, month: 10), event: 'task_created', snapshot: snapshot(dueAt: d(3))),
      activity(id: 'completed', taskId: 'late-task', at: d(5), event: 'task_completed', snapshot: snapshot(completed: true, dueAt: d(3))),
    ];
    final TaskAnalyticsSummary report = const TaskAnalyticsEngine().summarize(
      activities: events,
      currentTasks: <Task>[task],
      start: d(5),
      end: d(5),
    );
    expect(report.days.single.taskCompletions, 1);
    expect(report.days.single.lateCompletions, 1);
    expect(report.days.single.weightedScore, 3);
  });
}
