# Tazkiyane v0.5.0+21 — Import Fix

This is a targeted compile-fix patch for the v0.5.0+21 feature patch.

## Files

- `lib/features/notes/note_library_screen.dart`
  - Imports `app_state.dart`, where `appDataProvider` is declared.
- `lib/features/settings/widgets_settings_screen.dart`
  - Imports `app_data.dart`, where the `AppData` type is declared.

No database schema, UI layout, app identifier, signing configuration, or feature behaviour is changed.

## Apply

Extract this ZIP into the root of the existing `newtickoff` repository and overwrite the two files.
Then run:

```powershell
git add lib/features/notes/note_library_screen.dart lib/features/settings/widgets_settings_screen.dart
git commit -m "Fix app state imports for notes and widgets"
git push origin main
```

Keep the permanent release keystore and all four GitHub Actions signing secrets unchanged.
