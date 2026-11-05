# Tazkiyane — offline-first personal productivity app

Tazkiyane combines habit tracking, task management, a date-based daily journal, and personal expense tracking in one offline-first Flutter application. User data is stored on-device in SQLite. The app does not require an account, cloud synchronisation, Firebase, ads, or subscriptions for ordinary use.

> **Verification status:** The source archive has been updated and checked for basic script and ZIP integrity. The Flutter/Dart SDK is not installed in the preparation environment, so `flutter pub get`, `dart format`, `flutter analyze`, `flutter test`, and the Android release build have not been run here. Do not treat the APK as verified until the GitHub Actions workflow passes and the generated APK is tested on the phone.

## Main modules

- **Dashboard:** Daily habit/task overview, progress, and scrolling date navigation.
- **Habits:** Build, Quit, tick, checklist, and count-based habits; scheduling, completion history, streaks, heatmaps, analytics, categories, notes, and reminders.
- **Tasks:** Task details, priorities, categories, deadlines, optional manual reminders, repeat rules, subtasks, local attachments, pause/resume, postpone, and task analytics.
- **Journal & Notes:** A horizontally scrolling date selector matching the Dashboard; multiple general journal entries per date; existing habit-linked notes remain separately accessible.
- **Expenses:** Daily expense entry, edit/delete, built-in and custom categories, daily totals, and monthly spending analytics.
- **Notifications:** Exact local task reminders, 30-minute pre-deadline alerts with action buttons, and recurring Build-habit reminders that are suppressed when the habit is already complete for the day.

## Daily journal and expenses

The Notes destination is not a month-grid calendar. Journal and daily expense views reuse the Dashboard's horizontal date strip. General notes are associated with a calendar date; existing habit-linked notes remain linked to their habit. Expense amounts are persisted as integer paise. A day with no expense rows has a computed total of ₹0 and is included as a zero-spending day in the monthly averages and charts. The current month only counts days through today, so future dates do not reduce the average.

Monthly expense analytics display total expenses, average per elapsed day in the current month (or per calendar day for completed months), highest-spending day, transaction count, zero-expense days, category totals, and a daily bar chart. Built-in categories are Food, Transportation, Shopping, Education, Entertainment, Healthcare, Bills, Personal, and Others.

## Automatic task deadline notification

An active task with a deadline is scheduled to show one local alert 30 minutes before the deadline if it is still incomplete. The Android notification has `Mark as Completed` and `Postpone` actions. Both actions open the app: Mark as Completed uses the normal task state flow (including subtasks and repeating-task rules), while Postpone opens the task editor; saving a new deadline replaces the previous deadline alert. There are no repeated daily overdue notifications. A date-only deadline is treated as 23:59 local time, so the alert is planned for 23:29.

## Database compatibility

- Database file remains `tickoff.db` so the existing installation retains its database location.
- Schema version 1 contains the original categories, habits, completion records, notes, and achievements.
- Schema version 2 adds tasks, subtasks, and task activity history.
- Schema version 3 adds local app settings.
- Schema version 4 adds `notes.log_date`, `expense_categories`, and `expenses` with indexes. Existing standalone notes are assigned the date of their original creation; habit-linked notes remain linked to their habits.
- Existing Android application ID and attachment directory remain unchanged for update compatibility.

## Build on GitHub Actions

The repository workflow builds on the current stable Flutter channel with Java 17. It runs formatting, static analysis, unit/widget tests, SQLite repository/migration tests, and a release APK build. It uploads an APK artifact only when the Android scaffold, dependency resolution, formatting, analysis, unit/widget tests, SQLite tests, and release build all succeed.

After copying the source changes into the existing repository branch, push that branch and review every Actions step. Download the `tazkiyane-next-version-release-apk` artifact only after all required checks pass. Keep the existing working APK installed until the replacement has been tested. Do not merge into `main` until the new release is accepted.

## Local build commands

From the project root:

```bash
bash tool/prepare_android.sh
flutter pub get
dart format lib test
flutter analyze --no-fatal-infos
flutter test test/unit test/widget
flutter test test/data
flutter build apk --release
```

On Ubuntu/Debian, SQLite development headers may be needed for the FFI repository tests:

```bash
sudo apt-get update && sudo apt-get install -y libsqlite3-dev
```

## Important implementation notes

- The app label is `Tazkiyane`; the internal Flutter package name, Android application ID, database filename, and attachment directory are intentionally retained.
- Task and habit reminders remain local. Android exact-alarm permission, notification permission, timezone handling, reboot restoration, and OEM battery settings affect delivery.
- A date-only task deadline is defined as the end of that date for the advance-notification calculation.
- The source archive excludes `.git` so it can be copied into the existing working repository without replacing Git history.
