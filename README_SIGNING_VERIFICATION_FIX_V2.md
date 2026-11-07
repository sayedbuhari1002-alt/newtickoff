# Tazkiyane signing-verification fix (v2)

This patch changes only `.github/workflows/build_apk.yml`.

The last workflow successfully built a release APK and `apksigner` printed the expected SHA-256 certificate digest, but the parser did not match the current `V2 Signer: certificate SHA-256 digest:` format.

The updated parser matches the stable `certificate SHA-256 digest:` text and no longer depends on the signer label. It accepts the older `Signer #1`, SDK-range signer labels, and the current `V2 Signer:` format. The expected digest comparison remains strict.

No application source, version code, keystore, or GitHub Secrets are changed. Keep the existing keystore and all four existing Actions secrets.
