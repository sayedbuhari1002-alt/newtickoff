# Notification runtime fix

## Symptom
Release APK reports `PlatformException ... Missing type parameter` when scheduling
or cancelling a reminder. The Android stack trace enters
`FlutterLocalNotificationsPlugin.loadScheduledNotifications`.

## Cause
The Android notification plugin uses Gson `TypeToken` to deserialize its
scheduled-notification cache. R8 can strip the generic `Signature` metadata
needed by Gson in release builds.

## Fix
`tool/prepare_android.sh` now generates
`android/app/proguard-rules.pro` with Gson's documented TypeToken keep rules
and wires that file into the Android release build configuration for both
Gradle Kotlin DSL and Groovy DSL.

The Android scaffold is generated during GitHub Actions, so these rules are
created as part of the build and are not lost when `android/` is regenerated.

## Verification required
Run the GitHub Actions Android release build and install the resulting APK.
Test:
1. Create a task with a future reminder and save it.
2. Edit the reminder and save again (this exercises cancellation + rescheduling).
3. Create a weekly habit reminder and save it.
4. Confirm the reminders appear in Android's scheduled notifications / arrive
   at the configured time with notification and exact-alarm access enabled.
