# Android usage tracking reconciliation patch

## What changed

- Reworked Android Q+ usage-event processing to track resumed Activities within each package. A package session is closed only when its active Activity count reaches zero.
- `ACTIVITY_STOPPED` is no longer treated as a package-background event. This avoids a delayed `onStop` event for an earlier Activity prematurely ending a newer Activity's session.
- Kept the legacy package-level foreground/background event path for Android versions before Android Q.
- Added an independent `UsageStatsManager.queryUsageStats(INTERVAL_DAILY, ...)` query for the selected local day and selected app packages.
- Added a local SQLite table for Android daily totals and event-reconstructed totals, with an additive schema migration from version 8 to 9.
- Updated the Productivity > Distractions card to show Android daily totals as the displayed usage reference and expose the reconstructed-session comparison per app.
- Kept timestamped sessions as the input to the existing overlap-aware productivity penalty engine. No synthetic whole-day intervals are created from daily totals.

## Important behavior

Android daily totals and event sessions are independent measurements. The Android daily total is used for screen-time display. The reconstructed intervals remain available for scoring because they contain start/end times needed to merge overlapping distractions without double-counting. If the two figures differ, the Productivity screen displays the difference rather than inventing timestamps to make them match.

The app continues to use Android's public UsageStats APIs; it does not access Digital Wellbeing's private app data or database.

## Verification status

- Source-level inspection and consistency checks completed.
- SQLite schema version advanced to 9 with an additive migration.
- Added an SQLite round-trip test for the daily usage total model.
- A Flutter/Dart SDK and Android SDK are not installed in this execution environment, so `flutter analyze`, `flutter test`, and an Android APK build could not be run here. Run the repository's GitHub Actions build before installing the APK.
