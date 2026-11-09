# GitHub Actions widget-test fix

The latest workflow passed static analysis, database tests, APK compilation, signing, and signature verification. The application/widget test job failed because `test/widget/habit_form_test.dart` still searched for the old `Icons.add` navigation icon.

The current dashboard uses an extended Create floating action button with `Icons.add_rounded`. The `openNewForm` test helper now taps that actual icon before selecting **Add Habit**. This updates the test to follow the current UI; it does not change application behavior.

The nine reported habit-form tests all failed at the shared `openNewForm` helper, so one finder correction addresses their common failure point.
