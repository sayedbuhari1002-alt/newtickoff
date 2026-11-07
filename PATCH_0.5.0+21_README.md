# Tazkiyane v0.5.0+21 — Feature release patch

This release adds the approved Tazkiyane Identity launcher icon, three selectable colour themes, a native Android home-screen task widget, a Notes Library with Daily / General / Monthly / Yearly categories, full-screen photo and video attachment viewers, independent checklist-habit reminders, and independent task-subtask reminders.

## Install through GitHub Actions
1. Extract this patch ZIP into the existing `newtickoff` repository root and overwrite the included files.
2. Review the changed files, then commit and push to `main`.
3. Wait for every GitHub Actions check, APK build, permanent-signature verification, and artifact upload to succeed.
4. Download the artifact `tazkiyane-stable-release-apk` and install the APK over v0.4.13+20. Do not uninstall the current app; the database migration is additive and designed to preserve existing records.

## Release identity
- Application ID: `dev.tickoffreplacement.tickoff_replacement`
- Version: `0.5.0+21`
- SQLite schema: 6 (additive migration from schema 5)
- Signing: continue using the existing four GitHub Secrets and the permanent keystore. Never regenerate the key or add it to Git.

## Android home-screen widget
Long-press an empty home-screen area, open Widgets, and drag **Tazkiyane Tasks** onto the screen. It displays tasks scheduled for today, overdue tasks, and tasks completed today; tapping the widget opens the app. Its snapshot is refreshed whenever app data changes and by Android's widget update lifecycle.

## Notes Library
Open Notes → tap the Library icon. Create a Daily, General, Monthly, or Yearly note. Existing Daily Log entries remain Daily notes. Attachments stay in the app's private storage. Tap a photo or video preview to open its full-screen viewer; audio cards can be played and paused again.

## Subtask reminders
Each task subtask can now have its own reminder date and time. Checklist habit item reminders are scheduled independently of the parent habit reminder. Android notification and exact-alarm permissions must be allowed for reminders to appear.

## Validation
This patch was statically inspected and includes updated unit/database tests. The container used to prepare it does not have Flutter/Dart installed, so a local Flutter build was not run. GitHub Actions remains the authoritative formatter, analyzer, test, APK build and signature verification environment.
