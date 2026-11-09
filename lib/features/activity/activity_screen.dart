import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/models/models.dart';
import '../../state/app_data.dart';
import '../../state/app_state.dart';

class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<AppData> asyncData = ref.watch(appDataProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: asyncData.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) => Center(child: Text('$error')),
        data: (AppData data) {
          final List<TaskActivity> events = List<TaskActivity>.of(data.taskActivities)
            ..sort((TaskActivity a, TaskActivity b) => b.occurredAt.compareTo(a.occurredAt));
          if (events.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.history_rounded, size: 46, color: AppColors.textSecondary),
                    const SizedBox(height: 12),
                    const Text('No activity yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(
                      'Task creation, edits, progress changes and completions will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            itemCount: events.length,
            separatorBuilder: (BuildContext context, int index) => const Divider(height: 1, indent: 58),
            itemBuilder: (BuildContext context, int index) {
              final TaskActivity event = events[index];
              final Map<String, dynamic> snapshot = event.snapshot;
              final Task? task = data.taskById(event.taskId);
              final String taskTitle = (snapshot['title'] as String?) ?? task?.title ?? 'Deleted task';
              final bool isSubtask = event.entityType == 'subtask';
              final String itemTitle = isSubtask
                  ? (snapshot['subtaskTitle'] as String? ?? 'Subtask')
                  : taskTitle;
              final String eventTitle = _eventLabel(event.eventType);
              final String detail = isSubtask ? '$eventTitle · $taskTitle' : _eventDetail(event, snapshot);
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 5),
                leading: CircleAvatar(
                  backgroundColor: AppColors.surfaceRaised,
                  child: Icon(_eventIcon(event.eventType), color: _eventColor(event.eventType), size: 20),
                ),
                title: Text(itemTitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  '$detail\n${_dateTimeLabel(event.occurredAt)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.4),
                ),
                isThreeLine: true,
                onTap: task == null ? null : () => context.push('/task/${task.id}'),
              );
            },
          );
        },
      ),
    );
  }

  static String _eventLabel(String type) => switch (type) {
    'task_created' => 'Task created',
    'task_updated' => 'Task updated',
    'task_completed' => 'Task completed',
    'task_completed_automatic' => 'Task completed from subtasks',
    'task_reopened' => 'Task reopened',
    'task_paused' => 'Task paused',
    'task_resumed' => 'Task resumed',
    'task_postponed' => 'Task postponed',
    'task_scheduled' => 'Task scheduled',
    'task_duplicated' => 'Task duplicated',
    'deadline_changed' => 'Deadline changed',
    'task_progress_updated' => 'Progress updated',
    'subtask_created' => 'Subtask added',
    'subtask_updated' => 'Subtask updated',
    'subtask_completed' => 'Subtask completed',
    'subtask_reopened' => 'Subtask reopened',
    'subtask_deleted' => 'Subtask removed',
    'task_group_completed_automatic' => 'Task group completed',
    'task_group_reopened_automatic' => 'Task group reopened',
    'task_moved_to_group' => 'Task moved to a group',
    'task_removed_from_group' => 'Task removed from a group',
    'task_group_updated' => 'Task group updated',
    _ => type.replaceAll('_', ' '),
  };

  static String _eventDetail(TaskActivity event, Map<String, dynamic> snapshot) {
    if (event.eventType == 'task_progress_updated') {
      final double value = (snapshot['progressValue'] as num?)?.toDouble() ?? 0;
      final double target = (snapshot['progressTarget'] as num?)?.toDouble() ?? 100;
      final String unit = (snapshot['progressUnit'] as String? ?? '').trim();
      final String mode = snapshot['progressMode'] as String? ?? 'percentage';
      return mode == 'count'
          ? 'Progress: ${value.toStringAsFixed(0)} / ${target.toStringAsFixed(0)}${unit.isEmpty ? '' : ' $unit'}'
          : 'Progress: ${value.toStringAsFixed(0)}%';
    }
    if (event.eventType == 'deadline_changed') {
      final String? due = snapshot['dueAt'] as String?;
      return due == null ? 'Deadline removed' : 'Deadline: ${_dateOnly(DateTime.tryParse(due))}';
    }
    return _eventLabel(event.eventType);
  }

  static String _dateOnly(DateTime? value) {
    if (value == null) return 'Not set';
    return '${value.day}/${value.month}/${value.year}';
  }

  static String _dateTimeLabel(DateTime value) {
    final String hour = value.hour.toString().padLeft(2, '0');
    final String minute = value.minute.toString().padLeft(2, '0');
    return '${value.day}/${value.month}/${value.year} · $hour:$minute';
  }

  static IconData _eventIcon(String type) {
    if (type.contains('completed')) return Icons.check_circle_outline_rounded;
    if (type.contains('created')) return Icons.add_circle_outline_rounded;
    if (type.contains('deleted')) return Icons.delete_outline_rounded;
    if (type.contains('progress')) return Icons.trending_up_rounded;
    if (type.contains('paused')) return Icons.pause_circle_outline_rounded;
    if (type.contains('deadline') || type.contains('postponed') || type.contains('scheduled')) return Icons.event_outlined;
    return Icons.edit_note_rounded;
  }

  static Color _eventColor(String type) => type.contains('completed')
      ? AppColors.cyan
      : type.contains('deleted')
          ? AppColors.danger
          : AppColors.gold;
}
