# Tazkiyane Productivity Update — v0.6.0+23

This patch adds the Productivity score system to the working v0.5.1+22 project. It is designed as an additive update: it keeps the existing SQLite database, habits, tasks, notes and attachments, expenses, reminders, analytics, task templates, and Android signing identity.

## Included

- A Productivity destination in Settings, with date selection, the daily score and target, a score breakdown, recent history, assignment management, distractions, and task recommendations.
- A configurable default daily target (initially 15 points) whose changes take effect from tomorrow. Individual dates can have their own target override; earlier effective targets remain in the target history.
- Achievement points for Build Habits, assignments, standard tasks, subtasks, and newly reached progressive-task progress. Partial count/checklist habit completion is proportional. Quit Habits award no achievement points and incur a penalty only when a slip is explicitly recorded.
- Decimal scoring values. Habit scoring rules and point values are captured with a completion record; task/subtask and progressive-task values are captured in activity/progress history; assignment completion points and distraction severities are also snapshotted.
- Manual distraction categories and time logs. Severity is configured in points per hour. Overlapping manual and automatic intervals are merged and charged once at the highest active severity.
- Android Usage Access integration through `UsageStatsManager`. Selected package names can be attached to a category. Usage is refreshed when the Productivity screen is opened, when the app resumes, and through the Refresh action. A foreground session is capped at the current time for the current day. Manual logging remains available when Usage Access is disabled or unsupported.
- Task recommendations weighted by priority, deadline urgency, difficulty contribution to the remaining target, and whether the task has a schedule date. Completed, paused, group-parent, future-deadline, and already scheduled tasks are excluded. A suggested task is only scheduled; it earns no points until the task is completed or progress is recorded.

## Android Usage Access setup

1. Open **Settings → Productivity**.
2. Create or edit a distraction category and enable **Track app usage automatically**.
3. Enter one Android package name per line for each app to associate with that category (for example, Instagram: `com.instagram.android`; Facebook: `com.facebook.katana`; YouTube: `com.google.android.youtube`).
4. Tap **Refresh**. Android opens the special Usage Access settings screen. Enable access for Tazkiyane, return to the app, and refresh again if needed.

Usage Access is a special Android permission; the app cannot silently grant it. The integration queries local Android usage events and stores the resulting intervals in the app's SQLite database. It does not upload app-usage data. Automatic refresh is performed while the app is in use/resumed; this patch does not add a continuously running background service. If access is not enabled, the manual distraction log is the fallback.

Avoid assigning the same package name to more than one category. The app validates this so each package has one unambiguous severity value.

## Scoring rules

- `Achievement points` are summed from the eligible completion events for the selected calendar date.
- `Penalty points` are summed from explicit Quit Habit slips and distraction durations.
- `Raw net score = achievements - penalties`; the displayed net score is clamped to zero. The earned and penalty totals remain visible separately.
- Build Habit points are proportional to the recorded completion: tick is binary; count uses actual count divided by the saved daily goal; checklist uses checked items divided by the saved checklist size. A count-based habit can represent time by using a unit such as minutes.
- A progressive task only earns points for progress that reaches a new high-water percentage. Reducing progress does not claw back previously earned points, and later returning to an already reached percentage does not award it again.
- Group parents are organisational only. Direct child tasks and subtasks can earn their own points; the parent does not receive an additional award.

## Database and compatibility

- SQLite schema version advances from 7 to 8 using an additive migration.
- New productivity tables store assignments, daily target history/overrides, distraction categories, manual logs, and automatic app-usage intervals.
- Existing completion rows are given best-effort snapshots from the current habit setup during migration; future completion records preserve the rule configuration used for that date.
- Existing task and habit data is not intentionally cleared or replaced.
- Android package ID remains `dev.tickoffreplacement.tickoff_replacement`.
- The patch does not include an Android keystore or signing credentials. The existing GitHub Actions secrets and permanent release certificate must remain unchanged.

## Apply the patch

1. Keep the currently installed app and the existing project folder as they are. Make a backup of the project ZIP or folder before overwriting files.
2. Extract this patch ZIP to a temporary folder.
3. Copy the extracted files and folders into the root of the existing repository, allowing the new files to be added and existing files to be overwritten. Do not replace or delete `.git`, `android` generated files, keystore files, or GitHub secrets.
4. Review and commit the patch from PowerShell:

   ```powershell
   git add -A
   git diff --cached --stat
   git commit -m "Add Productivity score system v0.6.0+23"
   git push origin main
   ```

5. Let the repository's GitHub Actions workflow run. It formats the Dart source, analyses the project, runs app and SQLite migration tests, generates the Android scaffold, builds the release APK, verifies the permanent signing certificate, and uploads the APK artifact only when every required check succeeds.
6. Do not uninstall the current app or clear its data. Install the new APK as an in-place update only after the workflow succeeds, the APK artifact is present, and its certificate fingerprint matches the existing permanent certificate.

## Validation status

This patch is prepared against the uploaded v0.5.1+22 source. It has not yet been built with Flutter in this environment. GitHub Actions is the release validation step; use its full workflow log to address any analyzer, test, migration, Android build, or signing errors before installing the APK.
