# Patch — Productivity Analytics provider import fix

## Root cause
`ProductivityAnalyticsTab` reads `appDataProvider`, but the file imported only
`app_data.dart` (which defines the `AppData` model) and not `app_state.dart`
(which declares `appDataProvider`). Dart imports are not transitive, so the
provider reference was unresolved during static analysis and caused dependent
tests and the release build to fail.

## Change
Added the direct import:

```dart
import '../../state/app_state.dart';
```

No provider implementation, analytics calculations, UI, database schema, or
application behavior was changed.

## Verification
- Confirmed `appDataProvider` is declared in `lib/state/app_state.dart`.
- Confirmed `ProductivityAnalyticsTab` now imports that declaration directly.
- Flutter analyze, tests, and Android APK compilation were not run in this
  environment because the Flutter SDK is not installed. Run the existing
  GitHub Actions workflow after committing this patch.
