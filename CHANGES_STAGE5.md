# Stage 4 + Stage 5 implementation notes

This package extends the supplied Stage 3 project rather than nesting the original archive or replacing the habit tracker with a new demo app.

- Added local task and ordered subtask models with stable IDs, reminder/deadline metadata, repeat rules, attachments, completion state, and validation.
- Added SQLite schema version 2 as an additive migration; introduced task, subtask, and activity tables without resetting Stage 3 tables.
- Added an immutable task activity journal and snapshot-based analytics, preserving task events after deletion and attributing child completion to its actual event date.
- Added task lifecycle operations: create/edit, complete/reopen, pause/resume, postpone, repeat, duplicate, delete, and subtask reordering/completion.
- Added local notification scheduling for tasks and supported habit reminders.
- Added task create/edit/details/list/analytics and subtask-editor screens; integrated the four primary destinations and central Add menu.
- Moved the full habit list to the dedicated Habits destination and changed Dashboard to an overview with separate task/habit progress.
- Added task-engine and SQLite migration/history tests and updated affected existing widget tests for the new navigation.
- Added an Android scaffold preparation script and a CI workflow that reports check failures instead of treating analysis and format errors as informational.

See `BUILD_VERIFICATION.md` for checks that could not be executed because the Flutter/Dart SDK was unavailable in the preparation environment. Treat all unexecuted tests/builds as unverified.
