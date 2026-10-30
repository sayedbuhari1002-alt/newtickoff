# CI build fixes

This repair follows the GitHub Actions log provided on 2026-10-31.

- Fixed the out-of-scope `today` reference in Dashboard task cards by passing
  the current date into the task-section builder.
- Removed an illegal default value from the required positional
  `_statusLabel` parameter.
- Imported the existing `dateKey` helper in the Dashboard widget tests.

The uploaded log showed 16/16 SQLite tests passing. It showed 113 app tests
passing and six widget-test files failing to load because of the shared Dart
compilation errors above. The APK build failed for the same two application
compile errors.

These source corrections have not been verified by a fresh Flutter/Dart run
in this environment. Re-run the GitHub Actions workflow before installing or
releasing the APK.
