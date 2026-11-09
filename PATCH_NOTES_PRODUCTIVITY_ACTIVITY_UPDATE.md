# Tazkiyane productivity and navigation update

## Productivity
- Removed the Recommended Tasks and Assignments cards from the Productivity screen.
- Productivity scoring on this screen and its history strip no longer includes legacy assignment points. Existing local assignment data is retained for compatibility; no assignment UI is exposed in Productivity.
- Distraction categories can now select apps by their device-visible app names instead of asking users to enter Android package identifiers.
- Automatic usage history displays app labels instead of package identifiers.
- Android package visibility is limited to apps with launcher activities; no broad `QUERY_ALL_PACKAGES` permission is added.

## Navigation and task creation
- Replaced the middle Create button in the bottom navigation with an Activity destination.
- Added an Activity timeline for task and subtask changes, progress updates, scheduling, and completion events.
- Moved task/habit creation to a Create floating action button on the Home dashboard.

## Android home-screen widget
- Added up to two suggested next tasks, prioritised by the productivity engine and supplemented by open tasks planned for today.
- Increased the widget's minimum height and added space for the suggestions.

## Verification
- Android preparation script syntax checked with `bash -n`.
- Android preparation script exercised against a temporary generated-manifest/Gradle scaffold; launcher-app visibility query and Tazkiyane label verified.
- Widget Android XML resources parsed successfully.
- Source-level checks confirmed the Productivity UI no longer contains the removed Recommended Tasks or Assignments sections and the five navigation destinations match the router branches.
- Flutter/Dart compilation and test suites were not run in this environment because the Flutter and Dart SDK executables are unavailable. GitHub Actions should be used for final build verification.
