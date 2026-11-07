import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/models/models.dart';

class ReminderPermissionStatus {
  const ReminderPermissionStatus({
    required this.notificationsGranted,
    required this.exactAlarmsGranted,
    required this.timeZoneAvailable,
    this.schedulingIssue,
  });

  final bool notificationsGranted;
  final bool exactAlarmsGranted;
  final bool timeZoneAvailable;
  final String? schedulingIssue;

  bool get ready =>
      notificationsGranted && exactAlarmsGranted && timeZoneAvailable;
}

typedef TaskNotificationActionHandler =
    Future<void> Function(String taskId, String actionId);

/// Local-only reminder scheduling. Task alarms are one-shot exact alarms;
/// habit alarms are weekly recurring exact alarms (one alarm per selected
/// weekday), so they do not stop after a fixed scheduling window.
class TaskReminderService {
  TaskReminderService._();
  static final TaskReminderService instance = TaskReminderService._();

  static const String actionMarkTaskCompleted = 'mark_task_completed';
  static const String actionPostponeTask = 'postpone_task';
  static const String actionOpenTask = 'open_task';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialised = false;
  bool _timeZoneAvailable = false;
  bool _notificationsGranted = true;
  final Set<String> _legacyHabitIdsCleaned = <String>{};
  final Map<String, Future<void>> _scheduleQueues = <String, Future<void>>{};
  String? _lastSchedulingIssue;
  TaskNotificationActionHandler? _taskActionHandler;
  ({String taskId, String actionId})? _pendingAction;

  String? get lastSchedulingIssue => _lastSchedulingIssue;

  void setTaskActionHandler(TaskNotificationActionHandler handler) {
    _taskActionHandler = handler;
    final pending = _pendingAction;
    _pendingAction = null;
    if (pending != null) {
      unawaited(handler(pending.taskId, pending.actionId));
    }
  }

  static int notificationIdFor(String value) {
    int hash = 0x811C9DC5;
    for (final int unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  static String? taskIdFromPayload(String? payload) {
    if (payload == null) return null;
    for (final String prefix in <String>['task-deadline|', 'task-subtask|']) {
      if (payload.startsWith(prefix)) {
        final String id = payload.substring(prefix.length).split('|').first.trim();
        return id.isEmpty ? null : id;
      }
    }
    return null;
  }

  Future<void> initialise() async {
    if (_initialised) return;
    try {
      tz_data.initializeTimeZones();
      await _loadDeviceTimeZone();
      const InitializationSettings settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: _handleNotificationResponse,
      );
      _initialised = true;

      // Actions with showsUserInterface=true launch the app. When Android
      // starts a cold process for such an action, the plugin exposes the
      // response through launch details rather than the regular callback.
      try {
        final NotificationAppLaunchDetails? launchDetails =
            await _plugin.getNotificationAppLaunchDetails();
        if (launchDetails?.didNotificationLaunchApp ?? false) {
          final NotificationResponse? response =
              launchDetails?.notificationResponse;
          if (response != null) _handleNotificationResponse(response);
        }
      } catch (error) {
        debugPrint('Could not read notification launch action: $error');
      }

      final AndroidFlutterLocalNotificationsPlugin? android = _androidPlugin;
      if (android != null) {
        final bool? granted = await android.requestNotificationsPermission();
        _notificationsGranted = granted ?? true;
      }
    } catch (error) {
      _lastSchedulingIssue = 'Tazkiyane could not initialise reminders: $error';
      debugPrint(_lastSchedulingIssue);
    }
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final String? taskId = taskIdFromPayload(response.payload);
    if (taskId == null) return;
    final String action = response.actionId ?? actionOpenTask;
    final TaskNotificationActionHandler? handler = _taskActionHandler;
    if (handler == null) {
      _pendingAction = (taskId: taskId, actionId: action);
      return;
    }
    unawaited(handler(taskId, action));
  }

  AndroidFlutterLocalNotificationsPlugin? get _androidPlugin =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  Future<void> _loadDeviceTimeZone() async {
    try {
      final String name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
      _timeZoneAvailable = true;
    } catch (error) {
      _timeZoneAvailable = false;
      _lastSchedulingIssue =
          'Tazkiyane could not determine the device time zone. Open the app again after checking your device date and time settings.';
      debugPrint('Could not determine device time zone: $error');
    }
  }

  Future<void> refreshTimeZone() async {
    await initialise();
    if (!_initialised) return;
    await _loadDeviceTimeZone();
  }

  Future<ReminderPermissionStatus> checkPermissions() async {
    await initialise();
    bool exactGranted = true;
    final AndroidFlutterLocalNotificationsPlugin? android = _androidPlugin;
    if (android != null) {
      try {
        _notificationsGranted =
            await android.areNotificationsEnabled() ?? _notificationsGranted;
        exactGranted =
            await android.canScheduleExactNotifications() ?? true;
      } catch (error) {
        exactGranted = false;
        debugPrint('Could not check reminder permissions: $error');
      }
    }
    return ReminderPermissionStatus(
      notificationsGranted: _notificationsGranted,
      exactAlarmsGranted: exactGranted,
      timeZoneAvailable: _timeZoneAvailable,
      schedulingIssue: _lastSchedulingIssue,
    );
  }

  Future<ReminderPermissionStatus> requestPermissions() async {
    await initialise();
    final AndroidFlutterLocalNotificationsPlugin? android = _androidPlugin;
    if (android == null) return checkPermissions();

    try {
      final bool? notificationResult =
          await android.requestNotificationsPermission();
      _notificationsGranted = notificationResult ?? true;
    } catch (error) {
      _notificationsGranted = false;
      debugPrint('Could not request notification permission: $error');
    }

    bool exactGranted = true;
    try {
      exactGranted = await android.canScheduleExactNotifications() ?? true;
      if (!exactGranted) {
        await android.requestExactAlarmsPermission();
        exactGranted = await android.canScheduleExactNotifications() ?? true;
      }
    } catch (error) {
      exactGranted = false;
      debugPrint('Could not request exact-alarm permission: $error');
    }

    final ReminderPermissionStatus status = ReminderPermissionStatus(
      notificationsGranted: _notificationsGranted,
      exactAlarmsGranted: exactGranted,
      timeZoneAvailable: _timeZoneAvailable,
    );
    _lastSchedulingIssue = status.ready ? null : _permissionMessage(status);
    return ReminderPermissionStatus(
      notificationsGranted: status.notificationsGranted,
      exactAlarmsGranted: status.exactAlarmsGranted,
      timeZoneAvailable: status.timeZoneAvailable,
      schedulingIssue: _lastSchedulingIssue,
    );
  }

  String _permissionMessage(ReminderPermissionStatus status) {
    if (!status.notificationsGranted) {
      return 'Notifications are disabled for Tazkiyane. Open Android Settings → Apps → Tazkiyane → Notifications and allow notifications.';
    }
    if (!status.exactAlarmsGranted) {
      return 'Exact alarms are not allowed. Open Android Settings → Apps → Special app access → Alarms & reminders → Tazkiyane, then allow alarms and reminders.';
    }
    if (!status.timeZoneAvailable) {
      return 'Tazkiyane could not determine your device time zone, so the reminder was not scheduled.';
    }
    return 'Tazkiyane could not schedule this reminder. Please check Android notification and alarm settings.';
  }

  Future<bool> _canSchedule({required bool requestPermissions}) async {
    await initialise();
    if (!_initialised) {
      _lastSchedulingIssue ??= 'Tazkiyane reminder services are unavailable.';
      return false;
    }
    if (requestPermissions) {
      final ReminderPermissionStatus status = await requestPermissionsFlow();
      if (!status.ready) {
        _lastSchedulingIssue = _permissionMessage(status);
        return false;
      }
    } else {
      final ReminderPermissionStatus status = await checkPermissions();
      if (!status.ready) {
        _lastSchedulingIssue = _permissionMessage(status);
        return false;
      }
    }
    _lastSchedulingIssue = null;
    return true;
  }

  Future<ReminderPermissionStatus> requestPermissionsFlow() =>
      requestPermissions();

  Future<void> _runQueued(String key, Future<void> Function() operation) {
    final Future<void> previous =
        _scheduleQueues[key] ?? Future<void>.value();
    late final Future<void> next;
    next = previous
        .catchError((Object _) {})
        .then((_) => operation());
    _scheduleQueues[key] = next;
    return next.whenComplete(() {
      if (identical(_scheduleQueues[key], next)) {
        _scheduleQueues.remove(key);
      }
    });
  }

  int _taskReminderId(String taskId) =>
      notificationIdFor('task:$taskId');
  int _taskDeadlineId(String taskId) =>
      notificationIdFor('task-deadline:$taskId');
  int _subtaskReminderId(String taskId, String subtaskId) =>
      notificationIdFor('task-subtask:$taskId:$subtaskId');

  /// A date-only deadline means the end of that calendar day. A date with an
  /// explicit time uses that exact local time.
  DateTime? taskDeadlineAlertTime(Task task) {
    final DateTime? dueAt = task.dueAt;
    if (dueAt == null) return null;
    final bool hasExplicitTime = dueAt.hour != 0 || dueAt.minute != 0;
    final DateTime deadline = hasExplicitTime
        ? dueAt
        : DateTime(dueAt.year, dueAt.month, dueAt.day + 1)
            .subtract(const Duration(minutes: 1));
    return deadline.subtract(const Duration(minutes: 30));
  }

  Future<void> scheduleTask(
    Task task, {
    bool requestPermissions = false,
  }) =>
      _runQueued('task:${task.id}', () => _scheduleTaskNow(
            task,
            requestPermissions: requestPermissions,
          ));

  Future<void> _scheduleTaskNow(
    Task task, {
    bool requestPermissions = false,
  }) async {
    await initialise();
    try {
      await _plugin.cancel(_taskReminderId(task.id));
      await _plugin.cancel(_taskDeadlineId(task.id));
      await _cancelSubtaskRemindersForTask(task.id);
      if (!_initialised || task.isCompleted || task.isPaused) {
        _lastSchedulingIssue = null;
        return;
      }

      final DateTime now = DateTime.now();
      final DateTime? manualReminder = task.reminderAt;
      final DateTime? deadlineReminder = taskDeadlineAlertTime(task);
      final List<Subtask> futureSubtasks = task.subtasks.where((Subtask item) =>
        !item.isCompleted && item.reminderAt != null && item.reminderAt!.isAfter(now)).toList();
      final bool hasFutureReminder =
          (manualReminder != null && manualReminder.isAfter(now)) ||
          (deadlineReminder != null && deadlineReminder.isAfter(now)) ||
          futureSubtasks.isNotEmpty;
      if (!hasFutureReminder) {
        _lastSchedulingIssue = null;
        return;
      }
      if (!await _canSchedule(requestPermissions: requestPermissions)) return;

      final bool manualMatchesDeadlineAlert =
          manualReminder != null &&
          deadlineReminder != null &&
          manualReminder.year == deadlineReminder.year &&
          manualReminder.month == deadlineReminder.month &&
          manualReminder.day == deadlineReminder.day &&
          manualReminder.hour == deadlineReminder.hour &&
          manualReminder.minute == deadlineReminder.minute;
      if (manualReminder != null &&
          manualReminder.isAfter(now) &&
          !manualMatchesDeadlineAlert) {
        await _plugin.zonedSchedule(
          _taskReminderId(task.id),
          task.title,
          task.description.isEmpty ? 'Task reminder' : task.description,
          tz.TZDateTime.from(manualReminder, tz.local),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'tickoff_task_reminders',
              'Task reminders',
              channelDescription: 'Reminders for your tasks',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }

      if (deadlineReminder != null && deadlineReminder.isAfter(now)) {
        final List<AndroidNotificationAction> actions = <AndroidNotificationAction>[
          AndroidNotificationAction(
            actionMarkTaskCompleted,
            'Mark as Completed',
            // Use the main app state/repository for every task so subtasks,
            // repeating-task creation, task history, and visible UI stay in sync.
            showsUserInterface: true,
            cancelNotification: true,
          ),
          const AndroidNotificationAction(
            actionPostponeTask,
            'Postpone',
            showsUserInterface: true,
            // Keep the alert available if the user opens the editor and backs
            // out without saving a new deadline. Saving re-schedules it.
            cancelNotification: false,
          ),
        ];
        await _plugin.zonedSchedule(
          _taskDeadlineId(task.id),
          'Task deadline approaching',
          '${task.title} is due in 30 minutes.',
          tz.TZDateTime.from(deadlineReminder, tz.local),
          NotificationDetails(
            android: AndroidNotificationDetails(
              'tickoff_task_deadlines',
              'Task deadline alerts',
              channelDescription: 'Alerts 30 minutes before task deadlines',
              importance: Importance.max,
              priority: Priority.max,
              category: AndroidNotificationCategory.reminder,
              actions: actions,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: 'task-deadline|${task.id}',
        );
      }
      for (final Subtask subtask in futureSubtasks) {
        final DateTime reminderAt = subtask.reminderAt!;
        await _plugin.zonedSchedule(
          _subtaskReminderId(task.id, subtask.id),
          task.title,
          subtask.title,
          tz.TZDateTime.from(reminderAt, tz.local),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'tickoff_subtask_reminders',
              'Subtask reminders',
              channelDescription: 'Independent reminders for task subtasks',
              importance: Importance.high,
              priority: Priority.high,
              category: AndroidNotificationCategory.reminder,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: 'task-subtask|${task.id}|${subtask.id}',
        );
      }
      _lastSchedulingIssue = null;
    } catch (error) {
      _lastSchedulingIssue =
          'Could not schedule reminders for "${task.title}": $error';
      debugPrint(_lastSchedulingIssue);
    }
  }

  Future<void> cancelTask(String taskId) =>
      _runQueued('task:$taskId', () => _cancelTaskNow(taskId));

  Future<void> _cancelSubtaskRemindersForTask(String taskId) async {
    final String prefix = 'task-subtask|$taskId|';
    final List<PendingNotificationRequest> pending = await _plugin.pendingNotificationRequests();
    for (final PendingNotificationRequest request in pending) {
      if (request.payload?.startsWith(prefix) ?? false) {
        await _plugin.cancel(request.id);
      }
    }
  }

  Future<void> _cancelTaskNow(String taskId) async {
    await initialise();
    try {
      await _plugin.cancel(_taskReminderId(taskId));
      await _plugin.cancel(_taskDeadlineId(taskId));
      await _cancelSubtaskRemindersForTask(taskId);
    } catch (error) {
      debugPrint('Could not cancel task reminders: $error');
    }
  }

  int _habitWeekdayId(String habitId, int weekday) =>
      notificationIdFor('habit:$habitId:weekday:$weekday');
  int _checklistReminderId(String habitId, String itemId, int weekday) =>
      notificationIdFor('habit:$habitId:checklist:$itemId:weekday:$weekday');

  Future<void> cancelHabit(String habitId) =>
      _runQueued('habit:$habitId', () => _cancelHabitNow(habitId));

  Future<void> _cancelHabitNow(String habitId) async {
    await initialise();
    try {
      for (int weekday = DateTime.monday;
          weekday <= DateTime.sunday;
          weekday++) {
        await _plugin.cancel(_habitWeekdayId(habitId, weekday));
      }
      final String checklistPrefix = 'habit-checklist|$habitId|';
      final List<PendingNotificationRequest> pending = await _plugin.pendingNotificationRequests();
      for (final PendingNotificationRequest request in pending) {
        if (request.payload?.startsWith(checklistPrefix) ?? false) {
          await _plugin.cancel(request.id);
        }
      }
      if (_legacyHabitIdsCleaned.add(habitId)) {
        final DateTime now = DateTime.now();
        for (int offset = -1; offset <= 21; offset++) {
          final DateTime day = now.add(Duration(days: offset));
          final String legacyKey =
              'habit:$habitId:${day.year}-${day.month}-${day.day}';
          await _plugin.cancel(notificationIdFor(legacyKey));
        }
      }
    } catch (error) {
      debugPrint('Could not cancel habit reminder: $error');
    }
  }

  DateTime _nextWeekdayTime({
    required DateTime now,
    required int weekday,
    required int hour,
    required int minute,
    required bool skipToday,
  }) {
    DateTime candidate = DateTime(now.year, now.month, now.day, hour, minute);
    while (candidate.weekday != weekday ||
        !candidate.isAfter(now) ||
        (skipToday &&
            candidate.year == now.year &&
            candidate.month == now.month &&
            candidate.day == now.day)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  Future<void> scheduleHabit(
    Habit habit, {
    bool requestPermissions = false,
    bool skipToday = false,
  }) =>
      _runQueued('habit:${habit.id}', () => _scheduleHabitNow(
            habit,
            requestPermissions: requestPermissions,
            skipToday: skipToday,
          ));

  Future<void> _scheduleHabitNow(
    Habit habit, {
    bool requestPermissions = false,
    bool skipToday = false,
  }) async {
    await initialise();
    try {
      await _cancelHabitNow(habit.id);
      if (!_initialised || habit.isArchived) {
        _lastSchedulingIssue = null;
        return;
      }

      final List<({String title, Reminder reminder, String? itemId})> reminders =
          <({String title, Reminder reminder, String? itemId})>[];
      if (habit.type == HabitType.build &&
          habit.reminder.enabled &&
          habit.reminder.weekdays.isNotEmpty) {
        reminders.add((title: habit.title, reminder: habit.reminder, itemId: null));
      }
      if (habit.tracking == TrackingMethod.checklist) {
        for (final ChecklistItem item in habit.checklist) {
          if (item.reminder.enabled && item.reminder.weekdays.isNotEmpty) {
            reminders.add((title: item.title, reminder: item.reminder, itemId: item.id));
          }
        }
      }
      if (reminders.isEmpty) {
        _lastSchedulingIssue = null;
        return;
      }
      if (!await _canSchedule(requestPermissions: requestPermissions)) return;

      final DateTime now = DateTime.now();
      for (final entry in reminders) {
        final List<int> weekdays = entry.reminder.weekdays.toList()..sort();
        for (final int weekday in weekdays) {
          if (weekday < DateTime.monday || weekday > DateTime.sunday) continue;
          final DateTime firstOccurrence = _nextWeekdayTime(
            now: now,
            weekday: weekday,
            hour: entry.reminder.hour,
            minute: entry.reminder.minute,
            skipToday: skipToday,
          );
          final bool checklistItem = entry.itemId != null;
          final int id = checklistItem
              ? _checklistReminderId(habit.id, entry.itemId!, weekday)
              : _habitWeekdayId(habit.id, weekday);
          await _plugin.zonedSchedule(
            id,
            habit.title,
            checklistItem ? 'Checklist: ${entry.title}' : 'Time for your habit',
            tz.TZDateTime.from(firstOccurrence, tz.local),
            NotificationDetails(
              android: AndroidNotificationDetails(
                checklistItem ? 'tickoff_checklist_reminders' : 'tickoff_habit_reminders',
                checklistItem ? 'Checklist reminders' : 'Habit reminders',
                channelDescription: checklistItem
                    ? 'Reminders for individual checklist items'
                    : 'Reminders for your build habits',
                importance: checklistItem ? Importance.high : Importance.defaultImportance,
                priority: checklistItem ? Priority.high : Priority.defaultPriority,
              ),
            ),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
            payload: checklistItem ? 'habit-checklist|${habit.id}|${entry.itemId}' : 'habit|${habit.id}',
          );
        }
      }
      _lastSchedulingIssue = null;
    } catch (error) {
      _lastSchedulingIssue =
          'Could not schedule reminders for "${habit.title}": $error';
      debugPrint(_lastSchedulingIssue);
    }
  }

}
