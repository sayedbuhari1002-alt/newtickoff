# Tazkiyane 0.6.5+28 — partial count/checklist progress in habit analytics

## Changes

- Count-based Build habits now contribute their actual progress fraction to analytics. A count of 4 against a daily goal of 8 contributes 50%.
- Checklist-based Build habits now contribute the checked-item fraction. Four checked items out of five contribute 80%.
- Partial work recorded today is included immediately. A current day with no recorded progress remains pending and is not added to the analytics denominator.
- Historical incomplete count/checklist days contribute their recorded percentage rather than being treated as 0% when some progress was made.
- Added a Partial Progress History panel for count and checklist habits, displaying the amount/items completed and the corresponding percentage.
- The completion-rate trend chart, calendar intensity, period summaries, analytics completion rate, and 30-day score all use the fractional values.

## Unchanged behaviour

- Habit completion status and streaks still require the full count goal or all checklist items.
- Simple tick habits retain binary completion analytics.
- Quit-habit scoring and slip handling remain unchanged.
- No SQLite migration is required; the existing completion records are reused.

## Verification status

- Added unit tests for 50% count progress, 80% checklist progress, partial progress on the current day, historical partial progress, and the rule that partial progress does not complete a streak.
- The Flutter/Dart SDK is not available in the implementation environment. Run `dart format`, `flutter analyze`, `flutter test`, and a GitHub Actions Android build before installing the APK.
