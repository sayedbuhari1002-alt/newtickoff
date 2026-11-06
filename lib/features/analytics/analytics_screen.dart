import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/date_utils.dart';
import '../../domain/logic/achievements.dart';
import '../../domain/logic/analytics_engine.dart';
import '../../domain/logic/habit_engine.dart';
import '../../domain/models/models.dart';
import '../../shared/utils/format.dart';
import '../../shared/utils/habit_ui.dart';
import '../../shared/widgets/widgets.dart';
import '../../state/app_data.dart';
import '../../state/app_state.dart';
import '../habit_detail/habit_sheets.dart';
import 'trend_chart.dart';

/// Analytics: free for everyone. Every figure is computed from the stored
/// completion records; nothing is hard-coded and there is no premium check.
///
/// With [habitId] the screen starts on that habit; otherwise on all habits.
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key, this.habitId});

  final String? habitId;

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _ActualCountHistory extends StatelessWidget {
  const _ActualCountHistory({
    required this.habits,
    required this.data,
    required this.from,
    required this.to,
  });

  final List<Habit> habits;
  final AppData data;
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final List<_CountHistoryValue> values = <_CountHistoryValue>[];
    for (final Habit habit in habits.where((Habit h) => h.tracking == TrackingMethod.count)) {
      for (final MapEntry<String, CompletionRecord> entry in data.recordsFor(habit.id).entries) {
        final DateTime? day = parseDateKey(entry.key);
        if (day == null || day.isBefore(from) || day.isAfter(to) || entry.value.count <= 0) continue;
        values.add(_CountHistoryValue(habit: habit, day: day, count: entry.value.count));
      }
    }
    values.sort((_CountHistoryValue a, _CountHistoryValue b) => b.day.compareTo(a.day));

    return SectionCard(
      title: 'Actual Count History',
      child: values.isEmpty
          ? const Text(
              'No count entries in this date range yet.',
              style: TextStyle(color: AppColors.textSecondary),
            )
          : Column(
              children: <Widget>[
                for (int i = 0; i < values.length; i++) ...<Widget>[
                  if (i > 0) const Divider(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              values[i].habit.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              dayMonthLabel(values[i].day),
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        countLabel(values[i].habit, values[i].count),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}

class _CountHistoryValue {
  const _CountHistoryValue({required this.habit, required this.day, required this.count});
  final Habit habit;
  final DateTime day;
  final double count;
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  String? _habitId;
  AnalyticsRange _range = AnalyticsRange.month;

  @override
  void initState() {
    super.initState();
    _habitId = widget.habitId;
  }

  @override
  Widget build(BuildContext context) {
    final AppData? data = ref.watch(appDataProvider).valueOrNull;
    if (data == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Analytics')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final Habit? chosen = _habitId == null ? null : data.habitById(_habitId!);
    final List<Habit> active = data.activeHabits;
    final List<Habit> selected =
        chosen != null ? <Habit>[chosen] : active;

    if (selected.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Analytics')),
        body: const EmptyState(
          icon: Icons.insights_rounded,
          title: 'No data to analyse yet',
          message: 'Add a habit and complete it for a few days. Your '
              'statistics will appear here.',
        ),
      );
    }

    final HabitEngine engine = ref.watch(habitEngineProvider);
    final AnalyticsEngine analytics = AnalyticsEngine(engine);
    final Map<String, HabitStats> stats = ref.watch(habitStatsProvider);
    final DateTime today = engine.today;

    final DateTime earliest = analytics.earliestStart(selected, data.completions);
    DateTime from = analytics.rangeStart(_range, selected, data.completions);
    if (from.isBefore(earliest)) from = earliest;
    final Tally tally = analytics.tally(selected, data.completions, from, today);
    final List<TrendPoint> points =
        analytics.trend(selected, data.completions, from, today);
    final List<PeriodSummary> summaries =
        analytics.summaries(selected, data.completions);

    final Iterable<HabitStats> selectedStats =
        selected.map((Habit h) => stats[h.id] ?? HabitStats.empty);
    int current = 0;
    int best = 0;
    for (final HabitStats s in selectedStats) {
      if (s.currentStreak > current) current = s.currentStreak;
      if (s.bestStreak > best) best = s.bestStreak;
    }
    final double score = engine.overallScore(selectedStats);

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pagePadding,
          0,
          AppDimens.pagePadding,
          AppDimens.gapLg * 2,
        ),
        children: <Widget>[
          _habitChips(active, chosen),
          const SizedBox(height: AppDimens.gapSm),
          _rangeChips(),
          const SizedBox(height: AppDimens.gap),
          Row(
            children: <Widget>[
              Expanded(
                child: StatTile(value: '$current', label: 'Current Streak'),
              ),
              const SizedBox(width: 10),
              Expanded(child: StatTile(value: '$best', label: 'Best Streak')),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(value: percentLabel(score), label: 'Score'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: StatTile(
                  value: '${tally.completed.round()}',
                  label: 'Completions',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  value: percentLabel(tally.rate),
                  label: 'Completion Rate',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  value: '${daysBetween(from, today) + 1}',
                  label: 'Days Tracked',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.gap),
          SectionCard(
            title: TrendChart.caption(points),
            child: tally.hasData
                ? TrendChart(points: points)
                : const Text(
                    'Nothing was due in this range yet. Complete a habit '
                    'and the chart will fill in.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
          ),
          if (selected.any((Habit h) => h.tracking == TrackingMethod.count)) ...<Widget>[
            const SizedBox(height: AppDimens.gap),
            _ActualCountHistory(habits: selected, data: data, from: from, to: today),
          ],
          const SizedBox(height: AppDimens.gap),
          SectionCard(
            title: 'Summary',
            child: Column(
              children: <Widget>[
                for (final PeriodSummary s in summaries) _summaryRow(s),
              ],
            ),
          ),
          if (selected.length > 1 || chosen == null) ...<Widget>[
            const SizedBox(height: AppDimens.gap),
            SectionCard(
              title: 'Streaks',
              child: Column(
                children: <Widget>[
                  for (final Habit h in selected)
                    _streakRow(h, stats[h.id] ?? HabitStats.empty),
                ],
              ),
            ),
          ],
          if (chosen != null) ...<Widget>[
            const SizedBox(height: AppDimens.gap),
            SectionCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(
                  Icons.emoji_events_outlined,
                  color: AppColors.gold,
                ),
                title: const Text('Achievements'),
                subtitle: Text(
                  '${data.achievementsFor(chosen.id).length} of '
                  '${_milestoneCount()} unlocked',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showAchievementsSheet(context, chosen.id),
              ),
            ),
          ],
          const SizedBox(height: AppDimens.gap),
          SectionCard(
            title: 'Calendar',
            child: MonthCalendar(
              today: today,
              firstMonth: earliest,
              decorate: (DateTime day) {
                final Tally t = analytics.tally(
                  selected,
                  data.completions,
                  day,
                  day,
                );
                if (!t.hasData) return const DayDecoration();
                final double r = t.rate;
                return DayDecoration(
                  fill: AppColors.gold.withAlpha((40 + r * 215).round()),
                  textColor: r > 0.5 ? Colors.black : Colors.white,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  int _milestoneCount() => kMilestones.length;

  Widget _habitChips(List<Habit> active, Habit? chosen) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
            child: TickChip(
              label: 'All habits',
              selected: chosen == null,
              onTap: () => setState(() => _habitId = null),
            ),
          ),
          for (final Habit h in active)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
              child: TickChip(
                label: h.title,
                icon: h.icon,
                selected: chosen?.id == h.id,
                onTap: () => setState(() => _habitId = h.id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _rangeChips() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: <Widget>[
          for (final AnalyticsRange r in AnalyticsRange.values)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
              child: TickChip(
                label: r.label,
                selected: _range == r,
                filledWhenSelected: true,
                onTap: () => setState(() => _range = r),
              ),
            ),
        ],
      ),
    );
  }

  Widget _summaryRow(PeriodSummary s) {
    final String detail = s.tally.hasData
        ? '${s.tally.completed.round()} / ${s.tally.expected.round()}'
        : '-';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(s.label)),
          Text(
            detail,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          SizedBox(
            width: 56,
            child: Text(
              s.tally.hasData ? percentLabel(s.tally.rate) : '-',
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _streakRow(Habit h, HabitStats s) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Icon(h.icon, color: h.color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(h.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Text(
            '${s.currentStreak} / ${s.bestStreak} days',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
