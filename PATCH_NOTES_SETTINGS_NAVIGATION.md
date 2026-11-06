# Navigation and Settings Patch

## Task navigation

- Saving a newly created task replaces the form route with Task Details while preserving the screen the user came from in the back stack.
- Saving edits returns to the existing Task Details screen instead of opening a duplicate copy.
- Task Details has a visible back arrow in its normal, loading, and error states.
- The Android system Back action pops to the previous screen when possible; if Task Details has no previous route, it returns to Dashboard.

## Functional Settings

- **Theme:** saves `TickOff Dark` (the unchanged default appearance) or `Graphite` locally.
- **Widgets:** turns the in-app Dashboard sections on/off: Daily Progress, Today's Tasks, Habits Due, and Insights. The Dashboard explains how to restore sections if all are hidden. This setting does not add a native Android launcher widget.
- **Rearrange:** drag-and-drop ordering of those same Dashboard sections, with a reset-to-default action.
- Settings persist in the new SQLite `app_settings` table introduced by schema version 3. The migration is additive and leaves habit/task records intact.

## Verification status

Static relative-import, changed-file delimiter, shell-script syntax, and whitespace checks passed. Flutter/Dart are not installed in the patch preparation environment, so Dart formatting, Flutter analysis, automated tests, APK compilation, and on-device behavior still need to be verified through GitHub Actions and phone testing.
