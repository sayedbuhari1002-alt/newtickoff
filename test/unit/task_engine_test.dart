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
  group('Reminder-aware visibility', () {
    final Task task = makeTask(dueAt: d(4), reminderAt: d(3));

    test('reminder begins visibility and overdue tasks stay visible', () {
      expect(isTaskVisibleOnDate(task, d(2)), isFalse);
      expect(isTaskVisibleOnDate(task, d(3)), isTrue);
      expect(isTaskVisibleOnDate(task, d(4)), isTrue);
      expect(isTaskVisibleOnDate(task, d(5)), isTrue);
      expect(isTaskOverdueOnDate(task, d(5)), isTrue);
    });

    test('without reminder, deadline begins visibility', () {
      final Task noReminder = makeTask(dueAt: d(4), reminderAt: null);
      expect(isTaskVisibleOnDate(noReminder, d(3)), isFalse);
      expect(isTaskVisibleOnDate(noReminder, d(4)), isTrue);
      expect(isTaskVisibleOnDate(noReminder, d(5)), isTrue);
    });

    test('completed and paused tasks are not listed as pending', () {
      expect(isTaskVisibleOnDate(makeTask(dueAt: d(1), completed: true), d(5)), isFalse);
      expect(isTaskVisibleOnDate(makeTask(dueAt: d(1), paused: true), d(5)), isFalse);
    });
  });

  test('filters combine priority and category; default order puts overdue first', () {
    final List<Task> tasks = <Task>[
      makeTask(id: 'future-high', title: 'Future', dueAt: d(7), priority: TaskPriority.high, category: 'Study'),
      makeTask(id: 'overdue-high', title: 'Overdue', dueAt: d(1), priority: TaskPriority.high, category: 'Study'),
      makeTask(id: 'overdue-low', title: 'Low', dueAt: d(1), priority: TaskPriority.low, category: 'Study'),
      makeTask(id: 'other-category', title: 'Other', dueAt: d(1), priority: TaskPriority.high, category: 'Work'),
    ];
    final List<Task> filtered = filterAndSortTasks(
      tasks,
      filter: TaskListFilter.all,
      selectedDate: d(3),
      priority: TaskPriority.high,
      category: 'Study',
    );
    expect(filtered.map((Task t) => t.id), <String>['overdue-high', 'future-high']);

    final List<Task> byCategory = filterAndSortTasks(
      tasks,
      filter: TaskListFilter.all,
      selectedDate: d(3),
      sort: TaskSort.categoryDescending,
    );
    expect(byCategory.first.category, 'Work');
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
