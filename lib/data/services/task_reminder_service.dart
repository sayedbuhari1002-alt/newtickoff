import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/models/models.dart';

/// Local reminder scheduling. All failures are contained here so a reminder
/// failure never prevents an offline task or habit from being saved.
class TaskReminderService {
  TaskReminderService._();
  static final TaskReminderService instance = TaskReminderService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialised = false;

  Future<void> initialise() async {
    if (_initialised) return;
    try {
      tz_data.initializeTimeZones();
      try {
        final String name = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(name));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('UTC'));
      }
      const InitializationSettings settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _plugin.initialize(settings);
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      _initialised = true;
    } catch (error) {
      debugPrint('Local notification initialisation unavailable: $error');
    }
  }

  int _stableId(String value) {
    int hash = 0x811C9DC5;
    for (final int unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  Future<void> scheduleTask(Task task) async {
    await initialise();
    final int id = _stableId('task:${task.id}');
    try {
      await _plugin.cancel(id);
      final DateTime? reminder = task.reminderAt;
      if (!_initialised || reminder == null || task.isCompleted || task.isPaused || !reminder.isAfter(DateTime.now())) return;
      await _plugin.zonedSchedule(
        id,
        task.title,
        task.description.isEmpty ? 'Task reminder' : task.description,
        tz.TZDateTime.from(reminder, tz.local),
        const NotificationDetails(android: AndroidNotificationDetails(
          'tickoff_task_reminders', 'Task reminders',
          channelDescription: 'Reminders for your TickOff tasks',
          importance: Importance.high, priority: Priority.high,
        )),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (error) {
      debugPrint('Could not schedule task reminder ${task.id}: $error');
    }
  }

  Future<void> cancelTask(String taskId) async {
    await initialise();
    try { await _plugin.cancel(_stableId('task:$taskId')); } catch (error) { debugPrint('Could not cancel task reminder: $error'); }
  }

  Future<void> cancelHabit(String habitId) async {
    await initialise();
    try {
      for (int i = 0; i < 21; i++) {
        final DateTime day = DateTime.now().add(Duration(days: i));
        await _plugin.cancel(_stableId('habit:$habitId:${day.year}-${day.month}-${day.day}'));
      }
    } catch (error) {
      debugPrint('Could not cancel habit reminder: $error');
    }
  }

  Future<void> scheduleHabit(Habit habit) async {
    await initialise();
    final Reminder reminder = habit.reminder;
    try {
      for (int i = 0; i < 21; i++) {
        final DateTime day = DateTime.now().add(Duration(days: i));
        await _plugin.cancel(_stableId('habit:${habit.id}:${day.year}-${day.month}-${day.day}'));
      }
      if (!_initialised || !reminder.enabled || habit.isArchived) return;
      final DateTime now = DateTime.now();
      for (int i = 0; i < 21; i++) {
        final DateTime day = DateTime(now.year, now.month, now.day + i, reminder.hour, reminder.minute);
        if (!reminder.weekdays.contains(day.weekday) || !day.isAfter(now)) continue;
        final int id = _stableId('habit:${habit.id}:${day.year}-${day.month}-${day.day}');
        await _plugin.zonedSchedule(
          id,
          habit.title,
          'Time for your habit',
          tz.TZDateTime.from(day, tz.local),
          const NotificationDetails(android: AndroidNotificationDetails(
            'tickoff_habit_reminders', 'Habit reminders',
            channelDescription: 'Reminders for your TickOff habits',
            importance: Importance.defaultImportance, priority: Priority.defaultPriority,
          )),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    } catch (error) {
      debugPrint('Could not schedule habit reminder ${habit.id}: $error');
    }
  }
}
