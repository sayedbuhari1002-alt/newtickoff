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

/// Local-only reminder scheduling. Task alarms are one-shot exact alarms;
/// habit alarms are weekly recurring exact alarms (one alarm per selected
/// weekday), so they do not stop after a fixed 21-day scheduling window.
class TaskReminderService {
  TaskReminderService._();
  static final TaskReminderService instance = TaskReminderService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialised = false;
  bool _timeZoneAvailable = false;
  bool _notificationsGranted = true;
  final Set<String> _legacyHabitIdsCleaned = <String>{};
  String? _lastSchedulingIssue;

  String? get lastSchedulingIssue => _lastSchedulingIssue;

  Future<void> initialise() async {
    if (_initialised) return;
    try {
      tz_data.initializeTimeZones();
      await _loadDeviceTimeZone();
      const InitializationSettings settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _plugin.initialize(settings);
      _initialised = true;

      final AndroidFlutterLocalNotificationsPlugin? android =
          _androidPlugin;
      if (android != null) {
        final bool? granted = await android.requestNotificationsPermission();
        _notificationsGranted = granted ?? true;
      }
    } catch (error) {
      _lastSchedulingIssue = 'TickOff could not initialise reminders: $error';
      debugPrint(_lastSchedulingIssue);
    }
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
      // Never silently fall back to UTC: that would make local reminders fire
      // at the wrong wall-clock time for users outside UTC.
      _timeZoneAvailable = false;
      _lastSchedulingIssue =
          'TickOff could not determine the device time zone. Open the app again after checking your device date and time settings.';
      debugPrint('Could not determine device time zone: $error');
    }
  }

  /// Called when the app returns to the foreground so time-zone changes and
  /// permission changes are reflected before reminders are reconciled.
  Future<void> refreshTimeZone() async {
    await initialise();
    if (!_initialised) return;
    await _loadDeviceTimeZone();
  }

  int _stableId(String value) {
    int hash = 0x811C9DC5;
    for (final int unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
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

  /// Explicit user-initiated permission flow for the Settings screen. On
  /// Android 12+, exact-alarm access opens the system's Alarms & reminders page.
  Future<ReminderPermissionStatus> requestPermissions() async {
    await initialise();
    final AndroidFlutterLocalNotificationsPlugin? android = _androidPlugin;
    if (android == null) {
      return checkPermissions();
    }

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
      return 'Notifications are disabled for TickOff. Open Android Settings → Apps → TickOff → Notifications and allow notifications.';
    }
    if (!status.exactAlarmsGranted) {
      return 'Exact alarms are not allowed. Open Android Settings → Apps → Special app access → Alarms & reminders → TickOff, then allow alarms and reminders.';
    }
    if (!status.timeZoneAvailable) {
      return 'TickOff could not determine your device time zone, so the reminder was not scheduled.';
    }
    return 'TickOff could not schedule this reminder. Please check Android notification and alarm settings.';
  }

  Future<bool> _canSchedule({required bool requestPermissions}) async {
    await initialise();
    if (!_initialised) {
      _lastSchedulingIssue ??= 'TickOff reminder services are unavailable.';
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

  Future<void> scheduleTask(
    Task task, {
    bool requestPermissions = false,
  }) async {
    await initialise();
    final int id = _stableId('task:${task.id}');
    try {
      await _plugin.cancel(id);
      final DateTime? reminder = task.reminderAt;
      if (!_initialised || reminder == null || task.isCompleted || task.isPaused) {
        return;
      }
      if (!reminder.isAfter(DateTime.now())) {
        _lastSchedulingIssue =
            'The reminder time for "${task.title}" has already passed. Choose a future reminder time to receive a notification.';
        return;
      }
      if (!await _canSchedule(requestPermissions: requestPermissions)) {
        return;
      }
      await _plugin.zonedSchedule(
        id,
        task.title,
        task.description.isEmpty ? 'Task reminder' : task.description,
        tz.TZDateTime.from(reminder, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'tickoff_task_reminders',
            'Task reminders',
            channelDescription: 'Reminders for your TickOff tasks',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      _lastSchedulingIssue = null;
    } catch (error) {
      _lastSchedulingIssue =
          'Could not schedule the reminder for "${task.title}": $error';
      debugPrint(_lastSchedulingIssue);
    }
  }

  Future<void> cancelTask(String taskId) async {
    await initialise();
    try {
      await _plugin.cancel(_stableId('task:$taskId'));
    } catch (error) {
      debugPrint('Could not cancel task reminder: $error');
    }
  }

  int _habitWeekdayId(String habitId, int weekday) =>
      _stableId('habit:$habitId:weekday:$weekday');

  Future<void> cancelHabit(String habitId) async {
    await initialise();
    try {
      for (int weekday = DateTime.monday;
          weekday <= DateTime.sunday;
          weekday++) {
        await _plugin.cancel(_habitWeekdayId(habitId, weekday));
      }
      // Cancel the previous release's date-specific 21-day alarm IDs once
      // per habit, preventing duplicate reminders after an app upgrade.
      if (_legacyHabitIdsCleaned.add(habitId)) {
        final DateTime now = DateTime.now();
        for (int offset = -1; offset <= 21; offset++) {
          final DateTime day = now.add(Duration(days: offset));
          final String legacyKey =
              'habit:$habitId:${day.year}-${day.month}-${day.day}';
          await _plugin.cancel(_stableId(legacyKey));
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
    DateTime candidate =
        DateTime(now.year, now.month, now.day, hour, minute);
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
  }) async {
    await initialise();
    final Reminder reminder = habit.reminder;
    try {
      await cancelHabit(habit.id);
      if (!_initialised ||
          !reminder.enabled ||
          habit.isArchived ||
          reminder.weekdays.isEmpty) {
        _lastSchedulingIssue = null;
        return;
      }
      if (!await _canSchedule(requestPermissions: requestPermissions)) {
        return;
      }

      final DateTime now = DateTime.now();
      for (final int weekday in reminder.weekdays.toList()..sort()) {
        if (weekday < DateTime.monday || weekday > DateTime.sunday) continue;
        final DateTime firstOccurrence = _nextWeekdayTime(
          now: now,
          weekday: weekday,
          hour: reminder.hour,
          minute: reminder.minute,
          skipToday: skipToday,
        );
        await _plugin.zonedSchedule(
          _habitWeekdayId(habit.id, weekday),
          habit.title,
          'Time for your habit',
          tz.TZDateTime.from(firstOccurrence, tz.local),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'tickoff_habit_reminders',
              'Habit reminders',
              channelDescription: 'Reminders for your TickOff habits',
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      }
      _lastSchedulingIssue = null;
    } catch (error) {
      _lastSchedulingIssue =
          'Could not schedule reminders for "${habit.title}": $error';
      debugPrint(_lastSchedulingIssue);
    }
  }
}
