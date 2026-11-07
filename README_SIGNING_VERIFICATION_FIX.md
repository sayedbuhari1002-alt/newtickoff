# Tazkiyane signing verification parser fix

## Apply

Extract this ZIP into the repository root and overwrite:

`.github/workflows/build_apk.yml`

This is a workflow-only correction. It does not modify Dart source, app data, the keystore, GitHub Secrets, package ID, or version number.

## What it fixes

The previous verifier only recognized the older `Signer #1 certificate SHA-256 digest:` output. Newer Android Build Tools can report signers using an SDK-range label such as `Signer (minSdkVersion=24, maxSdkVersion=...) certificate SHA-256 digest:`. The old parser therefore returned `Actual: not found`, even though Gradle had produced the APK.

The corrected verifier accepts both output forms, captures diagnostic output, and checks the extracted certificate fingerprint against the existing permanent keystore. It does not weaken the signature check.

## Commit and push

```powershell
git add .github/workflows/build_apk.yml
git commit -m "Fix APK signing certificate verification"
git push origin main
```

Do not regenerate the keystore or change any of the four GitHub Secrets for this parser-only fix.
