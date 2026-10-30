# TickOff next-version changes

This source update implements the six changes agreed for the next TickOff version.

## 1. Task filtering and overdue rules

- Removed the task priority filter; priority assignment and priority-based sorting remain available.
- A task is scheduled from its reminder date through its deadline, inclusive.
- Without a reminder date, a task with a deadline appears on its deadline date.
- A reminder-only task remains visible from its reminder date until completed or given a deadline, preserving the previous no-deadline behavior.
- A task is not overdue during its deadline calendar day, regardless of the selected time.
- Incomplete tasks from earlier dates are included as overdue only in the current Today filter, not historical or future date filters.

## 2. Task and habit notifications

- Task reminders now use Android exact-while-idle scheduling when notification and exact-alarm permissions are granted.
- Habit reminders use weekly recurring alarms for each selected weekday rather than a finite 21-day queue.
- Notification and exact-alarm permissions are checked, with a Notifications & reminders settings page explaining how to enable access.
- Device time-zone lookup no longer silently falls back to UTC.
- Reminder schedules are refreshed when the app resumes, including after returning from Android settings.
- The Android scaffold script adds `SCHEDULE_EXACT_ALARM` and retains the boot/package-replaced receivers.
- Completing a Build habit suppresses that day's upcoming reminder and keeps the next weekly reminder. Reopening or reducing its count below goal can restore today's reminder if its time has not passed.
- Existing date-specific habit alarm IDs from the previous 21-day scheduler are cancelled during schedule refresh to prevent duplicate notifications after upgrade.

## 3. Quit-habit Daily Progress

- Dashboard Daily Progress uses the habit engine's success rule.
- Build habits contribute when completed.
- Quit habits contribute by default when no slip is recorded; recording a slip reduces progress, and undoing it restores progress.

## 4. Count-based habits

- Added a decrease-by-step control and a reset control beside the existing Add Count control on count-habit cards and the habit detail screen.
- Decrease never takes the count below zero.
- Reset affects only the selected day's count and asks for confirmation.
- Actual counts remain uncapped; progress is capped at 100%.
- The actual count remains visible in the habit detail and is listed in History and Analytics, including values above the goal.

## 5. Dashboard habit tracking

- The Dashboard now provides direct tracking controls for due habits.
- Tick Build habits can be completed or reopened from the Dashboard.
- Checklist habits open their checklist flow; count habits open their tracking detail page.
- Quit habits retain their slip-recording behavior.
- Dashboard progress is synchronized with the saved habit records.

## 6. Tasks page and Build Habit integration

- Date-filtered task lists include tasks during their active reminder-to-deadline window.
- Scheduled Build habits are included at the end of the task list under a `HABIT` display label.
- Quit habits are excluded from the Tasks page.
- Tick Build habits can be completed from Tasks; count/checklist habits open their original habit detail page.
- Habit tracking changes remain attached to the original habit record and its analytics.

## Database compatibility

No database schema migration is required for these changes. Existing tasks, habits, reminders, and completion records continue to use the current local SQLite schema.

## Verification limitation

The Flutter and Dart SDKs were not available in the implementation environment. The project therefore still requires `dart format`, `flutter analyze`, `flutter test`, the SQLite tests, and the Android release build in GitHub Actions before the APK can be treated as verified.


## Notification runtime correction
- Added Gson TypeToken keep rules to the release ProGuard configuration and an R8 compatibility-mode workaround (`android.enableR8.fullMode=false`) for the notification plugin reflection path. The Android generation script verifies both settings are applied. The CI workflow now withholds the APK artifact if that patch step fails.
