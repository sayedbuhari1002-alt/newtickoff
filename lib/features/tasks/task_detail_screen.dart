import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/logic/task_engine.dart';
import '../../domain/models/models.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../state/app_data.dart';
import '../../state/app_state.dart';

class TaskDetailScreen extends ConsumerWidget {
  const TaskDetailScreen({super.key, required this.taskId});
  final String taskId;

  Future<void> _editProgress(BuildContext context, WidgetRef ref, Task task) async {
    final TextEditingController value = TextEditingController(text: task.progressValue.toString());
    final double? result = await showDialog<double>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Update task progress'),
        content: TextField(
          controller: value,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: task.progressMode == TaskProgressMode.percentage ? 'Completed percentage (0–100)' : 'Completed count (target ${task.progressTarget})',
            helperText: task.progressMode == TaskProgressMode.count && task.progressUnit.isNotEmpty ? 'Unit: ${task.progressUnit}' : null,
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            final double? parsed = double.tryParse(value.text.trim());
            if (parsed != null && parsed >= 0 && parsed <= task.progressTarget) Navigator.pop(dialogContext, parsed);
          }, child: const Text('Save Progress')),
        ],
      ),
    );
    value.dispose();
    if (result != null) {
      await ref.read(appDataProvider.notifier).updateTaskProgress(task.id, result);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<AppData> async = ref.watch(appDataProvider);
    final bool canPop = context.canPop();
    void goBack() {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(AppRoutes.dashboard);
      }
    }
    final Widget backButton = IconButton(
      tooltip: 'Back',
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: goBack,
    );
    return PopScope<Object?>(
      canPop: canPop,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop && !canPop && context.mounted) {
          context.go(AppRoutes.dashboard);
        }
      },
      child: async.when(
      loading: () => Scaffold(appBar: AppBar(leading: backButton), body: const Center(child: CircularProgressIndicator())),
      error: (Object error, StackTrace _) => Scaffold(appBar: AppBar(leading: backButton), body: Center(child: Text('$error'))),
      data: (AppData data) {
        final Task? task = data.taskById(taskId);
        if (task == null) return Scaffold(appBar: AppBar(leading: backButton), body: const Center(child: Text('This task is no longer available.')));
        final List<TaskActivity> history = data.activitiesForTask(task.id).reversed.toList();
        final List<Task> childTasks = data.childrenForTask(task.id);
        final bool isGroup = data.isGroupTask(task);
        final double groupProgress = data.progressForTask(task);
        final Color accent = Color(task.colorValue);
        final bool overdue = isTaskOverdueOnDate(task, DateTime.now());
        return Scaffold(
          appBar: AppBar(
            leading: backButton,
            title: const Text('Task Details'),
            actions: <Widget>[
              PopupMenuButton<String>(
                tooltip: 'Task actions',
                onSelected: (String value) async {
                  switch (value) {
                    case 'progress':
                      if (task.taskType == TaskType.progressive && !isGroup) { await _editProgress(context, ref, task); }
                      else { context.push(AppRoutes.taskProgress(task.id)); }
                      break;
                    case 'edit': context.push(AppRoutes.taskEdit(task.id)); break;
                    case 'pause': await ref.read(appDataProvider.notifier).setTaskPaused(task.id, !task.isPaused); break;
                    case 'postpone_day': await ref.read(appDataProvider.notifier).postponeTask(task.id, days: 1); break;
                    case 'postpone_week': await ref.read(appDataProvider.notifier).postponeTask(task.id, days: 7); break;
                    case 'duplicate':
                      final Task? copy = await ref.read(appDataProvider.notifier).duplicateTask(task.id);
                      if (copy != null && context.mounted) context.push(AppRoutes.taskDetail(copy.id));
                      break;
                    case 'delete':
                      bool deleteChildren = false;
                      bool confirmed = false;
                      if (isGroup && childTasks.isNotEmpty) {
                        final String? choice = await showDialog<String>(context: context, builder: (BuildContext dialogContext) => AlertDialog(
                          title: const Text('Delete parent task?'),
                          content: const Text('Choose what should happen to its child tasks.'),
                          actions: <Widget>[
                            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(dialogContext, 'keep'), child: const Text('Keep children as tasks')),
                            FilledButton(onPressed: () => Navigator.pop(dialogContext, 'all'), child: const Text('Delete all')),
                          ],
                        ));
                        confirmed = choice != null;
                        deleteChildren = choice == 'all';
                      } else {
                        confirmed = await showConfirmDialog(context, title: 'Delete task?', message: 'The task will be removed from your task list. Its recorded activity will remain available to analytics.');
                      }
                      if (confirmed && context.mounted) { await ref.read(appDataProvider.notifier).deleteTask(task.id, deleteChildren: deleteChildren); if (context.mounted) context.pop(); }
                      break;
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  if (!isGroup) PopupMenuItem(value: 'progress', child: ListTile(leading: Icon(task.taskType == TaskType.progressive ? Icons.trending_up_rounded : Icons.insights_outlined), title: Text(task.taskType == TaskType.progressive ? 'Update Progress' : 'Task Analytics'), contentPadding: EdgeInsets.zero)),
                  const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit'), contentPadding: EdgeInsets.zero)),
                  PopupMenuItem(value: 'pause', child: ListTile(leading: Icon(task.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded), title: Text(task.isPaused ? 'Resume' : 'Pause'), contentPadding: EdgeInsets.zero)),
                  const PopupMenuItem(value: 'postpone_day', child: ListTile(leading: Icon(Icons.event_repeat_rounded), title: Text('Postpone 1 day'), contentPadding: EdgeInsets.zero)),
                  const PopupMenuItem(value: 'postpone_week', child: ListTile(leading: Icon(Icons.date_range_rounded), title: Text('Postpone 1 week'), contentPadding: EdgeInsets.zero)),
                  const PopupMenuItem(value: 'duplicate', child: ListTile(leading: Icon(Icons.copy_rounded), title: Text('Duplicate'), contentPadding: EdgeInsets.zero)),
                  const PopupMenuDivider(),
                  PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline_rounded, color: AppColors.danger), title: Text('Delete'), contentPadding: EdgeInsets.zero)),
                ],
              ),
            ],
          ),
          body: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(18, 6, 18, 28), children: <Widget>[
            Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: accent.withValues(alpha: 0.55))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Row(children: <Widget>[
                Container(width: 42, height: 42, decoration: BoxDecoration(color: accent.withValues(alpha: 0.20), borderRadius: BorderRadius.circular(13)), child: Icon(_taskIcon(task.iconKey), color: accent)),
                const SizedBox(width: 12),
                Expanded(child: Text(task.title, style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, decoration: task.isCompleted ? TextDecoration.lineThrough : null))),
              ]),
              if (task.description.trim().isNotEmpty) ...<Widget>[const SizedBox(height: 12), Text(task.description, style: TextStyle(color: AppColors.textSecondary, height: 1.4))],
              const SizedBox(height: 15),
              Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                _StatusPill(label: task.isCompleted ? 'Completed' : task.isPaused ? 'Paused' : overdue ? 'Overdue' : 'Incomplete', color: task.isCompleted ? const Color(0xFF81C784) : task.isPaused ? AppColors.textSecondary : overdue ? AppColors.danger : accent),
                _StatusPill(label: '${task.priority.name[0].toUpperCase()}${task.priority.name.substring(1)} priority', color: task.priority == TaskPriority.high ? AppColors.danger : task.priority == TaskPriority.medium ? AppColors.gold : AppColors.textSecondary),
                if (task.category.isNotEmpty) _StatusPill(label: task.category, color: AppColors.textSecondary),
              ]),
            ])),
            if (task.parentTaskId != null && data.taskById(task.parentTaskId!) != null) ...<Widget>[
              const SizedBox(height: 10),
              ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.folder_open_rounded), title: const Text('Parent task'), subtitle: Text(data.taskById(task.parentTaskId!)!.title), onTap: () => context.push(AppRoutes.taskDetail(task.parentTaskId!)),),
            ],
            const SizedBox(height: 18),
            _DetailRow(icon: Icons.event_outlined, title: 'Deadline', value: _dateLabel(context, task.dueAt)),
            _DetailRow(icon: Icons.notifications_none_rounded, title: 'Reminder', value: _dateLabel(context, task.reminderAt)),
            _DetailRow(icon: Icons.repeat_rounded, title: 'Repeat', value: switch (task.repeat) { TaskRepeat.none => 'Does not repeat', TaskRepeat.daily => 'Every day', TaskRepeat.weekly => 'Every week', TaskRepeat.monthly => 'Every month' }),
            _DetailRow(icon: Icons.calendar_today_outlined, title: 'Created', value: _dateLabel(context, task.createdAt)),
            const SizedBox(height: 12),
            if (task.taskType == TaskType.progressive && !isGroup) ...<Widget>[
              const SizedBox(height: 12),
              Row(children: <Widget>[
                Expanded(child: Text('Progress · ${task.progressDisplay}', style: const TextStyle(fontWeight: FontWeight.w700))),
                Text('${task.difficultyScore.toStringAsFixed(task.difficultyScore == task.difficultyScore.roundToDouble() ? 0 : 1)} difficulty', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ]),
              const SizedBox(height: 8),
              ClipRRect(borderRadius: BorderRadius.circular(5), child: LinearProgressIndicator(value: task.progressPercent / 100, minHeight: 8, backgroundColor: AppColors.border, color: accent)),
              const SizedBox(height: 10),
              FilledButton.icon(onPressed: task.isPaused ? null : () => _editProgress(context, ref, task), icon: const Icon(Icons.trending_up_rounded), label: const Text('Update Progress')),
            ] else if (!isGroup) ...<Widget>[
              Row(children: <Widget>[
                Expanded(child: FilledButton.icon(onPressed: task.isPaused && !task.isCompleted ? null : task.isCompleted ? () => ref.read(appDataProvider.notifier).setTaskCompleted(task.id, false) : task.subtasks.any((Subtask s) => !s.isCompleted) ? null : () => ref.read(appDataProvider.notifier).setTaskCompleted(task.id, true), icon: Icon(task.isCompleted ? Icons.undo_rounded : Icons.check_rounded), label: Text(task.isCompleted ? 'Reopen Task' : 'Mark Complete'))),
                const SizedBox(width: 10),
                OutlinedButton.icon(onPressed: () => context.push(AppRoutes.taskEdit(task.id)), icon: const Icon(Icons.edit_outlined), label: const Text('Edit')),
              ]),
            ] else ...<Widget>[
              const SizedBox(height: 12),
              Text('Parent group · ${childTasks.length} child task(s)', style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              ClipRRect(borderRadius: BorderRadius.circular(5), child: LinearProgressIndicator(value: groupProgress, minHeight: 8, backgroundColor: AppColors.border, color: AppColors.gold)),
              const SizedBox(height: 8),
              Row(children: <Widget>[Expanded(child: OutlinedButton.icon(onPressed: () => context.push(AppRoutes.taskEdit(task.id)), icon: const Icon(Icons.edit_outlined), label: const Text('Edit Parent')))]),
            ],
            if (task.taskType == TaskType.progressive && !isGroup) ...<Widget>[
              const SizedBox(height: 24),
              const Text('Progress History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (data.progressHistoryForTask(task.id).isEmpty)
                Text('No progress changes recorded yet.', style: TextStyle(color: AppColors.textSecondary))
              else
                for (final TaskProgressEvent event in data.progressHistoryForTask(task.id).reversed.take(20))
                  ListTile(
                    dense: true, contentPadding: EdgeInsets.zero,
                    leading: Icon(event.progressDelta >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded, color: event.progressDelta >= 0 ? AppColors.gold : AppColors.danger, size: 19),
                    title: Text('${event.previousPercent.toStringAsFixed(0)}% → ${event.newPercent.toStringAsFixed(0)}%  (${event.progressDelta >= 0 ? '+' : ''}${event.progressDelta.toStringAsFixed(1)}%)'),
                    subtitle: Text('${event.occurredAt.day}/${event.occurredAt.month}/${event.occurredAt.year} · ${TimeOfDay.fromDateTime(event.occurredAt).format(context)}'),
                  ),
            ],
            if (childTasks.isNotEmpty) ...<Widget>[
              const SizedBox(height: 24),
              Row(children: <Widget>[const Expanded(child: Text('Child Tasks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))), Text('${childTasks.where((Task child) => child.isCompleted).length}/${childTasks.length}', style: TextStyle(color: AppColors.textSecondary))]),
              const SizedBox(height: 8),
              ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: groupProgress, minHeight: 6, color: AppColors.gold, backgroundColor: AppColors.border)),
              const SizedBox(height: 8),
              for (final Task child in childTasks)
                Card(color: AppColors.surface, child: ListTile(
                  leading: Icon(child.isCompleted ? Icons.check_circle_rounded : child.taskType == TaskType.progressive ? Icons.trending_up_rounded : Icons.circle_outlined, color: child.isCompleted ? AppColors.gold : AppColors.textSecondary),
                  title: Text(child.title, style: TextStyle(decoration: child.isCompleted ? TextDecoration.lineThrough : null)),
                  subtitle: Text(child.taskType == TaskType.progressive ? '${child.progressDisplay} · ${child.priority.name} priority' : '${child.priority.name} priority${child.dueAt == null ? '' : ' · Due ${_dateLabel(context, child.dueAt)}'}'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(AppRoutes.taskDetail(child.id)),
                )),
            ],
            if (task.subtasks.isNotEmpty) ...<Widget>[
              const SizedBox(height: 26),
              Row(children: <Widget>[const Expanded(child: Text('Subtasks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))), Text('${task.completedSubtasks}/${task.subtasks.length}', style: TextStyle(color: AppColors.textSecondary))]),
              const SizedBox(height: 10),
              ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: task.subtaskProgress, minHeight: 5, color: accent, backgroundColor: AppColors.border)),
              const SizedBox(height: 6),
              for (final Subtask subtask in task.subtasks)
                Card(color: AppColors.surface, child: CheckboxListTile(
                  key: ValueKey<String>('subtask-${subtask.id}'), value: subtask.isCompleted,
                  onChanged: task.isPaused || task.isCompleted ? null : (_) => ref.read(appDataProvider.notifier).toggleSubtask(task.id, subtask.id),
                  title: Text(subtask.title, style: TextStyle(decoration: subtask.isCompleted ? TextDecoration.lineThrough : null)),
                  subtitle: Text(subtask.dueAt == null ? 'No independent deadline' : 'Due ${_dateLabel(context, subtask.dueAt)}${!subtask.isCompleted && subtask.dueAt!.isBefore(DateTime.now()) ? ' · Overdue' : ''}'),
                  controlAffinity: ListTileControlAffinity.leading,
                )),
            ],
            if (task.notes.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 24), const Text('Notes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(height: 8),
              Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)), child: Text(task.notes, style: const TextStyle(height: 1.4))),
            ],
            if (task.photoPaths.isNotEmpty || task.audioPaths.isNotEmpty) ...<Widget>[
              const SizedBox(height: 24), const Text('Attachments', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(height: 8),
              for (final String path in task.photoPaths) _PhotoAttachmentTile(path: path),
              for (final String path in task.audioPaths) _AudioAttachmentTile(path: path),
            ],
            const SizedBox(height: 26),
            const Text('Activity History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (history.isEmpty) Text('Activity is recorded as you create and update this task.', style: TextStyle(color: AppColors.textSecondary)),
            for (final TaskActivity event in history.take(20))
              ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(_eventIcon(event.eventType), color: AppColors.textSecondary, size: 19), title: Text(_eventLabel(event.eventType)), subtitle: Text('${event.occurredAt.day}/${event.occurredAt.month}/${event.occurredAt.year} · ${TimeOfDay.fromDateTime(event.occurredAt).format(context)}')),
          ])),
        );
      },
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.title, required this.value});
  final IconData icon; final String title; final String value;
  @override
  Widget build(BuildContext context) => ListTile(contentPadding: EdgeInsets.zero, leading: Icon(icon, color: AppColors.textSecondary), title: Text(title, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)), subtitle: Text(value, style: TextStyle(fontSize: 15, color: AppColors.textPrimary)));
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color}); final String label; final Color color;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(9)), child: Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700)));
}

String _dateLabel(BuildContext context, DateTime? value) {
  if (value == null) return 'Not set';
  final String date = '${value.day} ${const <String>['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][value.month - 1]} ${value.year}';
  if (value.hour == 0 && value.minute == 0) return date;
  return '$date · ${TimeOfDay.fromDateTime(value).format(context)}';
}

IconData _taskIcon(String key) => switch (key) { 'study' => Icons.menu_book_rounded, 'work' => Icons.work_outline_rounded, 'personal' => Icons.favorite_border_rounded, 'fitness' => Icons.fitness_center_rounded, _ => Icons.task_alt_rounded };
IconData _eventIcon(String type) => type.contains('completed') ? Icons.check_circle_outline_rounded : type.contains('deleted') ? Icons.delete_outline_rounded : type.contains('created') ? Icons.add_circle_outline_rounded : type.contains('paused') ? Icons.pause_circle_outline_rounded : Icons.edit_outlined;
String _eventLabel(String type) => switch (type) {
  'task_created' => 'Task created', 'task_updated' => 'Task updated', 'task_progress_updated' => 'Progress updated', 'task_moved_to_group' => 'Moved into parent task', 'task_removed_from_group' => 'Removed from parent task', 'task_group_completed_automatic' => 'Parent group completed', 'task_group_reopened_automatic' => 'Parent group reopened', 'deadline_changed' => 'Deadline changed', 'task_completed' => 'Task completed', 'task_reopened' => 'Task reopened', 'task_completed_automatic' => 'Completed automatically after subtasks', 'task_reopened_automatic' => 'Reopened after a subtask changed', 'task_paused' => 'Task paused', 'task_resumed' => 'Task resumed', 'task_postponed' => 'Task postponed', 'task_duplicated' => 'Task duplicated', 'task_deleted' => 'Task deleted', 'subtask_created' => 'Subtask added', 'subtask_updated' => 'Subtask updated', 'subtask_deleted' => 'Subtask removed', 'subtask_completed' => 'Subtask completed', 'subtask_reopened' => 'Subtask reopened', _ => type.replaceAll('_', ' '),
};


class _PhotoAttachmentTile extends StatelessWidget {
  const _PhotoAttachmentTile({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final File file = File(path);
    if (!file.existsSync()) {
      return const ListTile(
        leading: Icon(Icons.broken_image_outlined),
        title: Text('Photo is unavailable'),
        subtitle: Text('The local attachment file could not be found.'),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            file,
            fit: BoxFit.cover,
            width: double.infinity,
            height: 220,
            errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                const SizedBox(height: 80, child: Center(child: Text('Could not display this photo.'))),
          ),
        ),
        const SizedBox(height: 4),
        Text(path.split(Platform.pathSeparator).last, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ]),
    );
  }
}

class _AudioAttachmentTile extends StatefulWidget {
  const _AudioAttachmentTile({required this.path});
  final String path;

  @override
  State<_AudioAttachmentTile> createState() => _AudioAttachmentTileState();
}

class _AudioAttachmentTileState extends State<_AudioAttachmentTile> {
  late final AudioPlayer _player;
  late final StreamSubscription<void> _completionSubscription;
  bool _playing = false;
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _completionSubscription = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _completionSubscription.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (!File(widget.path).existsSync()) {
      setState(() => _unavailable = true);
      return;
    }
    try {
      if (_playing) {
        await _player.pause();
        if (mounted) setState(() => _playing = false);
      } else {
        await _player.play(DeviceFileSource(widget.path));
        if (mounted) setState(() => _playing = true);
      }
    } catch (_) {
      if (mounted) setState(() { _playing = false; _unavailable = true; });
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(_unavailable ? Icons.audio_file_outlined : Icons.graphic_eq_rounded),
        title: Text(_unavailable ? 'Audio is unavailable' : 'Audio recording'),
        subtitle: Text(_unavailable ? 'The local recording could not be opened.' : widget.path.split(Platform.pathSeparator).last, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: IconButton(
          tooltip: _playing ? 'Pause recording' : 'Play recording',
          onPressed: _unavailable ? null : _toggle,
          icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
        ),
      );
}
