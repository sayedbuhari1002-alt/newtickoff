# Tazkiyane 0.6.6+30 — productivity scoring and distraction allowances

## Included changes

### Progressive-task score correction
Today's score now compares the current saved progress against the progress value immediately before the first edit made that day. If a task was at 10% yesterday and is moved from 10% to 36% and then back to 10% today, it earns zero progressive-task points today. If it is left at 20%, it earns points for the net 10 percentage-point increase. A task created today uses zero as its day-start baseline. Historical task scores continue to use their existing saved history calculations.

### Per-app daily distraction allowance
Each selected automatically tracked app has its own daily free-usage allowance in minutes. For example, an Instagram allowance of 30 minutes means the first 30 minutes of that day's Instagram use are free; only usage after minute 30 is scored as a distraction. Different apps can have different limits. An allowance of zero means all usage is eligible for penalties.

Allowance values are copied into saved app-usage sessions. Editing a category's future allowance therefore does not retroactively rewrite usage sessions and productivity scores already saved. Existing usage records receive a zero-minute snapshot during the schema migration, preserving their previous full-duration penalty behavior until the app usage is refreshed under the new setting.

The allowance editor is available when creating or editing a distraction category: enable automatic tracking, select installed apps, then enter each app's daily limit. New or previously unconfigured selected apps default to 30 minutes when the category editor is opened.

### Productivity Analytics graphs
Productivity Analytics now shows three separate trend graphs: net productivity points, points earned before penalties, and penalty points. They share the existing date-range selector (7 days, 30 days, 90 days, and 12 months). Existing summary cards and source/penalty breakdowns remain.

## Database compatibility

SQLite schema version 11 adds a per-app allowance JSON field to distraction categories and a daily allowance snapshot field to automatic app-usage sessions. The migration is additive. Existing habits, tasks, notes, attachments, finance records, categories, usage records, and analytics history are retained.

## Verification status

Added regression tests for the progressive-task slider return-to-baseline case, partial net progress above the baseline, automatic usage under the allowance, excess usage beyond the allowance, and SQLite round-tripping of the new allowance fields. The Flutter/Dart SDK is not installed in the editing environment, so these tests have not been executed locally; the repository's GitHub Actions workflow runs formatting, analysis, unit/widget tests, SQLite tests, and the release build.
