#!/usr/bin/env python3
"""Configure generated Android Gradle files to require Tazkiyane's release key.

The key itself is supplied to Gradle through environment variables by CI. No
keystore or password is written into the repository or Android source tree.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

APPLICATION_ID = "dev.tickoffreplacement.tickoff_replacement"
MARKER = "Tazkiyane permanent release signing"

KOTLIN_SIGNING = '''    // Tazkiyane permanent release signing. CI supplies these values from GitHub Secrets.
    signingConfigs {
        create("release") {
            val releaseStorePath = System.getenv("ANDROID_KEYSTORE_PATH")
                ?: throw GradleException("Missing ANDROID_KEYSTORE_PATH; configure the Tazkiyane Android signing secrets.")
            storeFile = file(releaseStorePath)
            storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                ?: throw GradleException("Missing ANDROID_KEYSTORE_PASSWORD GitHub secret.")
            keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                ?: throw GradleException("Missing ANDROID_KEY_ALIAS GitHub secret.")
            keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
                ?: throw GradleException("Missing ANDROID_KEY_PASSWORD GitHub secret.")
        }
    }
'''

GROOVY_SIGNING = '''    // Tazkiyane permanent release signing. CI supplies these values from GitHub Secrets.
    def tazkiyaneReleaseStorePath = System.getenv('ANDROID_KEYSTORE_PATH')
    def tazkiyaneReleaseStorePassword = System.getenv('ANDROID_KEYSTORE_PASSWORD')
    def tazkiyaneReleaseKeyAlias = System.getenv('ANDROID_KEY_ALIAS')
    def tazkiyaneReleaseKeyPassword = System.getenv('ANDROID_KEY_PASSWORD')
    if (!tazkiyaneReleaseStorePath || !tazkiyaneReleaseStorePassword ||
        !tazkiyaneReleaseKeyAlias || !tazkiyaneReleaseKeyPassword) {
        throw new GradleException('Missing Tazkiyane release signing environment variables. Configure GitHub Actions secrets.')
    }
    signingConfigs {
        release {
            storeFile file(tazkiyaneReleaseStorePath)
            storePassword tazkiyaneReleaseStorePassword
            keyAlias tazkiyaneReleaseKeyAlias
            keyPassword tazkiyaneReleaseKeyPassword
        }
    }
'''


def ensure_application_id(source: str, path: Path) -> None:
    pattern = re.compile(
        r"applicationId\s*(?:=\s*)?['\"]" + re.escape(APPLICATION_ID) + r"['\"]"
    )
    if not pattern.search(source):
        raise SystemExit(
            f"{path}: expected applicationId '{APPLICATION_ID}' was not found. "
            "Refusing to build an APK that could install as a different app."
        )


def configure(path: Path, kotlin: bool) -> None:
    source = path.read_text(encoding="utf-8")
    ensure_application_id(source, path)

    if MARKER in source:
        expected = (
            'signingConfig = signingConfigs.getByName("release")'
            if kotlin
            else "signingConfig signingConfigs.release"
        )
        if expected not in source:
            raise SystemExit(f"{path}: signing marker exists but the release build type is not using it.")
        print(f"{path}: permanent release signing already configured.")
        return

    android_match = re.search(r"(?m)^android\s*\{", source)
    if not android_match:
        raise SystemExit(f"{path}: could not find the top-level android {{ block.")

    if kotlin:
        old_lines = (
            'signingConfig = signingConfigs.getByName("debug")',
            "signingConfig = signingConfigs.debug",
        )
        new_line = 'signingConfig = signingConfigs.getByName("release")'
        block = KOTLIN_SIGNING
    else:
        old_lines = (
            "signingConfig signingConfigs.debug",
            "signingConfig = signingConfigs.debug",
        )
        new_line = "signingConfig signingConfigs.release"
        block = GROOVY_SIGNING

    found = next((line for line in old_lines if line in source), None)
    if found is None:
        raise SystemExit(
            f"{path}: expected Flutter's default debug signing assignment was not found. "
            "Refusing to leave a release APK on debug signing."
        )

    source = source.replace(found, new_line, 1)
    insert_at = android_match.end()
    source = source[:insert_at] + "\n" + block + source[insert_at:]
    path.write_text(source, encoding="utf-8")
    print(f"{path}: configured to require the permanent Tazkiyane release key.")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: configure_release_signing.py <android/app/build.gradle[.kts]>")
    path = Path(sys.argv[1])
    if not path.is_file():
        raise SystemExit(f"Android Gradle file not found: {path}")
    configure(path, kotlin=path.name.endswith(".kts"))


if __name__ == "__main__":
    main()
