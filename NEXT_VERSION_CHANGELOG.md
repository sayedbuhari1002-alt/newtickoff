# Tazkiyane 0.4.0 — next-version changes

This release carries forward the previously agreed habit/task improvements and adds deadline actions, completion-aware habit reminders, a date-based journal, expense tracking, and Tazkiyane branding.

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

## Compatibility with the previous release

The existing tasks, habits, reminders, completions, settings, and attachment paths are retained. New journal and expense storage is added through the version-4 SQLite migration described below.

## Verification limitation

The Flutter and Dart SDKs were not available in the implementation environment. The project therefore still requires `dart format`, `flutter analyze`, `flutter test`, the SQLite tests, and the Android release build in GitHub Actions before the APK can be treated as verified.


## Notification runtime correction
- Added Gson TypeToken keep rules to the release ProGuard configuration and an R8 compatibility-mode workaround (`android.enableR8.fullMode=false`) for the notification plugin reflection path. The Android generation script verifies both settings are applied. The CI workflow now withholds the APK artifact if that patch step fails.


## 7. Automatic task deadline alerts

- Every active task with a deadline receives one local notification 30 minutes before its deadline, provided the task is still incomplete.
- The notification includes `Mark as Completed` and `Postpone` actions. Selecting either action opens Tazkiyane; Mark as Completed is applied through the normal app state/repository path. Outstanding subtasks are completed through their existing workflow, preserving task activity history and repeating-task creation.
- Postpone opens the task editor. Saving a changed deadline cancels and replaces the previous automatic deadline alert. If the editor is closed without saving, the delivered notification is not dismissed by the action itself.
- Completing or pausing a task, removing its deadline, or changing its deadline reconciles the scheduled alert. Existing manually configured task reminders remain separate and continue to work. A manual reminder at the exact same minute as the automatic alert is coalesced into the action-enabled deadline alert to avoid a duplicate.
- No repeated daily overdue alerts are scheduled. A date-only deadline is treated as 23:59 local time, so its advance alert is scheduled at 23:29. A deadline with a time uses that exact local time minus 30 minutes.

## 8. Build-habit reminder suppression

- Build habit reminders are suppressed for the current day when the habit is already complete at its configured reminder time.
- Count-based Build habits are complete for this rule when their saved count reaches or exceeds the daily goal.
- Reopening a Build habit or reducing a count below its goal before the reminder time reschedules today's reminder when the selected weekday applies.
- Quit habits are not affected by this rule. Habits without reminders remain unchanged.

## 9. Daily journal and notes

- The Notes destination now uses the same horizontally scrolling date strip as the Dashboard rather than a calendar grid.
- General notes are stored as date-based journal entries. Multiple entries can be created, edited, and deleted for one date.
- Existing habit-linked notes remain accessible in a separate Habit Notes section.
- During the version-4 migration, existing standalone notes are assigned their original creation date; habit-linked notes remain linked to their habit.

## 10. Expense tracking and analytics

- Added local expense records with add, edit, and delete operations, date, amount, category, optional description, and payment method.
- Amounts are stored as integer paise to avoid floating-point rounding in expense totals.
- The database seeds Food, Transportation, Shopping, Education, Entertainment, Healthcare, Bills, Personal, and Others categories. Users can add custom categories; deleting a custom category leaves its expenses uncategorised rather than deleting those expenses.
- Daily expense totals show ₹0 when no entries exist. Monthly analytics include total expenses, average per elapsed day in the current month (or all calendar days in a completed month, including zero-spending days), highest-spending day, transaction count, zero-expense days, category breakdown, and daily spending bars.

## 11. Tazkiyane branding

- Updated the Android launcher label and in-app title/settings copy to Tazkiyane.
- Kept the existing Android application ID, SQLite database filename, and attachment directory unchanged so the new APK can update the installed app without intentionally resetting local data.

## Database compatibility

- SQLite schema version 4 adds `notes.log_date`, `expense_categories`, and `expenses` plus indexes. The migration is additive and does not recreate the existing habits, completions, tasks, task activities, notes, or settings tables.
- Existing standalone notes are backfilled from their stored creation timestamps. Existing habit-linked notes preserve their habit relationship.

## Verification status

- Added SQLite migration/repository tests for legacy journal-date backfill, seeded expense categories, expense insert/update/delete, and custom-category deletion behavior.
- Added model/state tests for paise amounts, expense validation, and expense state changes, plus tests for the 30-minute deadline calculation.
- The Flutter/Dart SDK is not installed in this preparation environment. `dart format`, `flutter analyze`, `flutter test`, and the release APK build remain unrun here. GitHub Actions must pass before installing this APK as an update, and the notification actions must be tested on the phone.


## CI test corrections (0.4.1+7)
- Replaced the decorated SectionCard container with a Material surface so nested ListTiles render their ink and background correctly.
- Initialised Notes and Tasks selected dates from the shared todayProvider, keeping screens and date-keyed records aligned.
- Published a saved habit to application state before awaiting the platform reminder scheduler, so a slow/failed notification call cannot leave the UI stale after the database update.
- Returned to the Habits destination after archiving or deleting a habit from its detail screen.
- Updated widget tests to follow the current create menu, current Dashboard progress cards, and current Habits date-heading format.
