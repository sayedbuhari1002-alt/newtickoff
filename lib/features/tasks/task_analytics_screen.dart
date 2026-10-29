import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/logic/task_engine.dart';
import '../../domain/models/models.dart';
import '../../state/app_data.dart';
import '../../state/app_state.dart';

enum _Range { day, week, month, days30, days90, year, custom }

class TaskAnalyticsScreen extends ConsumerStatefulWidget {
  const TaskAnalyticsScreen({super.key, this.taskId});
  final String? taskId;
  @override
  ConsumerState<TaskAnalyticsScreen> createState() => _TaskAnalyticsScreenState();
}

class _TaskAnalyticsScreenState extends ConsumerState<TaskAnalyticsScreen> {
  _Range _range = _Range.days30;
  DateTime _selectedDay = DateTime.now();
  DateTimeRange? _custom;

  Future<void> _selectCustomRange() async {
    final DateTime now = DateTime.now();
    final DateTimeRange? value = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _custom ?? DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
    );
    if (value != null && mounted) setState(() { _custom = value; _range = _Range.custom; });
  }

  DateTimeRange _getRange() {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    switch (_range) {
      case _Range.day: return DateTimeRange(start: _selectedDay, end: _selectedDay);
      case _Range.week:
        final DateTime start = DateTime(today.year, today.month, today.day - (today.weekday - 1));
        return DateTimeRange(start: start, end: DateTime(start.year, start.month, start.day + 6));
      case _Range.month: return DateTimeRange(start: DateTime(today.year, today.month, 1), end: DateTime(today.year, today.month + 1, 0));
      case _Range.days30: return DateTimeRange(start: DateTime(today.year, today.month, today.day - 29), end: today);
      case _Range.days90: return DateTimeRange(start: DateTime(today.year, today.month, today.day - 89), end: today);
      case _Range.year: return DateTimeRange(start: DateTime(today.year - 1, today.month, today.day + 1), end: today);
      case _Range.custom: return _custom ?? DateTimeRange(start: DateTime(today.year, today.month, 1), end: today);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppData? data = ref.watch(appDataProvider).valueOrNull;
    if (data == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final Task? selectedTask = widget.taskId == null ? null : data.taskById(widget.taskId!);
    final List<Task> tasks = selectedTask == null ? data.tasks : <Task>[selectedTask];
    final List<TaskActivity> activities = widget.taskId == null ? data.taskActivities : data.activitiesForTask(widget.taskId!);
    final DateTimeRange range = _getRange();
    final TaskAnalyticsEngine engine = const TaskAnalyticsEngine();
    final TaskAnalyticsSummary summary = engine.summarize(activities: activities, currentTasks: tasks, start: range.start, end: range.end);
    final TaskDayBreakdown? dayBreakdown = _range == _Range.day
        ? engine.breakdownForDay(activities: activities, currentTasks: tasks, day: _selectedDay)
        : null;
    final String heading = selectedTask == null ? 'Task Analytics' : 'Task Progress';
    return Scaffold(
      appBar: AppBar(title: Text(heading)),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: <Widget>[
        if (selectedTask != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(selectedTask.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
        Wrap(spacing: 6, runSpacing: 8, children: <Widget>[
          _RangeChip(label: 'Day', selected: _range == _Range.day, onTap: () => setState(() { _range = _Range.day; _selectedDay = DateTime.now(); })),
          _RangeChip(label: 'Week', selected: _range == _Range.week, onTap: () => setState(() => _range = _Range.week)),
          _RangeChip(label: 'Month', selected: _range == _Range.month, onTap: () => setState(() => _range = _Range.month)),
          _RangeChip(label: '30 days', selected: _range == _Range.days30, onTap: () => setState(() => _range = _Range.days30)),
          _RangeChip(label: '90 days', selected: _range == _Range.days90, onTap: () => setState(() => _range = _Range.days90)),
          _RangeChip(label: '1 year', selected: _range == _Range.year, onTap: () => setState(() => _range = _Range.year)),
          _RangeChip(label: 'Custom', selected: _range == _Range.custom, onTap: _selectCustomRange),
        ]),
        const SizedBox(height: 12),
        if (_range == _Range.day) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.calendar_today_outlined), title: const Text('Selected day'), subtitle: Text(_dateLabel(_selectedDay)), trailing: const Icon(Icons.chevron_right_rounded), onTap: () async {
          final DateTime? day = await showDatePicker(context: context, initialDate: _selectedDay, firstDate: DateTime(2000), lastDate: DateTime(DateTime.now().year + 1));
          if (day != null && mounted) setState(() => _selectedDay = day);
        }),
        if (_range == _Range.custom) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('${_dateLabel(range.start)} – ${_dateLabel(range.end)}', style: const TextStyle(color: AppColors.textSecondary))),
        GridView.count(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: 1.7, children: <Widget>[
          _MetricCard(label: 'Total tasks', value: '${summary.totalTasks}', icon: Icons.checklist_rounded),
          _MetricCard(label: 'Completed', value: '${summary.completedTasks}', icon: Icons.task_alt_rounded),
          _MetricCard(label: 'Incomplete', value: '${summary.incompleteTasks}', icon: Icons.pending_actions_rounded),
          _MetricCard(label: 'Overdue', value: '${summary.overdueTasks}', icon: Icons.warning_amber_rounded, accent: AppColors.danger),
          _MetricCard(label: 'Completion', value: '${summary.completionPercent.toStringAsFixed(1)}%', icon: Icons.donut_large_rounded),
          _MetricCard(label: 'On time', value: '${summary.onTimePercent.toStringAsFixed(1)}%', icon: Icons.schedule_rounded),
          _MetricCard(label: 'Weighted score', value: summary.weightedScore.toStringAsFixed(1), icon: Icons.stars_rounded),
          _MetricCard(label: 'Current / best streak', value: '${summary.currentStreak} / ${summary.bestStreak}', icon: Icons.local_fire_department_rounded),
        ]),
        const SizedBox(height: 24),
        const Text('Daily completions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        const Text('Completed tasks and subtasks are attributed to the date they were completed. Automatically completed parents are excluded when child completions already represent the work.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35)),
        const SizedBox(height: 16),
        Container(height: 165, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)), child: _CompletionBars(days: summary.days, onSelectDay: (DateTime day) => setState(() { _selectedDay = day; _range = _Range.day; }))),
        const SizedBox(height: 24),
        const Text('Completion trend', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Container(height: 150, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)), child: _TrendLineChart(values: summary.days.map((TaskDayAnalytics d) => d.workUnits.toDouble()).toList())),
        const SizedBox(height: 24),
        const Text('Completed versus incomplete', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        _ComparisonChart(firstLabel: 'Completed', firstValue: summary.completedTasks, secondLabel: 'Incomplete', secondValue: summary.incompleteTasks),
        const SizedBox(height: 24),
        const Text('On-time versus late completions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        _ComparisonChart(firstLabel: 'On time', firstValue: math.max(0, summary.days.fold<int>(0, (int sum, TaskDayAnalytics d) => sum + d.workUnits) - summary.days.fold<int>(0, (int sum, TaskDayAnalytics d) => sum + d.lateCompletions)).toInt(), secondLabel: 'Late', secondValue: summary.days.fold<int>(0, (int sum, TaskDayAnalytics d) => sum + d.lateCompletions)),
        const SizedBox(height: 24),
        const Text('Weighted score trend', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Container(height: 130, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)), child: _TrendLineChart(values: summary.days.map((TaskDayAnalytics d) => d.weightedScore).toList())),
        if (dayBreakdown != null) ...<Widget>[
          const SizedBox(height: 24),
          Text('Selected-day status · ${_dateLabel(_selectedDay)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          _HistorySection(title: 'Tasks scheduled', items: dayBreakdown.scheduledTasks),
          _HistorySection(title: 'Tasks pending', items: dayBreakdown.pendingTasks),
          _HistorySection(title: 'Tasks overdue', items: dayBreakdown.overdueTasks),
          _HistorySection(title: 'Subtasks completed that day', items: dayBreakdown.completedSubtasks),
          _HistorySection(title: 'Subtasks incomplete', items: dayBreakdown.incompleteSubtasks),
          _HistorySection(title: 'Subtasks overdue', items: dayBreakdown.overdueSubtasks),
        ],
        const SizedBox(height: 24),
        const Text('Daily breakdown', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final TaskDayAnalytics day in summary.days.reversed.take(14))
          Card(color: AppColors.surface, child: ListTile(
            title: Text(_dateLabel(day.day)),
            subtitle: Text('${day.taskCompletions} task(s) · ${day.subtaskCompletions} subtask(s) · ${day.lateCompletions} late completion(s)'),
            trailing: Text(day.weightedScore.toStringAsFixed(0), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.gold)),
            onTap: () => setState(() { _selectedDay = day.day; _range = _Range.day; }),
          )),
        if (summary.days.every((TaskDayAnalytics d) => d.workUnits == 0)) const Padding(padding: EdgeInsets.only(top: 8), child: Text('No completion activity was recorded in this range.', style: TextStyle(color: AppColors.textSecondary))),
      ]),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({required this.label, required this.selected, required this.onTap}); final String label; final bool selected; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap());
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, required this.icon, this.accent = AppColors.gold}); final String label; final String value; final IconData icon; final Color accent;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: <Widget>[
    Icon(icon, size: 20, color: accent), Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)), Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
  ]));
}

class _CompletionBars extends StatelessWidget {
  const _CompletionBars({required this.days, this.onSelectDay});

  final List<TaskDayAnalytics> days;
  final ValueChanged<DateTime>? onSelectDay;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty || days.every((TaskDayAnalytics day) => day.workUnits == 0)) {
      return const Center(
        child: Text('No chart data for this range', style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    final List<TaskDayAnalytics> shown = days.length > 31 ? days.sublist(days.length - 31) : days;
    final int maxValue = shown.fold<int>(
      1,
      (int max, TaskDayAnalytics day) => math.max(max, day.workUnits).toInt(),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        for (int i = 0; i < shown.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Tooltip(
                message: '${_dateLabel(shown[i].day)}: ${shown[i].workUnits}',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelectDay?.call(shown[i].day),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            height: 100 * shown[i].workUnits / maxValue + (shown[i].workUnits == 0 ? 1 : 0),
                            decoration: BoxDecoration(
                              color: shown[i].workUnits == 0 ? AppColors.border : AppColors.gold,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        (i == 0 || i == shown.length - 1 || (shown.length <= 14 && i % 2 == 0)) ? '${shown[i].day.day}' : '',
                        style: const TextStyle(fontSize: 8, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.title, required this.items});

  final String title;
  final List<TaskHistoryItem> items;

  @override
  Widget build(BuildContext context) => Card(
        color: AppColors.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('$title (${items.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('None', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                )
              else
                for (final TaskHistoryItem item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(item.isCompleted ? Icons.check_circle_outline_rounded : Icons.circle_outlined, size: 17, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Expanded(child: Text(item.title, style: const TextStyle(fontSize: 13))),
                        if (item.dueAt != null)
                          Text('${item.dueAt!.day}/${item.dueAt!.month}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      );
}

String _dateLabel(DateTime date) => '${date.day.toString().padLeft(2, '0')} ${const <String>['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][date.month - 1]} ${date.year}';


class _ComparisonChart extends StatelessWidget {
  const _ComparisonChart({required this.firstLabel, required this.firstValue, required this.secondLabel, required this.secondValue});
  final String firstLabel;
  final int firstValue;
  final String secondLabel;
  final int secondValue;

  @override
  Widget build(BuildContext context) {
    final int maxValue = math.max(1, math.max(firstValue, secondValue)).toInt();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
      child: Column(children: <Widget>[
        _ComparisonRow(label: firstLabel, value: firstValue, maxValue: maxValue, color: AppColors.gold),
        const SizedBox(height: 12),
        _ComparisonRow(label: secondLabel, value: secondValue, maxValue: maxValue, color: AppColors.danger),
      ]),
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({required this.label, required this.value, required this.maxValue, required this.color});
  final String label;
  final int value;
  final int maxValue;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[Expanded(child: Text(label, style: const TextStyle(fontSize: 13))), Text('$value', style: const TextStyle(fontWeight: FontWeight.w700))]),
        const SizedBox(height: 5),
        ClipRRect(borderRadius: BorderRadius.circular(5), child: LinearProgressIndicator(value: value / maxValue, color: color, backgroundColor: AppColors.border, minHeight: 8)),
      ]);
}

class _TrendLineChart extends StatelessWidget {
  const _TrendLineChart({required this.values});
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty || values.every((double value) => value == 0)) {
      return const Center(child: Text('No trend data for this range', style: TextStyle(color: AppColors.textSecondary)));
    }
    final List<double> shown = values.length > 31 ? values.sublist(values.length - 31) : values;
    return CustomPaint(
      painter: _TrendPainter(values: shown),
      child: const SizedBox.expand(),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({required this.values});
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.width <= 0 || size.height <= 0) return;
    final Paint grid = Paint()..color = AppColors.border..strokeWidth = 1;
    final Paint line = Paint()..color = AppColors.gold..strokeWidth = 2.5..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    final Paint point = Paint()..color = AppColors.gold..style = PaintingStyle.fill;
    for (int row = 1; row <= 3; row++) {
      final double y = size.height * row / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final double maximum = values.fold<double>(1, (double current, double value) => math.max(current, value).toDouble());
    final Path path = Path();
    final List<Offset> points = <Offset>[];
    for (int i = 0; i < values.length; i++) {
      final double x = values.length == 1 ? size.width / 2 : size.width * i / (values.length - 1);
      final double y = size.height - (values[i] / maximum) * (size.height - 8) - 4;
      final Offset offset = Offset(x, y);
      points.add(offset);
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    canvas.drawPath(path, line);
    for (final Offset offset in points) {
      canvas.drawCircle(offset, 3, point);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) => oldDelegate.values != values;
}
