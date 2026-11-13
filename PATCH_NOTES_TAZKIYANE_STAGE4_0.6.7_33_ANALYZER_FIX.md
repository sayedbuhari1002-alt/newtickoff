# Tazkiyane v0.6.7+33 — Analyzer warning correction

## Fixed

- Removed the unused `app_data.dart` import from `task_template_editor_screen.dart`.
- This resolves the sole analyzer warning reported in the supplied GitHub Actions log. The workflow runs `flutter analyze --no-fatal-infos`, which still fails on warnings even though informational lints are non-fatal.

## Preserved

All v0.6.7+32 functionality is retained, including reusable task-template notes, photo/audio attachments, subtasks, category selection, SQLite schema version 12, and previous productivity updates.

## Version

- App version: `0.6.7+33`
