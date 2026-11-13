# Tazkiyane v0.6.7+31 — Reusable Task Template Expansion

## Task templates now store reusable task content

Task templates now include:
- Notes text.
- Photo attachments.
- Audio recordings.
- A reusable subtask checklist, including each subtask's difficulty score.

When a template is applied to a new task, its notes and attachment references are copied, and each subtask is instantiated with a new ID and an incomplete state. Subtask deadlines, reminders, and completion timestamps are intentionally not copied so a reusable template does not carry stale dates or completion state into a new task.

## Task form improvements

- Task categories now use the same category selection sheet as habits, including No category and New category.
- Existing legacy free-text task categories are preserved when editing until the user selects a managed category.
- Added subtask creation, editing, and removal to the task form.
- Saving a task's settings as a template now includes notes, photos, audio notes, and subtasks.

## Template management improvements

- Added a dedicated template editor for reusable notes, photo/audio attachments, and subtasks.
- Template duplication retains its notes and attachments and creates fresh subtask IDs.
- Template list cards display counts for subtasks, photos, and audio notes.
- Attachment cleanup now checks template references so a task or template cannot delete a file that is still used by another task or template.

## Database

- SQLite schema version increased from 11 to 12.
- Added `notes`, `photo_paths_json`, `audio_paths_json`, and `subtasks_json` to `task_templates` using an additive migration. Existing task templates remain intact and receive empty defaults for the new fields.

## Version

- App version: `0.6.7+31`
