import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/logic/productivity_engine.dart';
import '../../domain/models/models.dart';
import '../../state/app_data.dart';
import '../../state/app_settings.dart';
import '../../state/app_state.dart';

/// Productivity analytics embedded in the unified Analytics destination.
/// Historical days are evaluated by ProductivityEngine, which preserves the
/// scoring model and snapshots associated with each historical date.
class ProductivityAnalyticsTab extends ConsumerStatefulWidget {
  const ProductivityAnalyticsTab({super.key});

  @override
  ConsumerState<ProductivityAnalyticsTab> createState() =>
      _ProductivityAnalyticsTabState();
}

enum _ProductivityRange { week, month, quarter, year }

class _ProductivityAnalyticsTabState
    extends ConsumerState<ProductivityAnalyticsTab> {
  _ProductivityRange _range = _ProductivityRange.month;

  @override
  Widget build(BuildContext context) {
    final AppData? data = ref.watch(appDataProvider).valueOrNull;
    if (data == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime start = switch (_range) {
      _ProductivityRange.week => today.subtract(const Duration(days: 6)),
      _ProductivityRange.month => today.subtract(const Duration(days: 29)),
      _ProductivityRange.quarter => today.subtract(const Duration(days: 89)),
      _ProductivityRange.year => DateTime(today.year, today.month - 11, 1),
    };

    final String? rawStart =
        data.settings[AppSettingKeys.productivityScoringStartDate];
    final DateTime? parsedStart =
        rawStart == null ? null : DateTime.tryParse(rawStart);
    final DateTime? scoringStart = parsedStart == null
        ? null
        : DateTime(parsedStart.year, parsedStart.month, parsedStart.day);
    final ProductivityEngine engine = const ProductivityEngine();
    final List<_DailyScore> daily = <_DailyScore>[];
    for (DateTime date = start;
        !date.isAfter(today);
        date = date.add(const Duration(days: 1))) {
      final ProductivityDayScore score = engine.calculateDay(
        date: date,
        target: data.targetForDate(date),
        habits: data.habits,
        completions: data.completions,
        tasks: data.tasks,
        activities: data.taskActivities,
        progressEvents: data.taskProgressEvents,
        assignments: const <Assignment>[],
        distractionCategories: data.distractionCategories,
        distractionLogs: data.distractionLogs,
        appUsageRecords: data.appUsageRecords,
        today: today,
        currentStateScoringStartDate: scoringStart,
      );
      daily.add(_DailyScore(date: date, score: score));
    }

    final List<_ScoreBucket> buckets = _makeBuckets(daily);
    final double earned = daily.fold<double>(
      0,
      (double total, _DailyScore day) => total + day.score.achievementPoints,
    );
    final double penalties = daily.fold<double>(
      0,
      (double total, _DailyScore day) => total + day.score.penaltyPoints,
    );
    final double net = daily.fold<double>(
      0,
      (double total, _DailyScore day) => total + day.score.netScore,
    );
    final double average = daily.isEmpty ? 0 : net / daily.length;
    final _DailyScore? best = daily.isEmpty
        ? null
        : daily.reduce((_DailyScore a, _DailyScore b) =>
            a.score.netScore >= b.score.netScore ? a : b);
    final Map<String, double> sourcePoints = <String, double>{};
    final Map<String, double> penaltyPoints = <String, double>{};
    for (final _DailyScore day in daily) {
      for (final ProductivityContribution contribution
          in day.score.contributions) {
        sourcePoints.update(
          contribution.kind,
          (double value) => value + contribution.points,
          ifAbsent: () => contribution.points,
        );
      }
      for (final ProductivityContribution penalty in day.score.penalties) {
        penaltyPoints.update(
          penalty.kind,
          (double value) => value + penalty.points,
          ifAbsent: () => penalty.points,
        );
      }
    }

    final List<MapEntry<String, double>> sortedSourcePoints = sourcePoints.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final List<MapEntry<String, double>> sortedPenaltyPoints = penaltyPoints.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final double firstHalfAverage = _halfAverage(daily, first: true);
    final double secondHalfAverage = _halfAverage(daily, first: false);
    final double trendDifference = secondHalfAverage - firstHalfAverage;
    final String trendLabel = daily.length < 2
        ? 'Not enough history to determine a trend'
        : trendDifference.abs() < 0.05
            ? 'Productivity is stable across this period'
            : trendDifference > 0
                ? 'Productivity is moving upward'
                : 'Productivity is moving downward';

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          _rangeSelector(),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.75,
            children: <Widget>[
              _MetricCard(
                title: 'Net points',
                value: net.toStringAsFixed(1),
                icon: Icons.stars_rounded,
              ),
              _MetricCard(
                title: 'Average per day',
                value: average.toStringAsFixed(1),
                icon: Icons.show_chart_rounded,
              ),
              _MetricCard(
                title: 'Points earned',
                value: earned.toStringAsFixed(1),
                icon: Icons.add_circle_outline_rounded,
              ),
              _MetricCard(
                title: 'Penalty points',
                value: penalties.toStringAsFixed(1),
                icon: Icons.remove_circle_outline_rounded,
                danger: true,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _Panel(
            title: 'Productivity trend',
            subtitle: trendLabel,
            child: SizedBox(
              height: 170,
              child: _LineScoreChart(
                values: buckets.map((_ScoreBucket bucket) => bucket.net).toList(),
                color: AppColors.gold,
                emptyMessage: 'No productivity trend is available yet.',
              ),
            ),
          ),
          const SizedBox(height: 14),
          _Panel(
            title: 'Points earned trend',
            subtitle: 'Positive points earned before penalties',
            child: SizedBox(
              height: 150,
              child: _LineScoreChart(
                values: buckets.map((_ScoreBucket bucket) => bucket.earned).toList(),
                color: AppColors.secondaryAccent,
                emptyMessage: 'No earned points are available for this period.',
              ),
            ),
          ),
          const SizedBox(height: 14),
          _Panel(
            title: 'Penalty points trend',
            subtitle: 'Points deducted from distractions and quit-habit slips',
            child: SizedBox(
              height: 150,
              child: _LineScoreChart(
                values: buckets.map((_ScoreBucket bucket) => bucket.penalty).toList(),
                color: AppColors.danger,
                emptyMessage: 'No penalty points are available for this period.',
              ),
            ),
          ),
          const SizedBox(height: 14),
          _Panel(
            title: _range == _ProductivityRange.week ||
                    _range == _ProductivityRange.month
                ? 'Daily productivity scores'
                : _range == _ProductivityRange.quarter
                    ? 'Weekly productivity scores'
                    : 'Monthly productivity scores',
            subtitle: 'Net points for each day or period',
            child: SizedBox(
              height: 184,
              child: _BarScoreChart(buckets: buckets),
            ),
          ),
          const SizedBox(height: 14),
          _Panel(
            title: 'Achievement points by source',
            subtitle: 'Where your earned productivity points came from',
            child: sourcePoints.isEmpty
                ? const _EmptyAnalyticsText(
                    text: 'No achievement points were recorded in this period.',
                  )
                : Column(
                    children: <Widget>[
                      for (final MapEntry<String, double> entry in sortedSourcePoints)
                        _BreakdownRow(
                          label: entry.key,
                          value: entry.value,
                          maximum: earned,
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 14),
          _Panel(
            title: 'Penalty breakdown',
            subtitle: 'Points deducted from quit-habit slips and distractions',
            child: penaltyPoints.isEmpty
                ? const _EmptyAnalyticsText(
                    text: 'No penalty points were recorded in this period.',
                  )
                : Column(
                    children: <Widget>[
                      for (final MapEntry<String, double> entry in sortedPenaltyPoints)
                        _BreakdownRow(
                          label: entry.key,
                          value: entry.value,
                          maximum: penalties,
                          danger: true,
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 14),
          _Panel(
            title: 'Best productivity day',
            subtitle: best == null
                ? 'No score data available yet'
                : '${_dateLabel(best.date)} · ${best.score.netScore.toStringAsFixed(1)} points',
            child: best == null
                ? const _EmptyAnalyticsText(
                    text: 'Complete tasks or habits to start building your history.',
                  )
                : Row(
                    children: <Widget>[
                      Icon(Icons.emoji_events_rounded,
                          color: AppColors.gold, size: 30),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${best.score.achievementPoints.toStringAsFixed(1)} earned · ${best.score.penaltyPoints.toStringAsFixed(1)} penalties',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            'Previous dates use their preserved historical scoring records. Changes to today’s tasks and habits affect today’s score, not earlier days.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rangeSelector() => Wrap(
        spacing: 7,
        runSpacing: 7,
        children: <Widget>[
          _RangeChip(
            label: '7 days',
            selected: _range == _ProductivityRange.week,
            onTap: () => setState(() => _range = _ProductivityRange.week),
          ),
          _RangeChip(
            label: '30 days',
            selected: _range == _ProductivityRange.month,
            onTap: () => setState(() => _range = _ProductivityRange.month),
          ),
          _RangeChip(
            label: '90 days',
            selected: _range == _ProductivityRange.quarter,
            onTap: () => setState(() => _range = _ProductivityRange.quarter),
          ),
          _RangeChip(
            label: '12 months',
            selected: _range == _ProductivityRange.year,
            onTap: () => setState(() => _range = _ProductivityRange.year),
          ),
        ],
      );

  List<_ScoreBucket> _makeBuckets(List<_DailyScore> days) {
    if (days.isEmpty) return const <_ScoreBucket>[];
    final List<List<_DailyScore>> groups = <List<_DailyScore>>[];
    if (_range == _ProductivityRange.week ||
        _range == _ProductivityRange.month) {
      groups.addAll(days.map((day) => <_DailyScore>[day]));
    } else if (_range == _ProductivityRange.quarter) {
      for (int i = 0; i < days.length; i += 7) {
        groups.add(days.skip(i).take(7).toList());
      }
    } else {
      final Map<String, List<_DailyScore>> byMonth = <String, List<_DailyScore>>{};
      for (final _DailyScore day in days) {
        final String key = '${day.date.year}-${day.date.month}';
        byMonth.putIfAbsent(key, () => <_DailyScore>[]).add(day);
      }
      groups.addAll(byMonth.values);
    }

    return groups.map((List<_DailyScore> group) {
      final DateTime from = group.first.date;
      final DateTime to = group.last.date;
      final double net = group.fold<double>(
        0,
        (double sum, _DailyScore item) => sum + item.score.netScore,
      );
      final double earned = group.fold<double>(
        0,
        (double sum, _DailyScore item) => sum + item.score.achievementPoints,
      );
      final double penalty = group.fold<double>(
        0,
        (double sum, _DailyScore item) => sum + item.score.penaltyPoints,
      );
      return _ScoreBucket(
        label: _bucketLabel(from, to),
        net: net,
        earned: earned,
        penalty: penalty,
      );
    }).toList();
  }

  double _halfAverage(List<_DailyScore> days, {required bool first}) {
    if (days.isEmpty) return 0;
    final int midpoint = days.length ~/ 2;
    final List<_DailyScore> part = first
        ? days.take(math.max(1, midpoint).toInt()).toList()
        : days.skip(midpoint).toList();
    if (part.isEmpty) return 0;
    return part.fold<double>(
          0,
          (double sum, _DailyScore day) => sum + day.score.netScore,
        ) /
        part.length;
  }
}

class _DailyScore {
  const _DailyScore({required this.date, required this.score});
  final DateTime date;
  final ProductivityDayScore score;
}

class _ScoreBucket {
  const _ScoreBucket({
    required this.label,
    required this.net,
    required this.earned,
    required this.penalty,
  });
  final String label;
  final double net;
  final double earned;
  final double penalty;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    this.danger = false,
  });
  final String title;
  final String value;
  final IconData icon;
  final bool danger;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Icon(icon, color: danger ? AppColors.danger : AppColors.gold, size: 19),
            Text(value,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            if (subtitle != null) ...<Widget>[
              const SizedBox(height: 3),
              Text(subtitle!,
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      );
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      );
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.value,
    required this.maximum,
    this.danger = false,
  });
  final String label;
  final double value;
  final double maximum;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final Color color = danger ? AppColors.danger : AppColors.gold;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
              Text(value.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: maximum <= 0 ? 0 : (value / maximum).clamp(0.0, 1.0).toDouble(),
              minHeight: 7,
              color: color,
              backgroundColor: AppColors.border,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyAnalyticsText extends StatelessWidget {
  const _EmptyAnalyticsText({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      );
}

class _LineScoreChart extends StatelessWidget {
  const _LineScoreChart({
    required this.values,
    required this.color,
    required this.emptyMessage,
  });
  final List<double> values;
  final Color color;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty || values.every((double value) => value == 0)) {
      return _EmptyAnalyticsText(text: emptyMessage);
    }
    return CustomPaint(
      painter: _LineScorePainter(values: values, color: color),
      child: const SizedBox.expand(),
    );
  }
}

class _LineScorePainter extends CustomPainter {
  const _LineScorePainter({required this.values, required this.color});
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.width <= 0 || size.height <= 0) return;
    final Paint grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    final Paint line = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Paint pointsPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (int row = 1; row <= 3; row++) {
      final double y = size.height * row / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final double maximum = values.fold<double>(
      1,
      (double value, double item) => math.max(value, item).toDouble(),
    );
    final Path path = Path();
    final List<Offset> points = <Offset>[];
    for (int i = 0; i < values.length; i++) {
      final double x = values.length == 1
          ? size.width / 2
          : size.width * i / (values.length - 1);
      final double y = size.height -
          (values[i] / maximum) * (size.height - 10) -
          5;
      final Offset point = Offset(x, y);
      points.add(point);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, line);
    for (final Offset point in points) {
      canvas.drawCircle(point, 3.2, pointsPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineScorePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

class _BarScoreChart extends StatelessWidget {
  const _BarScoreChart({required this.buckets});
  final List<_ScoreBucket> buckets;

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty || buckets.every((_ScoreBucket bucket) => bucket.net == 0)) {
      return const _EmptyAnalyticsText(text: 'No bar-chart data is available yet.');
    }
    final double maximum = buckets.fold<double>(
      1,
      (double current, _ScoreBucket bucket) => math.max(current, bucket.net).toDouble(),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        for (int index = 0; index < buckets.length; index++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Tooltip(
                message: '${buckets[index].label}: ${buckets[index].net.toStringAsFixed(1)} points',
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          height: buckets[index].net <= 0
                              ? 2
                              : 112 * buckets[index].net / maximum,
                          decoration: BoxDecoration(
                            color: buckets[index].net <= 0
                                ? AppColors.border
                                : AppColors.gold,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _showBarLabel(index, buckets.length)
                          ? buckets[index].label
                          : '',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(fontSize: 8, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  bool _showBarLabel(int index, int count) {
    if (count <= 7) return true;
    if (index == 0 || index == count - 1) return true;
    final int step = count <= 30 ? 5 : count <= 14 ? 2 : 3;
    return index % step == 0;
  }
}

String _bucketLabel(DateTime start, DateTime end) {
  if (start.year == end.year && start.month == end.month && start.day == end.day) {
    return '${start.day}';
  }
  if (start.month == end.month && start.year == end.year) {
    return '${start.day}-${end.day} ${_monthName(end.month)}';
  }
  return '${start.day} ${_monthName(start.month)}';
}

String _monthName(int month) => const <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ][month - 1];

String _dateLabel(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')} ${_monthName(date.month)} ${date.year}';
