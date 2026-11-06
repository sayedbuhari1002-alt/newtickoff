# Notification runtime fix

## Symptom
Release APK reports `PlatformException ... Missing type parameter` when
scheduling or cancelling a reminder. The Android stack trace enters
`FlutterLocalNotificationsPlugin.loadScheduledNotifications`, then
`removeNotificationFromCache` and `cancelNotification`.

## Cause
The Android notification plugin uses Gson `TypeToken` to deserialize its
scheduled-notification cache. R8 can remove generic `Signature` metadata that
Gson needs when reflecting over `TypeToken` subclasses. The failure can occur
while cancelling an existing notification, before a new reminder is saved.

## Build-time correction
`tool/prepare_android.sh` now applies two safeguards to the Android scaffold
created by GitHub Actions:

1. It writes Gson `TypeToken` keep rules to
   `android/app/proguard-rules.pro` and attaches that file to the release
   build type for Kotlin DSL or Groovy DSL Gradle projects.
2. It sets `android.enableR8.fullMode=false` in
   `android/gradle.properties` as a compatibility workaround for the
   reflective Gson path used by the installed notification plugin. Existing
   values are replaced, so the setting is not duplicated on repeated runs.

The script verifies that both settings are present and fails the scaffold step
instead of silently continuing without them. Since Android is generated during
CI, these changes must be made in this script rather than in a local generated
`android/` folder.

## Verification required
The app version is bumped to `0.3.2+5` so Android can install the new APK
over the previous `0.3.1+4` build without clearing app data. The workflow now
withholds the APK artifact if Android scaffold patching fails. Source-level
checks confirm that the patch script is syntactically valid and applies the
settings to representative Kotlin and Groovy Gradle templates. A GitHub
Actions release build and on-device test are still required to confirm runtime
resolution. After installing the APK, test:

1. Create a task with a future reminder and save it.
2. Edit the reminder and save again (this exercises cancellation and
   rescheduling).
3. Create a weekly habit reminder and save it.
4. Confirm reminders appear in Android's scheduled notifications and arrive
   at the configured time, with notification and exact-alarm access enabled.
