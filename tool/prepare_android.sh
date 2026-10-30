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



# Preserve Gson generic signatures used by flutter_local_notifications.
# R8 full mode can otherwise strip TypeToken metadata and cause
# "RuntimeException: Missing type parameter" while cancelling/loading reminders.
PROGUARD_RULES="android/app/proguard-rules.pro"
cat > "$PROGUARD_RULES" <<'EOF'
# Gson TypeToken requires generic signatures at runtime.
-keepattributes Signature
-keep,allowobfuscation class com.google.gson.reflect.TypeToken
-keep,allowobfuscation class * extends com.google.gson.reflect.TypeToken
EOF

# The Android scaffold is generated during CI. Keep R8 in compatibility mode
# as an additional safeguard for this plugin/Gson reflection path. Replace an
# existing value rather than appending duplicate Gradle properties.
GRADLE_PROPERTIES="android/gradle.properties"
if [ ! -f "$GRADLE_PROPERTIES" ]; then
  touch "$GRADLE_PROPERTIES"
fi
if grep -q '^[[:space:]]*android\.enableR8\.fullMode[[:space:]]*=' "$GRADLE_PROPERTIES"; then
  sed -i 's/^[[:space:]]*android\.enableR8\.fullMode[[:space:]]*=.*/android.enableR8.fullMode=false/' "$GRADLE_PROPERTIES"
else
  printf '\nandroid.enableR8.fullMode=false\n' >> "$GRADLE_PROPERTIES"
fi

# Ensure the generated Android release build consumes the app ProGuard rules.
# Match both `release {` and Kotlin/Groovy `getByName("release") {` forms.
if [ -f android/app/build.gradle.kts ]; then
  APP_GRADLE="android/app/build.gradle.kts"
  if ! grep -q 'proguard-rules.pro' "$APP_GRADLE"; then
    python3 - "$APP_GRADLE" <<'PYGRADLE'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
source = path.read_text()
pattern = r'''(?m)^([ \t]*)(?:release|getByName\(["']release["']\))[ \t]*\{'''
match = re.search(pattern, source)
if not match:
    raise SystemExit(f"Could not find the release buildType block in {path}")
indent = match.group(1) + "    "
line = indent + 'proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")'
source = source[:match.end()] + "\n" + line + source[match.end():]
path.write_text(source)
PYGRADLE
  fi
elif [ -f android/app/build.gradle ]; then
  APP_GRADLE="android/app/build.gradle"
  if ! grep -q 'proguard-rules.pro' "$APP_GRADLE"; then
    python3 - "$APP_GRADLE" <<'PYGRADLE'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
source = path.read_text()
pattern = r'''(?m)^([ \t]*)(?:release|getByName\(["']release["']\))[ \t]*\{'''
match = re.search(pattern, source)
if not match:
    raise SystemExit(f"Could not find the release buildType block in {path}")
indent = match.group(1) + "    "
line = indent + "proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'"
source = source[:match.end()] + "\n" + line + source[match.end():]
path.write_text(source)
PYGRADLE
  fi
else
  echo "ERROR: Neither android/app/build.gradle.kts nor build.gradle exists" >&2
  exit 1
fi

# Verify the generated Android project contains both parts of the fix. This
# prevents CI from silently building an APK without applying the workaround.
grep -q 'android.enableR8.fullMode=false' "$GRADLE_PROPERTIES"
grep -q 'proguard-rules.pro' "$APP_GRADLE"
echo "Applied Gson TypeToken keep rules and R8 compatibility-mode workaround."

# Runtime permissions and receivers required by exact local reminders and recording.
for permission in POST_NOTIFICATIONS RECEIVE_BOOT_COMPLETED RECORD_AUDIO SCHEDULE_EXACT_ALARM; do
  if ! grep -q "android.permission.${permission}" "$MANIFEST"; then
    sed -i "/<application/i\    <uses-permission android:name=\"android.permission.${permission}\" />" "$MANIFEST"
  fi
done
if ! grep -q 'ScheduledNotificationReceiver' "$MANIFEST"; then
  sed -i '/<\/application>/i\        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />\n        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">\n            <intent-filter>\n                <action android:name="android.intent.action.BOOT_COMPLETED" />\n                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />\n                <action android:name="android.intent.action.QUICKBOOT_POWERON" />\n                <action android:name="android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED" />\n            </intent-filter>\n        </receiver>' "$MANIFEST"
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
