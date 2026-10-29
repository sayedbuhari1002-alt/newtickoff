#!/usr/bin/env bash
# Generates the Android Gradle scaffold with the Flutter SDK installed on the
# build machine (so Gradle/AGP/Kotlin versions always match that SDK), then
# applies the small customisations this app needs.
# Safe to run repeatedly: it only generates android/ when it is missing.
set -euo pipefail

PROJECT_NAME="tickoff_replacement"
ORG="dev.tickoffreplacement"
APP_LABEL="TickOff"

if [ ! -d "android/app" ]; then
  echo "Generating Android scaffold with the installed Flutter SDK..."
  SCAFFOLD_DIR="$(mktemp -d)"
  flutter create --platforms=android \
    --project-name "$PROJECT_NAME" \
    --org "$ORG" \
    "$SCAFFOLD_DIR/$PROJECT_NAME"
  cp -R "$SCAFFOLD_DIR/$PROJECT_NAME/android" ./android
  rm -f android/local.properties
else
  echo "android/ already exists - leaving it untouched."
fi

MANIFEST="android/app/src/main/AndroidManifest.xml"
if [ -f "$MANIFEST" ]; then
  sed -i "s/android:label=\"[^\"]*\"/android:label=\"$APP_LABEL\"/" "$MANIFEST"
  echo "App label set to $APP_LABEL"
else
  echo "ERROR: $MANIFEST not found" >&2
  exit 1
fi


# Runtime permissions and receivers required by local reminders and recording.
for permission in POST_NOTIFICATIONS RECEIVE_BOOT_COMPLETED RECORD_AUDIO; do
  if ! grep -q "android.permission.${permission}" "$MANIFEST"; then
    sed -i "/<application/i\    <uses-permission android:name=\"android.permission.${permission}\" />" "$MANIFEST"
  fi
done
if ! grep -q 'ScheduledNotificationReceiver' "$MANIFEST"; then
  sed -i '/<\/application>/i\        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />\n        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">\n            <intent-filter>\n                <action android:name="android.intent.action.BOOT_COMPLETED" />\n                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />\n                <action android:name="android.intent.action.QUICKBOOT_POWERON" />\n            </intent-filter>\n        </receiver>' "$MANIFEST"
fi

# flutter_local_notifications 17 uses core-library desugaring for scheduled
# notifications. Apply the required setting to either Gradle DSL so the
# generated Android scaffold can compile the same dependency set consistently.
if [ -f android/app/build.gradle.kts ]; then
  APP_GRADLE="android/app/build.gradle.kts"
  if ! grep -q 'multiDexEnabled' "$APP_GRADLE"; then
    sed -i '/defaultConfig[[:space:]]*{/a\        multiDexEnabled = true' "$APP_GRADLE"
  fi
  if ! grep -q 'isCoreLibraryDesugaringEnabled' "$APP_GRADLE"; then
    sed -i '/compileOptions[[:space:]]*{/a\        isCoreLibraryDesugaringEnabled = true' "$APP_GRADLE"
  fi
  if ! grep -q 'desugar_jdk_libs' "$APP_GRADLE"; then
    if grep -q 'dependencies[[:space:]]*{' "$APP_GRADLE"; then
      sed -i '/dependencies[[:space:]]*{/a\    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")' "$APP_GRADLE"
    else
      printf '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n' >> "$APP_GRADLE"
    fi
  fi
elif [ -f android/app/build.gradle ]; then
  APP_GRADLE="android/app/build.gradle"
  if ! grep -q 'multiDexEnabled' "$APP_GRADLE"; then
    sed -i '/defaultConfig[[:space:]]*{/a\        multiDexEnabled true' "$APP_GRADLE"
  fi
  if ! grep -q 'coreLibraryDesugaringEnabled' "$APP_GRADLE"; then
    sed -i '/compileOptions[[:space:]]*{/a\        coreLibraryDesugaringEnabled true' "$APP_GRADLE"
  fi
  if ! grep -q 'desugar_jdk_libs' "$APP_GRADLE"; then
    if grep -q 'dependencies[[:space:]]*{' "$APP_GRADLE"; then
      sed -i "/dependencies[[:space:]]*{/a\\    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'" "$APP_GRADLE"
    else
      printf "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n" >> "$APP_GRADLE"
    fi
  fi
fi
