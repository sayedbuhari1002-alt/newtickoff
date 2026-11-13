# Tazkiyane v0.6.7+32 — Flutter build correction

## Fixed

- Removed the unsupported `mainAxisSize` argument from the `Wrap` widget used by the subtask action controls in the task form.
- Applied the same correction in the reusable task-template editor.
- Kept the existing `Wrap` layout and subtask edit/remove actions unchanged.

This resolves the Dart compilation errors reported by GitHub Actions for `task_form_screen.dart` and `task_template_editor_screen.dart`. The related widget-test loading failures were downstream of those same compilation errors.

## Preserved

All v0.6.7+31 task-template features, notes, photo/audio attachments, reusable subtasks, category selection, SQLite schema version 12, and earlier productivity updates are retained.

## Version

- App version: `0.6.7+32`
