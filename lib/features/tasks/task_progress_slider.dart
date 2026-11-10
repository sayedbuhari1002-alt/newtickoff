import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/models/models.dart';

/// A compact, direct-manipulation progress control for progressive tasks.
/// The slider is presented as a percentage, while count-based tasks are
/// converted back to their configured count/target before persistence.
class TaskProgressSlider extends StatefulWidget {
  const TaskProgressSlider({
    super.key,
    required this.task,
    required this.onProgressChanged,
    this.enabled = true,
    this.compact = false,
  });

  final Task task;
  final Future<void> Function(double value) onProgressChanged;
  final bool enabled;
  final bool compact;

  @override
  State<TaskProgressSlider> createState() => _TaskProgressSliderState();
}

class _TaskProgressSliderState extends State<TaskProgressSlider> {
  late double _percent;
  bool _dragging = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _percent = widget.task.progressPercent;
  }

  @override
  void didUpdateWidget(covariant TaskProgressSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    final double latest = widget.task.progressPercent;
    if (!_dragging && (!_saving || (latest - _percent).abs() < 0.05)) {
      _percent = latest;
    }
  }

  int get _divisions {
    final double target = widget.task.progressTarget;
    if (widget.task.progressMode == TaskProgressMode.count &&
        target >= 1 && target <= 1000 &&
        target == target.roundToDouble()) {
      return target.round();
    }
    return 100;
  }

  double _valueForPercent(double percent) {
    if (widget.task.progressMode == TaskProgressMode.count) {
      return widget.task.progressTarget * percent / 100;
    }
    return percent;
  }

  String _formatNumber(double value) {
    final double rounded = value.roundToDouble();
    return (value - rounded).abs() < 0.0001
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }

  String _displayForPercent(double percent) {
    if (widget.task.progressMode == TaskProgressMode.count) {
      final String unit = widget.task.progressUnit.trim();
      return '${_formatNumber(_valueForPercent(percent))} / ${_formatNumber(widget.task.progressTarget)}${unit.isEmpty ? '' : ' $unit'}';
    }
    return '${_formatNumber(percent)}%';
  }

  Future<void> _commit(double percent) async {
    if (!widget.enabled || _saving) return;
    final double value = _valueForPercent(percent).clamp(0, widget.task.progressTarget).toDouble();
    setState(() => _saving = true);
    try {
      await widget.onProgressChanged(value);
      if (!mounted) return;
      setState(() {
        _percent = percent;
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _percent = widget.task.progressPercent;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Color(widget.task.colorValue);
    final bool canChange = widget.enabled && !widget.task.isPaused && !_saving;
    final double value = _percent.clamp(0, 100).toDouble();
    final String display = _displayForPercent(value);
    final double verticalGap = widget.compact ? 1 : 5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(height: verticalGap),
        Row(
          children: <Widget>[
            Text(
              'Progress',
              style: TextStyle(
                fontSize: widget.compact ? 11 : 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const Spacer(),
            Text(
              display,
              key: const ValueKey<String>('task-progress-value'),
              style: TextStyle(
                fontSize: widget.compact ? 11 : 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            if (_saving) ...<Widget>[
              const SizedBox(width: 8),
              SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: accent,
                ),
              ),
            ],
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: widget.compact ? 3 : 4,
            activeTrackColor: accent,
            inactiveTrackColor: AppColors.border,
            thumbColor: accent,
            overlayColor: accent.withValues(alpha: 0.16),
            thumbShape: RoundSliderThumbShape(
              enabledThumbRadius: widget.compact ? 7 : 9,
            ),
            overlayShape: RoundSliderOverlayShape(
              overlayRadius: widget.compact ? 14 : 18,
            ),
          ),
          child: Slider(
            key: const ValueKey<String>('task-progress-slider'),
            min: 0,
            max: 100,
            divisions: _divisions,
            value: value,
            label: display,
            onChangeStart: canChange ? (_) => setState(() => _dragging = true) : null,
            onChanged: canChange
                ? (double next) => setState(() => _percent = next)
                : null,
            onChangeEnd: canChange
                ? (double next) {
                    setState(() => _dragging = false);
                    _commit(next);
                  }
                : null,
          ),
        ),
        if (widget.task.isPaused)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              'Resume this task to update its progress.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ),
      ],
    );
  }
}
