Tazkiyane Task Management Update – v0.5.1+22

This patch is based on the uploaded v0.5.0+21 source archive.

Included:
- First-class parent/child task grouping with long-press multi-selection.
- Move individual tasks from multiple groups into a new or existing parent group.
- Parent progress derived from child task progress; parent completion follows all children.
- Standard and Progressive task types with percentage or count/target progress.
- Dated progress events, including difficulty snapshots for future Productivity scoring.
- Duplicate, postpone and delete operations, including parent-group safeguards.
- Parent postponement shifts the parent and all child task dates/reminders.
- Reusable task templates with management and direct use from the template list.
- Home-page Habits Due sorting puts habits needing attention before successful/completed habits.
- Additive SQLite schema migration to version 7.

Version: 0.5.1+22
Package ID and permanent Android signing configuration are unchanged.

Apply this ZIP by extracting it over the root of your existing repository and allowing files to be overwritten. Do not delete the existing project, .git folder, local keystore backup, or GitHub Secrets.

Build and verification are intended to run through the existing GitHub Actions workflow. This patch has not been compiled with Flutter in this environment. Review the Actions workflow result before installing the APK. Keep v0.5.0+21 installed until the new APK passes build and permanent-signature verification.
