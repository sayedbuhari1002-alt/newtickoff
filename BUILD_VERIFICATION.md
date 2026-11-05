# Build verification and CI repair report

Date: 2026-10-31

## Review of the uploaded GitHub Actions log

The uploaded workflow ran on branch `fix/navigation-settings`, commit
`194c71f414dc14357e459402f9b3df18d3e0d8f0`, using Flutter 3.47.9 and Dart
3.13.7.

The log reports:

- Dependency resolution succeeded.
- SQLite repository and migration tests passed: 16/16.
- Unit/widget test runner reported 113 passed and 6 test files unable to load.
- Android release APK compilation failed at Dart compilation.
- The six test-file load failures were cascades from the same source compilation
  errors, not six independently reported runtime assertions.

## Source corrections applied after reviewing the log

1. `lib/features/dashboard/dashboard_screen.dart`
   - Passed the `todayProvider` date into `_tasksSection`.
   - Uses `isSameDay(selected, today)` for the overdue-display flag, avoiding
     an out-of-scope variable and comparing calendar dates rather than exact
     timestamps.

2. `lib/features/habit_detail/habit_detail_screen.dart`
   - Removed the invalid default value from the required positional
     `isToday` argument of `_statusLabel`. The call site already supplies it.

3. `test/widget/dashboard_test.dart`
   - Added the direct import for `dateKey` from
     `core/utils/date_utils.dart`.

## Verification status of this repaired archive

The three reported source issues have been corrected by inspection. The
Flutter/Dart SDK is not installed in this preparation environment, so this
archive has **not** been re-run through `dart format`, `flutter analyze`,
`flutter test`, or an Android release build after these corrections.

Run these checks from the extracted project root in GitHub Actions:

```bash
flutter pub get
dart format lib test
flutter analyze --no-fatal-infos
flutter test test/unit test/widget
flutter test test/data
flutter build apk --release
```

Do not treat the APK as approved until the workflow passes and the resulting
APK has been installed and tested on the phone. Keep the existing working APK
and user data backed up until the replacement is accepted.

## Verification after the 0.4.4+10 navigation run

The next uploaded GitHub Actions log reported 162 app tests passed and 3 failed:

- Archiving a habit updated the data but left the full-screen habit detail visible.
- Deleting a habit updated the data but left the full-screen habit detail visible.
- Saving a new habit did not restore the shell/bottom-navigation route expected by the test.

The database suite passed 19/19, and the Android release APK compiled successfully. The workflow remained failed because the app/widget test step failed, so no artifact was approved for installation.

## Source correction in 0.4.5+11

- Archive/restore and delete now pop the root Navigator route for the habit detail page, returning to the actual shell destination that opened it. A GoRouter fallback is used only if there is no prior route.
- Saving a new or edited habit explicitly pops the root-level form route, restoring the originating shell or detail page. A direct-launch fallback remains available.
- The three affected widget tests now explicitly assert that the shell's Habits destination is visible after the route is closed.

The preparation environment still has no Flutter/Dart SDK. This source correction has not been compiled or run through Flutter tests here; GitHub Actions must verify it.


## Navigation follow-up — 0.4.6+12

The 0.4.5+11 GitHub Actions run still showed three widget failures: the habit detail route remained visible after archive and delete, and the new-habit form did not restore the shell after saving. The release APK compiled, but the workflow did not approve an artifact because the widget test step failed.

The 0.4.6+12 source changes make the route ownership explicit by assigning the habit creation and detail routes to a dedicated root Navigator key. The nested edit route inherits the detail route's root Navigator. Navigation actions now call `GoRouter.pop()` instead of directly mutating a Navigator or using a root-level imperative pop, so the router's route-match state is updated together with the visible stack.

Verification performed in the preparation environment:
- `git diff --check`
- `bash -n tool/prepare_android.sh`
- YAML parsing for `pubspec.yaml` and `.github/workflows/build_apk.yml`
- Source assertions for the root Navigator key, explicit route ownership, and GoRouter-based pops
- ZIP integrity check after packaging

The Flutter/Dart SDK is not installed in this preparation environment. `dart format`, `flutter analyze`, `flutter test`, and an Android release build have **not** been run on 0.4.6+12. GitHub Actions must verify this archive before installation.


## 0.4.7+13 navigation investigation

The 0.4.6+12 GitHub Actions run checked commit `149d5e2` but reproduced the same three widget failures. Inspection showed that the Create menu and Habit Options handlers initiated a second navigation action immediately after calling `Navigator.pop` on their modal sheet. Since the modal and page routes share the root Navigator, the page pop could race the sheet's reverse transition. In 0.4.7+13, both flows await the modal result before pushing or popping page routes. Flutter tests and APK compilation must still be confirmed by the next GitHub Actions run.
