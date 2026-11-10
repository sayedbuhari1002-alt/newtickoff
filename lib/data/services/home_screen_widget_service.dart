import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../../core/utils/date_utils.dart';
import '../../domain/models/models.dart';
import '../../domain/logic/productivity_engine.dart';
import '../../state/app_data.dart';

/// Publishes task schedule data for the native Android home-screen widget.
/// The native provider filters this saved list against today's date, so its
/// contents roll over even when Flutter is not running.
class HomeScreenWidgetService {
  HomeScreenWidgetService._();
  static const String providerName = 'TazkiyaneTasksWidgetProvider';
  static String? _lastSnapshot;

  static Future<void> update(AppData data) async {
    try {
      final List<Map<String, Object>> entries = data.tasks
          .where((Task task) => task.parentTaskId != null || !data.isGroupTask(task))
          .map((Task task) {
            return <String, Object>{
              'id': task.id,
              'title': task.title,
              'scheduledDate': task.scheduledDate == null ? '' : dateKey(task.scheduledDate!),
              'reminderDate': task.reminderAt == null ? '' : dateKey(task.reminderAt!),
              'dueDate': task.dueAt == null ? '' : dateKey(task.dueAt!),
              'completedDate': task.completedAt == null
                  ? ''
                  : dateKey(task.completedAt!),
              'isCompleted': task.isCompleted,
              'isPaused': task.isPaused,
            };
          })
          .toList();
      final DateTime today = DateTime.now();
      final ProductivityEngine engine = const ProductivityEngine();
      final ProductivityDayScore score = engine.calculateDay(
        date: today,
        target: data.targetForDate(today),
        habits: data.habits,
        completions: data.completions,
        tasks: data.tasks,
        activities: data.taskActivities,
        progressEvents: data.taskProgressEvents,
        assignments: const <Assignment>[],
        distractionCategories: data.distractionCategories,
        distractionLogs: data.distractionLogs,
        appUsageRecords: data.appUsageRecords,
      );
      final List<RecommendedTask> recommendations = engine.recommendTasks(
        tasks: data.tasks,
        date: today,
        remainingTarget: (score.target - score.netScore).clamp(0, double.infinity).toDouble(),
      );
      final Map<String, Task> suggestionTasks = <String, Task>{};
      for (final RecommendedTask recommendation in recommendations) {
        suggestionTasks[recommendation.task.id] = recommendation.task;
      }
      final String snapshot = jsonEncode(<String, Object>{
        'tasks': entries,
        'recommendations': suggestionTasks.values.take(2).map((Task task) => <String, String>{
          'id': task.id,
          'title': task.title,
        }).toList(),
      });
      if (snapshot == _lastSnapshot) return;
      _lastSnapshot = snapshot;
      await HomeWidget.saveWidgetData<String>('tazkiyane_tasks_snapshot', snapshot);
      await HomeWidget.updateWidget(name: providerName);
    } catch (error, stackTrace) {
      debugPrint('Could not refresh Tazkiyane home-screen widget: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
