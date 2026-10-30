import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/logic/habit_engine.dart';
import '../../domain/models/models.dart';
import '../../shared/utils/format.dart';

/// A Build habit presented as the lowest display-priority item in the Tasks
/// list. Tick habits can be completed here; count/checklist habits open detail
/// so their method-specific tracking controls are used.
class HabitTaskCard extends StatelessWidget {
  const HabitTaskCard({
    super.key,
    required this.habit,
    required this.engine,
    required this.record,
    required this.onOpen,
    required this.onToggle,
  });

  final Habit habit;
  final HabitEngine engine;
  final CompletionRecord? record;
  final VoidCallback onOpen;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final bool completed = engine.isCompleted(habit, record);
    final bool quickToggle = habit.tracking == TrackingMethod.tick;
    final String trackingLabel = switch (habit.tracking) {
      TrackingMethod.tick => 'Build habit',
      TrackingMethod.count => countLabel(habit, record?.count ?? 0),
      TrackingMethod.checklist => 'Checklist · ${habit.checklist.length} items',
    };

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              if (quickToggle)
                Checkbox(
                  value: completed,
                  activeColor: Color(habit.colorValue),
                  checkColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                  onChanged: (bool? value) {
                    if (value != null) onToggle(value);
                  },
                )
              else
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Color(habit.colorValue).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.repeat_rounded, color: Color(habit.colorValue)),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      habit.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        decoration: completed ? TextDecoration.lineThrough : null,
                        color: completed ? AppColors.textSecondary : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceRaised,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: const Text(
                            'HABIT',
                            style: TextStyle(
                              fontSize: 9,
                              letterSpacing: 0.6,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            trackingLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}
