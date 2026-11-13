# Tazkiyane next-version changes

## 0.6.7+31 — reusable task template content

- Task templates now preserve notes, photo attachments, audio recordings, and reusable subtasks with difficulty scores.
- Applying a template copies its notes and media attachments to the task and creates new, incomplete subtask records. Subtask deadlines, reminders, and completion state are not copied, avoiding stale dates or completed steps in a new task.
- Task creation and template editing now use the same category picker as habits, including No category and New category. Legacy free-text task categories are retained when editing until the user chooses a managed category.
- Added subtask add/edit/remove controls to the task form and expanded the template editor to manage notes, photo/audio attachments, and subtasks.
- Attachment cleanup now accounts for references held by task templates as well as tasks and journal notes.
- SQLite schema version 12 adds template notes, photo paths, audio paths, and serialized subtasks through an additive migration.

## 0.6.6+30 — progressive-task day baseline, app grace periods, and complete productivity trends

- Today's progressive-task score now uses the difference between the saved progress at the start of the day and the current saved progress. Temporarily moving a task slider up and then returning to yesterday's percentage no longer awards points for that day. Newly created progressive tasks still start their daily baseline at zero.
- Automatic distraction tracking now supports a separate daily free-usage allowance for each selected app. Only the chronological usage beyond that app's daily allowance is charged at the configured category penalty rate. A zero-minute allowance means no free usage.
- The allowance used by each automatic usage session is stored as a snapshot, so editing an app's allowance does not change penalties on already-recorded dates.
- Productivity Analytics now has separate trend graphs for net productivity, points earned before deductions, and penalty points, all using the existing 7-day, 30-day, 90-day, and 12-month range selector.
- SQLite schema version 11 adds per-app allowance settings and usage-session allowance snapshots. The migration is additive and retains existing settings, usage records, and history.

## 0.6.5+28 — partial count/checklist progress in habit analytics

- Habit analytics now calculates Build count-based habit progress proportionally against the configured daily goal. For example, 4 of 8 counts contributes 50% rather than 0% until the target is fully reached.
- Checklist-based Build habits contribute the percentage of checked items. For example, 4 of 5 checked items contributes 80%.
- Partial progress recorded today is included immediately in analytics; an untouched current day remains pending and is excluded from the denominator.
- Historical partial count/checklist records contribute their saved progress instead of being treated as a completely missed day.
- Added a Partial Progress History panel showing the recorded count/checklist amount and percentage for each date.
- Trend charts, calendar intensity, period summaries, overall completion rate, and the 30-day score now use fractional progress.
- Full completion is still required for habit completion status, streaks, and completion-based achievements. Quit habits and simple tick habits retain their existing rules.
- No database schema change is required; existing completion records are read using the new analytics calculation.

## 0.6.4+27 — income and expense analytics

- Expense entry supports income and expense transaction types with separate category lists.
- Added built-in income sources for Salary, Freelance, Business, Investment, Interest, Gift, and Other income.
- Daily Log now shows incoming money, spending, and daily net cash flow.
- Expanded monthly finance analytics with total income, total expenses, net cash flow, income/expense averages, transaction counts, zero-expense days, highest income/spending days, top spending/income categories, income-source and expense-category breakdowns, and daily bar charts.
- SQLite schema version 10 adds transaction types without changing existing transactions; legacy rows remain expenses.

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


## CI test corrections (0.4.2+8)
- Updated archive/delete widget assertions to verify the habit is removed from the visible list without depending on one exact empty-state message.
- Updated the add-habit widget test to navigate through the dedicated Habits tab after saving.
- Added frame pumps between weekday-chip selections so each toggle is rebuilt before the next interaction.
- Habit-linked note creation now uses the shared local-day provider for its calendar date, keeping date filtering consistent with the app's selected day source.


## Navigation corrections (0.4.3+9)
- Archive and delete actions now pop the habit detail route to its originating list/dashboard after the data change, with a safe Habits-route fallback for direct-entry cases.
- Creating a new habit navigates to the dedicated Habits destination so the newly saved habit is immediately visible; editing an existing habit still returns to its previous detail screen.
- These changes address the three remaining widget-test failures from the 0.4.2+8 CI run without changing habit persistence, history, or reminder scheduling.

## Version 0.4.4+10 — navigation recovery
- Route to the Habits destination using a stable GoRouter reference after archive, restore, or delete operations.
- Return from the new-habit form to the screen that opened it, preserving the shell and bottom navigation.
- No database schema change.


## Version 0.4.5+11 — root navigation recovery
- Habit archive/restore and delete now close the full-screen detail route through the root Navigator, returning to the actual caller in the StatefulShellRoute. A hard-coded Habits route is used only as a fallback when the detail page was opened without a previous route.
- Saving a new or edited habit now closes the root-level form route explicitly, restoring the originating shell tab or habit detail screen. A direct-launch fallback remains available when no previous route exists.
- No database schema or habit/task data changes.


## Version 0.4.6+12 — explicit root-route ownership

- Added an explicit root Navigator key to the GoRouter configuration.
- Habit creation and habit detail routes are explicitly assigned to that root Navigator, including habit edit routes inherited from the detail route. This avoids ambiguity when a habit page is opened from a StatefulShellRoute branch.
- Archive, restore, delete, and successful habit-form saves now pop through GoRouter, keeping the router match list synchronized with the visible Navigator stack and restoring the actual caller.
- Preserved the safe direct-entry fallback when there is no previous route.
- No database schema or stored habit/task data changes.


## Version 0.4.7+13 — modal-to-page navigation sequencing

- The Create menu now waits for the bottom sheet to finish closing before opening the selected Habit or Task form.
- Habit Options now returns the selected action from the sheet and performs navigation or persistence only after the options sheet has fully dismissed.
- This prevents a second navigation pop from consuming a modal sheet that is still completing its reverse transition instead of closing the intended page.
- No database schema, saved habit/task data, or reminder behavior changes.


## 0.4.8+14 — Modal/navigation hardening

- Added a shared modal-dismissal wait before pushing or replacing routes after bottom-sheet/dialog actions.
- Habit archive and delete now navigate explicitly to the Habits destination rather than conditionally popping a Navigator whose top route may still be a dismissing modal.
- Saving a new habit explicitly navigates to Habits; saving an edit explicitly returns to that habit's detail route.
- No database schema, database filename, attachment directory, or Android application ID changes.
- Flutter widget tests and Android build must still be run in GitHub Actions; this environment does not contain the Flutter SDK.


## Version 0.4.9+15 — non-blocking reminder work and route-complete modals

- Habit persistence updates the repository and Riverpod state before starting reminder scheduling as a guarded background task. Notification plugin/platform-channel latency no longer delays save, archive, or form navigation. Build-habit completion updates also reschedule reminders in the background after the completion record is published.
- Habit deletion updates local repository/state immediately and cancels its Android reminder asynchronously, so plugin cleanup cannot hold the delete route open.
- Replaced fixed 350 ms modal delays with explicit `ModalBottomSheetRoute.completed` and `DialogRoute.completed` waits. Follow-up navigation now waits for the actual route transition rather than an arbitrary timer.
- Removed the immediate reminder-status snackbar read from the habit form because background scheduling can complete after the form has closed; reminder status remains available from the reminders settings flow.
- No database schema, database filename, attachment directory, or Android application ID changes.
- Flutter tests and Android build must still pass in GitHub Actions before this build is considered verified.


## Version 0.4.10+16 — consistent habit creation date

- New habits now take their `createdAt` date from the shared `todayProvider` clock rather than calling `DateTime.now()` independently. This keeps the habit's lifetime start date aligned with the app's current calendar date and makes date-controlled tests deterministic.
- Added a regression assertion that a newly created habit uses the injected app date and appears in the Habits destination under the Due filter.
- No database schema, database filename, attachment directory, Android application ID, or notification scheduling behavior changes.
