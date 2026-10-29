import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/logic/task_engine.dart';
import '../../domain/models/models.dart';

class TaskCard extends StatelessWidget {
  const TaskCard({super.key, required this.task, required this.selectedDate, required this.onOpen, required this.onToggle, this.titleFontSize = 14});
  final Task task;
  final DateTime selectedDate;
  final VoidCallback onOpen;
  final ValueChanged<bool> onToggle;
  final double titleFontSize;

  @override
  Widget build(BuildContext context) {
    final Color accent = Color(task.colorValue);
    final bool overdue = isTaskOverdueOnDate(task, selectedDate);
    final bool blocked = task.subtasks.any((Subtask s) => !s.isCompleted);
    final String? dueLabel = task.dueAt == null ? null : '${task.dueAt!.day.toString().padLeft(2, '0')}/${task.dueAt!.month.toString().padLeft(2, '0')}/${task.dueAt!.year}${task.dueAt!.hour == 0 && task.dueAt!.minute == 0 ? '' : ' · ${TimeOfDay.fromDateTime(task.dueAt!).format(context)}'}';
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16), onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Tooltip(message: blocked ? 'Complete all subtasks first' : task.isCompleted ? 'Reopen task' : 'Complete task', child: Checkbox(value: task.isCompleted, onChanged: task.isPaused || blocked ? null : (bool? value) { if (value != null) onToggle(value); }, activeColor: accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)))),
            const SizedBox(width: 6),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Row(children: <Widget>[
                Expanded(child: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.w700, decoration: task.isCompleted ? TextDecoration.lineThrough : null, color: task.isCompleted ? AppColors.textSecondary : AppColors.textPrimary))),
                const SizedBox(width: 6),
                Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: switch (task.priority) { TaskPriority.high => AppColors.danger, TaskPriority.medium => AppColors.gold, TaskPriority.low => AppColors.textSecondary })),
              ]),
              if (task.description.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(task.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
                if (dueLabel != null) _MetaPill(icon: Icons.event_outlined, label: dueLabel, color: overdue ? AppColors.danger : AppColors.textSecondary),
                if (task.category.trim().isNotEmpty) _MetaPill(icon: Icons.label_outline_rounded, label: task.category, color: AppColors.textSecondary),
                if (task.isPaused) const _MetaPill(icon: Icons.pause_circle_outline_rounded, label: 'Paused', color: AppColors.textSecondary),
                if (overdue) const _MetaPill(icon: Icons.warning_amber_rounded, label: 'Overdue', color: AppColors.danger),
              ]),
              if (task.subtasks.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Row(children: <Widget>[
                  Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: task.subtaskProgress, minHeight: 5, backgroundColor: AppColors.border, color: accent))),
                  const SizedBox(width: 8),
                  Text('${task.completedSubtasks}/${task.subtasks.length}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ]),
              ],
            ])),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
          ]),
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
    Icon(icon, size: 13, color: color), const SizedBox(width: 4), Text(label, style: TextStyle(fontSize: 11, color: color)),
  ]);
}
