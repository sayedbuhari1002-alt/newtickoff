# Tazkiyane 0.4.12+19 — Obsidian Graphite + Violet theme

## Scope

This is a theme-only update based on the supplied `tazkiyane-05-11.zip` source.
It changes the shared colour palette and Material theme while keeping existing
screen layout, navigation, app logic, data models, and task/habit workflows intact.

## Visual changes

- Background: `#17171C`
- Card surface: `#22212A`
- Elevated surface: `#2B2935`
- Primary accent: `#A78BFA` (soft violet)
- Secondary accent: `#8B9BB4` (muted slate)
- Primary text: `#EEEAF5`
- Secondary text: `#A6A1B2`
- Borders: `#393642`
- Shared text fields, dialogs, sheets, selection states and progress indicators use the same palette.
- The bottom create action and date-strip selected state now use the violet accent.
- Existing user-selected habit/task/expense-category colours are not migrated or overwritten. New habit/task defaults and newly created expense-category defaults use violet; existing saved colours remain unchanged.

## Applying this patch

Extract the ZIP into the project root and overwrite the matching files. The ZIP
contains only changed files plus this README.

Then run:

```powershell
flutter pub get
dart format lib test/unit/app_theme_test.dart
flutter analyze --no-fatal-infos
flutter test test/unit/app_theme_test.dart
flutter test
flutter build apk --release
```

The version is advanced to `0.4.12+19` so Android recognises this as a newer build
than the preceding `0.4.11+18` compile-fix release.

## Verification status

The patch is source-reviewed and its ZIP structure can be checked here. Flutter
and Dart SDKs are not installed in this environment, so formatter, analyzer,
tests, and APK compilation must be run through the user's Flutter installation
or GitHub Actions.
