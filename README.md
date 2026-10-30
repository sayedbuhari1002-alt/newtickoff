# TickOff — Stage 5 source project

TickOff is an offline-first Flutter application that combines the supplied Stage 3 habit tracker with a local task-management system. Records are stored on-device in SQLite. Ordinary use does not require an account, internet connection, Firebase, cloud sync, ads, subscriptions, or paid services.

> **Verification status:** This archive was assembled and checked for ZIP integrity in an environment without the Flutter/Dart SDK. The source changes, build script, and tests are included, but `flutter pub get`, `dart format`, `flutter analyze`, `flutter test`, and the Android release build could not be run here. Treat compilation and runtime behavior as **unverified** until the GitHub Actions workflow or a local Flutter environment passes. See `BUILD_VERIFICATION.md`.

## Stage 5 overview

- Four primary destinations: Dashboard, Habits, Tasks, and Notes, with a single central Add control offering Add Habit and Add Task.
- Dashboard overview with independent task and habit progress; the full habit list is managed on the Habits tab.
- Full-screen task creation/editing and task details, plus Progress, Edit, Delete, pause/resume, postpone, duplicate, and repeat actions.
- Task priority, category, icon, accent colour, deadline and optional time, reminder, repeat rule, text notes, local photo/audio attachments, and ordered subtasks with independent deadlines.
- Combined task priority/category filters; All, Today, Due Tasks, and selected-date views; default overdue-first ordering and explicit priority/deadline/category sorts.
- Local reminders for tasks and supported habit reminders, with permission requests and failure handling so notification errors do not block saving.
- Persisted task activity snapshots for task/subtask creation, updates, completion/reopening, deadline changes, pause/resume, postponement, duplication, deletion, and subtask edits.
- Task analytics with day/week/month/30-day/90-day/year/custom ranges; task summary metrics, completion bars/trends, comparison charts, weighted score trend, and selected-day historical breakdown.
- SQLite schema migrations through version 3: task tables are added in version 2 and local app preferences in version 3, without resetting existing habit or task data.
- GitHub Actions workflow that runs formatting, analysis, unit/widget tests, database/migration tests, and builds/uploads a release APK; the workflow fails if a required check fails.

See [PATCH_NOTES_SETTINGS_NAVIGATION.md](PATCH_NOTES_SETTINGS_NAVIGATION.md) for the latest navigation and Settings changes and their verification status.

## Stage 3 habit functionality retained

The existing habit models and screens remain part of the project. The source retains Build/Quit habits, Tick/Count/Checklist tracking, schedule handling, completion records, category management, streaks, score calculations, analytics/heatmaps, achievements, habit details, archive/restore, and notes linked to habits. The full habit list now lives on the dedicated **Habits** destination rather than being duplicated on Dashboard. Dashboard shows a compact due-habits overview.

As with the new task implementation, retained habit functionality is not certified by a successful compile/test run in this environment.

## Requirements

- Flutter SDK with Dart compatible with `pubspec.yaml` (`>=3.4.0 <4.0.0`). Use a current stable Flutter release.
- Java 17 for the Android build.
- Linux SQLite development library for the desktop-backed SQLite repository tests (`libsqlite3-dev` on Ubuntu/Debian).

The uploaded project did not include an Android Gradle scaffold. `tool/prepare_android.sh` generates the Android scaffold using the installed Flutter SDK if `android/app` is absent and applies the notification/microphone manifest permissions and local-notification receivers. If you already have a configured `android/` directory in your own checkout, the script leaves that directory intact and only reapplies the manifest changes.

## Open and build in VS Code

From the extracted project root (the folder containing `pubspec.yaml`):

```bash
bash tool/prepare_android.sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --release
```

On a first build, Android Gradle dependencies need to be downloaded. The APK output path is:

```text
build/app/outputs/flutter-apk/app-release.apk
```

For the database repository tests on Ubuntu/Debian, install SQLite first:

```bash
sudo apt-get update && sudo apt-get install -y libsqlite3-dev
```

## Build on GitHub without a local Flutter install

1. Upload this project to your GitHub repository, including the hidden `.github/workflows/build_apk.yml` workflow and `tool/prepare_android.sh`.
2. Push the source to `main`, or open **Actions → Build Android APK → Run workflow**.
3. Review **every** format, analysis, test, scaffold, and APK-build step. A successful APK compilation alone is not a passing run.
4. When the APK build succeeds, download the `tickoff-stage5-release-apk` artifact from that workflow run.

The checked-in workflow does not merge branches or push source changes automatically. Release APK signing uses Flutter/Android's default configuration; it is suitable for local testing, not Play Store release without setting up a production signing key.

## Data and migration notes

- Database file: `tickoff.db` in the app's application-support database location.
- Schema version 1 contains the original categories, habits, completion records, notes, and achievements tables.
- Schema version 2 adds `tasks`, `subtasks`, and `task_activities` plus indexes.
- Schema version 3 adds the `app_settings` key/value table used for theme selection, Dashboard widget visibility, and section ordering. All migrations are additive; they do not reset or rebuild existing habit/task data.
- Task parent rows and subtasks use a SQLite transaction during upsert. Task activity rows intentionally do **not** use a foreign key to `tasks`, allowing historical events to remain after a task is deleted.
- Photos and recordings are copied to an app-private `tickoff_attachments` directory. A task deletion removes an attachment file only when no remaining task or note references it.
- The activity journal only starts recording after this version is installed. Historical task states that were never captured cannot be reconstructed retroactively.

## Tests included

- `test/unit`: existing habit logic, date/model/state/analytics tests plus task visibility, filtering/sorting, subtask completion date attribution, and late-completion tests.
- `test/widget`: habit, notes, Dashboard, and navigation/widget tests updated for the dedicated Habits tab.
- `test/data`: SQLite repository round trips, task/subtask/attachment metadata, retained task activity on deletion, and a version-1-to-version-2 migration test.

Run all tests with `flutter test` after installing Flutter and resolving dependencies.

## Known limitations / items to verify

- No Dart formatter, analyzer, Flutter test runner, Android Gradle build, or device runtime was available when this archive was prepared. The included CI workflow is the intended next verification gate.
- Android scaffold files are generated during the build rather than included in the source archive because the supplied ZIP lacked them.
- Theme settings now persist the original TickOff Dark or Graphite appearance locally. Widgets settings control visibility of the in-app Dashboard sections, and Rearrange persists Dashboard section order. These are in-app Dashboard sections, not Android launcher widgets; native launcher widgets remain outside this implementation. Layout and General remain placeholder destinations.
- Audio capture/playback and local notification behavior depend on Android permission and operating-system behavior and need device testing. If a notification cannot be scheduled, saved task/habit data remains local.
- Habit-linked notes retain the Stage 3 behavior. Photo/audio attachment support in this change is implemented for tasks; existing note attachment controls should be verified separately.
- Weighted task score is intentionally defined as 1 point for Low, 2 for Medium, and 3 for High priority per actual task or subtask completion. A parent auto-completion event is excluded from completion units when child completion events already represent that work.
