# Tazkiyane v0.6.7+34 — Historical Productivity Scoring Fix

## Corrections

- When a habit's scoring settings are edited during the current date, refresh that date's existing completion snapshot. This ensures the points shown live today are the same points shown after the date becomes historical.
- On application launch, reconcile only the open date's existing habit completion snapshots against the current habit configuration. This repairs stale snapshots for the current date after upgrading from an earlier build without rewriting previous dates.
- Historical progressive-task scoring now awards only the positive net progress achieved during that specific date, using the earliest progress event as the day's starting percentage and the last task activity snapshot as the cumulative end-of-day percentage.
- Historical progressive-task breakdowns show both cumulative progress and the portion earned on that date (for example, `15% cumulative · +5% that day`).
- The legacy event-only fallback for partially populated task activity histories now also uses the day's net progress rather than cumulative progress.

## Regression coverage

- Editing a habit's difficulty after recording today's completion updates today's snapshot but leaves yesterday's snapshot unchanged.
- Launching with a stale open-day snapshot reconciles that date only and preserves previous dates.
- A task progressing from 10% to 15% across two dates awards 10% on the first date and 5% on the second date, while showing 15% cumulative progress on the second date.
- Moving a progressive-task slider up and then back to its start value on a historical date awards no points.

## Data compatibility

No SQLite schema change is required. The correction uses the existing daily completion snapshots, immutable task-activity snapshots, and task-progress events. Existing tasks, habits, attachments, settings, and historical records are retained.

## Verification

The source archive was checked for ZIP integrity. Flutter formatting, analysis, unit/widget tests, and APK compilation must still be run in the project's GitHub Actions environment because the Flutter SDK is not installed in this build environment.
