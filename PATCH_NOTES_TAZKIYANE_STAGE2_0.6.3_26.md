# Tazkiyane Stage 2 — Analytics & Suggested Next Tasks

**Version:** `0.6.3+26`

This update builds on the working Stage 1 scoring and difficulty update (`0.6.2+25`). It adds a unified analytics destination and restores task recommendations.

## 1. Unified Analytics destination

- Added an **Analytics** shortcut beside Settings on the Home dashboard.
- The Analytics screen now contains three tabs:
  - **Tasks:** the existing task analytics, including completion totals, completion trends, weighted score, on-time/late comparisons and daily breakdowns.
  - **Productivity:** new daily, weekly and monthly productivity views, including net points, average daily points, achievement points, penalties, trend line, period bar chart, source breakdown and best day.
  - **Habits:** the existing habit analytics, including completion rates, streaks, count history, summaries and calendar heatmap.
- The Task List analytics shortcut now opens the unified Analytics screen as well.
- Individual task and habit progress/detail analytics routes remain available.

## 2. Productivity analytics

- Added range selectors for 7 days, 30 days, 90 days and 12 months.
- Daily ranges plot daily scores; 90-day range groups scores into weeks; 12-month range groups by calendar month.
- The screen reads score data from `ProductivityEngine`, including the Stage 1 scoring-model activation date and preserved historical scoring records.
- Today's live changes do not rewrite earlier daily records.

## 3. Suggested Next Tasks

- Restored **Suggested Next** in the Productivity screen.
- Suggestions include upcoming scheduled tasks and tasks without a schedule/deadline.
- Ranking weighs priority, deadline/planned-date urgency, difficulty points and fit against the remaining daily target.
- Completed, paused, group-parent, already-scheduled-for-the-selected-day and overdue tasks are excluded.
- Up to three recommendations are shown. Selecting one opens its task details.
- The Android Home Screen widget keeps the Today's Tasks list separate from the Suggested Next recommendations. Upcoming or unscheduled items can appear in recommendations without being shown as due today.

## 4. Existing functionality preserved

- No database schema migration was added.
- Existing tasks, habits, activity records, reminders, notes, analytics history, distraction records, app-usage records and user settings are retained.
- Stage 1 live scoring, historical score preservation and 1–10 difficulty scale are unchanged.
- No date-specific distraction penalty configuration was added.

## 5. Tests and verification

- Updated analytics widget tests for the three-tab Analytics destination and Home shortcut.
- Updated recommendation unit tests to cover upcoming tasks, unscheduled tasks, overdue/today exclusions, group parents and child tasks.
- Flutter tests and Android APK compilation must be run by GitHub Actions. The local editing environment used to prepare this ZIP does not have the Flutter/Dart SDK installed, so this archive has not been locally compiled or tested.
