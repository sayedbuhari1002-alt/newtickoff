#!/usr/bin/env bash
# Generates the Android Gradle scaffold with the Flutter SDK installed on the
# build machine (so Gradle/AGP/Kotlin versions always match that SDK), then
# applies the small customisations this app needs.
# Safe to run repeatedly: it only generates android/ when it is missing.
set -euo pipefail

PROJECT_NAME="tickoff_replacement"
ORG="dev.tickoffreplacement"
APP_LABEL="Tazkiyane"

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

# Android Gradle Plugin 9.3.0/9.3.1 contains a known lint crash on JDK 17:
# NoSuchMethodError: java.util.List.removeLast() in the bundled JavaDocParser.
# Google fixed this in AGP 9.3.2. Pin only the affected patch versions while
# keeping the Flutter-generated Gradle wrapper and Java 17 toolchain intact.
python3 - <<'PYAGP'
from pathlib import Path
import re

candidates = [
    Path("android/settings.gradle.kts"),
    Path("android/settings.gradle"),
    Path("android/build.gradle.kts"),
    Path("android/build.gradle"),
]
patterns = [
    re.compile(
        r'(id\(["\']com\.android\.(?:application|library)["\']\)\s+version\s+["\'])'
        r'9\.3\.[01](["\'])'
    ),
    re.compile(
        r'(id\s+["\']com\.android\.(?:application|library)["\']\s+version\s+["\'])'
        r'9\.3\.[01](["\'])'
    ),
    re.compile(
        r'(classpath\(["\']com\.android\.tools\.build:gradle:)'
        r'9\.3\.[01](["\']\))'
    ),
]
changed = False
found = []
for path in candidates:
    if not path.is_file():
        continue
    source = path.read_text()
    updated = source
    for pattern in patterns:
        updated, count = pattern.subn(r'\g<1>9.3.2\g<2>', updated)
        changed = changed or count > 0
    if updated != source:
        path.write_text(updated)
        print(f"Updated Android Gradle Plugin to 9.3.2 in {path}")
    for match in re.finditer(
        r'(?:com\.android\.(?:application|library)["\']?\)?\s+version\s+["\']|'
        r'com\.android\.tools\.build:gradle:)([0-9]+\.[0-9]+\.[0-9]+)',
        updated,
    ):
        found.append((path, match.group(1)))
if not any(path.is_file() for path in candidates):
    raise SystemExit("Could not find generated Android Gradle settings/build files.")
if changed:
    print("Applied the AGP 9.3.2 lint-crash fix.")
else:
    print("No AGP 9.3.0/9.3.1 pin needed; leaving the Flutter scaffold's AGP version unchanged.")
PYAGP

MANIFEST="android/app/src/main/AndroidManifest.xml"
if [ -f "$MANIFEST" ]; then
  sed -i "s/android:label=\"[^\"]*\"/android:label=\"$APP_LABEL\"/" "$MANIFEST"
  echo "App label set to $APP_LABEL"
else
  echo "ERROR: $MANIFEST not found" >&2
  exit 1
fi

# Keep an intent query for launcher apps, and request broad package visibility
# so the distraction picker can include installed apps that are not consistently
# exposed by launcher-intent queries (for example, some preinstalled apps).
if ! grep -q '<queries>' "$MANIFEST"; then
  python3 - "$MANIFEST" <<'PYQUERIES'
from pathlib import Path
import re
import sys
path = Path(sys.argv[1])
source = path.read_text()
match = re.search(r'<manifest\b[^>]*>', source, re.S)
if not match:
    raise SystemExit(f"Could not find the manifest root in {path}")
queries = """
    <queries>
        <intent>
            <action android:name="android.intent.action.MAIN" />
            <category android:name="android.intent.category.LAUNCHER" />
        </intent>
    </queries>"""
source = source[:match.end()] + queries + source[match.end():]
path.write_text(source)
PYQUERIES
fi

# Apply the approved Tazkiyane launcher icon to the generated Android scaffold.
# The Android project is generated in CI, so the source artwork and density
# variants live in the repository and are copied in on every fresh build.
ICON_SOURCE="assets/branding/android"
if [ ! -f "assets/branding/tazkiyane_icon.png" ]; then
  echo "ERROR: Approved Tazkiyane app icon asset is missing." >&2
  exit 1
fi
for density in mipmap-mdpi mipmap-hdpi mipmap-xhdpi mipmap-xxhdpi mipmap-xxxhdpi; do
  SOURCE_DIR="$ICON_SOURCE/$density"
  TARGET_DIR="android/app/src/main/res/$density"
  if [ ! -f "$SOURCE_DIR/ic_launcher.png" ] || [ ! -f "$SOURCE_DIR/ic_launcher_round.png" ]; then
    echo "ERROR: Launcher icon resources are missing for $density." >&2
    exit 1
  fi
  mkdir -p "$TARGET_DIR"
  cp "$SOURCE_DIR/ic_launcher.png" "$TARGET_DIR/ic_launcher.png"
  cp "$SOURCE_DIR/ic_launcher_round.png" "$TARGET_DIR/ic_launcher_round.png"
done
# Remove the generated Flutter adaptive XML resources so Android resolves the
# approved, density-specific PNGs instead of the default Flutter logo layers.
rm -f android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
rm -f android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml
echo "Installed the approved Tazkiyane launcher icon in all Android densities."

# Install the native Android home-screen widget resources. They are copied into
# the freshly generated scaffold on every CI build.
WIDGET_SOURCE="assets/branding/android_widget"
mkdir -p android/app/src/main/res/layout android/app/src/main/res/xml android/app/src/main/res/drawable android/app/src/main/res/values
cp "$WIDGET_SOURCE/layout/tazkiyane_tasks_widget.xml" android/app/src/main/res/layout/
cp "$WIDGET_SOURCE/xml/tazkiyane_tasks_widget_info.xml" android/app/src/main/res/xml/
cp "$WIDGET_SOURCE/drawable/tazkiyane_widget_background.xml" android/app/src/main/res/drawable/
cp "$WIDGET_SOURCE/values/tazkiyane_widget_strings.xml" android/app/src/main/res/values/
KOTLIN_DIR="android/app/src/main/kotlin/dev/tickoffreplacement/tickoff_replacement"
mkdir -p "$KOTLIN_DIR"
cp "$WIDGET_SOURCE/kotlin/TazkiyaneTasksWidgetProvider.kt" "$KOTLIN_DIR/"
# Install the UsageStats MethodChannel bridge used by Productivity distraction tracking.
cp "assets/branding/android_usage/MainActivity.kt" "$KOTLIN_DIR/MainActivity.kt"
if ! grep -q 'TazkiyaneTasksWidgetProvider' "$MANIFEST"; then
  sed -i '/<\/application>/i\        <receiver android:name=".TazkiyaneTasksWidgetProvider" android:exported="true" android:label="Tazkiyane Tasks">\n            <intent-filter>\n                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />\n            </intent-filter>\n            <meta-data android:name="android.appwidget.provider" android:resource="@xml/tazkiyane_tasks_widget_info" />\n        </receiver>' "$MANIFEST"
fi
echo "Installed Tazkiyane Tasks Android home-screen widget and UsageStats bridge."


# Preserve Gson generic signatures used by flutter_local_notifications.
# R8 full mode can otherwise strip TypeToken metadata and cause
# "RuntimeException: Missing type parameter" while cancelling/loading reminders.
PROGUARD_RULES="android/app/proguard-rules.pro"
cat > "$PROGUARD_RULES" <<'EOF'
# Gson TypeToken requires generic signatures at runtime.
-keepattributes Signature
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
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

# Require one stable release-signing identity. The actual private keystore and
# credentials are supplied only by GitHub Actions secrets at build time.
python3 tool/configure_release_signing.py "$APP_GRADLE"

# Runtime permissions and receivers required by exact local reminders and recording.
for permission in POST_NOTIFICATIONS RECEIVE_BOOT_COMPLETED RECORD_AUDIO SCHEDULE_EXACT_ALARM PACKAGE_USAGE_STATS QUERY_ALL_PACKAGES; do
  if ! grep -q "android.permission.${permission}" "$MANIFEST"; then
    sed -i "/<application/i\    <uses-permission android:name=\"android.permission.${permission}\" />" "$MANIFEST"
  fi
done
# QUERY_ALL_PACKAGES is a manifest-only package-visibility permission; Android
# does not show a runtime prompt for it. It is used by this sideloadable,
# offline-first app to populate the user's installed-app selection list.
grep -q 'android.permission.QUERY_ALL_PACKAGES' "$MANIFEST"
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
