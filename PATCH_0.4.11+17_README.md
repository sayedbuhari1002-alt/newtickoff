# Tazkiyane 0.4.11+17 targeted patch

This archive contains only the files changed for the habit-navigation fix and Daily Notes media attachments. It is not a complete Flutter project.

## Apply the patch

1. Extract this ZIP into the root of your existing Tazkiyane project.
2. Allow the files in the ZIP to overwrite files at the same relative paths.
3. Run:

   ```bash
   flutter pub get
   dart format lib test
   flutter analyze --no-fatal-infos
   flutter test test/unit test/widget
   flutter test test/data
   flutter build apk --release
   ```

## Changes

- Saving an edited habit now pops the edit form and preserves the existing Habit Details -> Dashboard navigation stack. Creating a new habit keeps its previous navigation behaviour.
- Daily Notes can attach photos (camera/gallery), record and play audio, and capture/select and play videos.
- Media is copied into the app's private documents directory and is associated with the dated note.
- Removed and deleted note attachments are cleaned up when no other task or note references the file.
- SQLite schema version 5 adds `videos_json`. Existing v4 notes and their photo/audio references are preserved automatically during migration.
- Android scaffold preparation adds the CAMERA permission; RECORD_AUDIO was already included.
- Regression tests cover Dashboard navigation, video attachment persistence, and the v4-to-v5 database migration.

## Important

The source archive used to prepare this patch did not contain a Flutter/Dart SDK in the editing environment. The patch received static file/YAML/shell checks, but Flutter formatting, analysis, tests, and APK compilation were not run here. Run the commands above or use the project's GitHub Actions workflow before treating the APK as verified.
