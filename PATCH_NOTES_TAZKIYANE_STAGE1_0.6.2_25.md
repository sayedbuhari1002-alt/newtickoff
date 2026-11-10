# Tazkiyane Stage 1 — Live Scoring and 1–10 Difficulty Scale

This staged update contains the scoring and difficulty foundation only. Unified Analytics and the restored Suggested Next recommendations are intentionally reserved for Stage 2.

## 1. Live daily productivity scoring
- Today's build-habit score is calculated from the current saved tick, count, or checked checklist items and the current habit point value.
- Today's quit-habit penalty uses the current saved slip state and current configured penalty.
- Today's standard-task points are awarded only while the task remains completed for the current day. Reopening it removes today's contribution.
- Progressive percentage and count tasks use their current saved progress when the progress has been changed today (or the task was created today). Reducing progress immediately reduces the contribution; setting it to zero removes it.
- Inline subtasks/checklist items contribute their own difficulty points only while currently completed for the day. Their parent is not scored again.
- First-class task-group children are scored individually; group parents are excluded to avoid double-counting.
- Distraction penalties continue to use recorded durations and configured penalty rates. Overlapping manual and automatic usage remains charged once at the highest active rate.

## 2. Historical score preservation
- The first launch after this update stores a local scoring-model activation date in the existing app-settings table. No database schema migration is needed.
- Dates before that activation date continue using the previous scoring calculation, so upgrading does not reinterpret existing historical scores.
- Dates on or after the activation date are reconstructed from immutable end-of-day task-state snapshots. Later reopening, resetting, editing or deleting a task does not rewrite an earlier date's state. An increase followed by a reset on the same date produces zero for that date; that result remains unchanged after midnight.
- Historical habit scores continue to use the configuration snapshots stored in their CompletionRecords. Today's edits do not recalculate previous dates.
- Older partial activity snapshots retain a compatibility fallback to the legacy event-based interpretation.

## 3. Difficulty scale
- Expanded task difficulty, subtask difficulty, task-template difficulty and legacy assignment difficulty from 1–5 to 1–10 (decimal values remain supported).
- Build-habit productivity points are also expanded from 1–5 to 1–10 so the positive scoring inputs can use the same range.
- Existing stored values are preserved; no automatic multiplication or database migration is performed.

## 4. Compatibility
- No SQLite schema migration is required.
- Version updated to 0.6.2+25 for an in-place Android upgrade over 0.6.1+24, provided the same permanent signing key is used.
- Stage 2 (unified Analytics and Suggested Next task recommendations) is not included in this ZIP.

## Verification
- Source-level checks and ZIP integrity are performed during preparation.
- This environment does not have Flutter/Dart installed, so `dart format`, `flutter analyze`, `flutter test` and the signed APK build must be verified by GitHub Actions before installation.
