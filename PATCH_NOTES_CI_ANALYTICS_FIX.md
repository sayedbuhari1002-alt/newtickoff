# Tazkiyane 0.6.5+29 — CI analytics and Android lint fixes

## GitHub Actions failures diagnosed

- Restored the existing `Completions` metric while retaining a separate fractional `Progress Units` metric for count/checklist partial progress.
- Restored the `Actual Count History` section for count habits and added a separate `Checklist Progress History` section.
- Updated the generated Android scaffold to use AGP 9.3.2 when the Flutter template selects affected AGP 9.3.0/9.3.1. This is the upstream patch release that fixes the JDK 17 lint `List.removeLast()` crash.

## Preserved

- Income and expense transactions and analytics.
- Partial count/checklist progress in aggregate analytics.
- Full-completion semantics for the `Completions` metric, completion status and streaks.
- Existing UI components and theme.

## Validation

The source changes were reviewed and the archive was checked for integrity. Flutter analyze/tests and an Android APK build must be run in GitHub Actions to confirm the complete toolchain build.
