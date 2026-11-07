import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../../core/utils/date_utils.dart';
import '../../domain/models/models.dart';
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
          .map((Task task) => <String, Object>{
                'id': task.id,
                'title': task.title,
                'startDate': task.reminderAt == null && task.dueAt == null
                    ? ''
                    : dateKey(task.reminderAt ?? task.dueAt!),
                'dueDate': task.dueAt == null ? '' : dateKey(task.dueAt!),
                'completedDate': task.completedAt == null
                    ? ''
                    : dateKey(task.completedAt!),
                'isCompleted': task.isCompleted,
                'isPaused': task.isPaused,
              })
          .toList();
      final String snapshot = jsonEncode(<String, Object>{
        'tasks': entries,
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
