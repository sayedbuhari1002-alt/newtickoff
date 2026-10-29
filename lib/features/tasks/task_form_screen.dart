import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path_util;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/ids.dart';
import '../../domain/models/models.dart';
import '../../state/app_data.dart';
import '../../state/app_state.dart';

class TaskFormScreen extends ConsumerStatefulWidget {
  const TaskFormScreen({super.key, this.taskId});
  final String? taskId;

  @override
  ConsumerState<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends ConsumerState<TaskFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _category = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  DateTime? _dueAt;
  DateTime? _reminderAt;
  TaskPriority _priority = TaskPriority.medium;
  TaskRepeat _repeat = TaskRepeat.none;
  int _colorValue = 0xFFFFC857;
  String _iconKey = 'task';
  List<Subtask> _subtasks = <Subtask>[];
  List<String> _photoPaths = <String>[];
  List<String> _audioPaths = <String>[];
  final Set<String> _sessionAddedPaths = <String>{};
  bool _savedSuccessfully = false;
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  bool _initialised = false;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _category.dispose();
    _notes.dispose();
    unawaited(_finishRecorderAndCleanup());
    super.dispose();
  }

  Future<void> _finishRecorderAndCleanup() async {
    if (_recording) {
      try { await _recorder.cancel(); } catch (_) { /* already stopped or disposed */ }
    }
    if (!_savedSuccessfully) {
      for (final String path in _sessionAddedPaths) {
        try {
          final File file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) { /* Best-effort cleanup of an unsaved attachment. */ }
      }
    }
    try { await _recorder.dispose(); } catch (_) { /* Dispose is best effort. */ }
  }

  void _fill(Task task) {
    _title.text = task.title;
    _description.text = task.description;
    _category.text = task.category;
    _notes.text = task.notes;
    _dueAt = task.dueAt;
    _reminderAt = task.reminderAt;
    _priority = task.priority;
    _repeat = task.repeat;
    _colorValue = task.colorValue;
    _iconKey = task.iconKey;
    _subtasks = List<Subtask>.of(task.subtasks);
    _photoPaths = List<String>.of(task.photoPaths);
    _audioPaths = List<String>.of(task.audioPaths);
    _initialised = true;
  }

  Future<void> _chooseDueDate() async {
    final DateTime now = DateTime.now();
    final DateTime? day = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 15),
      helpText: 'Choose deadline',
    );
    if (day == null || !mounted) return;
    final DateTime? existing = _dueAt;
    _dueAt = DateTime(day.year, day.month, day.day, existing?.hour ?? 0, existing?.minute ?? 0);
    setState(() {});
  }

  Future<void> _chooseDueTime() async {
    if (_dueAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose a deadline date first.')));
      return;
    }
    final TimeOfDay? time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_dueAt!));
    if (time == null || !mounted) return;
    setState(() => _dueAt = DateTime(_dueAt!.year, _dueAt!.month, _dueAt!.day, time.hour, time.minute));
  }

  Future<void> _chooseReminder() async {
    final DateTime now = DateTime.now();
    final DateTime? day = await showDatePicker(
      context: context,
      initialDate: _reminderAt ?? _dueAt ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 15),
      helpText: 'Choose reminder date',
    );
    if (day == null || !mounted) return;
    final TimeOfDay initial = _reminderAt == null ? const TimeOfDay(hour: 9, minute: 0) : TimeOfDay.fromDateTime(_reminderAt!);
    final TimeOfDay? time = await showTimePicker(context: context, initialTime: initial);
    if (time == null || !mounted) return;
    setState(() => _reminderAt = DateTime(day.year, day.month, day.day, time.hour, time.minute));
  }

  Future<void> _editSubtasks() async {
    final List<Subtask>? result = await context.push<List<Subtask>>(
      AppRoutes.subtaskEditor,
      extra: List<Subtask>.of(_subtasks),
    );
    if (result != null && mounted) setState(() => _subtasks = result);
  }

  Future<Directory> _attachmentDirectory() async {
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory directory = Directory(path_util.join(docs.path, 'tickoff_attachments'));
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> _pickPhoto() async {
    try {
      final XFile? picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
      if (picked == null || !mounted) return;
      final Directory directory = await _attachmentDirectory();
      final String extension = path_util.extension(picked.path).isEmpty ? '.jpg' : path_util.extension(picked.path);
      final String target = path_util.join(directory.path, 'photo-${newId()}$extension');
      await File(picked.path).copy(target);
      if (!mounted) {
        try { await File(target).delete(); } catch (_) { /* Best-effort cleanup. */ }
        return;
      }
      _sessionAddedPaths.add(target);
      setState(() => _photoPaths.add(target));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not attach photo: $error')));
    }
  }

  Future<void> _toggleRecording() async {
    try {
      if (_recording) {
        final String? path = await _recorder.stop();
        if (mounted && path != null) setState(() { _audioPaths.add(path); _recording = false; });
      } else {
        final bool granted = await _recorder.hasPermission();
        if (!granted) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone permission is required to record audio.')));
          return;
        }
        final Directory directory = await _attachmentDirectory();
        final String path = path_util.join(directory.path, 'audio-${newId()}.m4a');
        _sessionAddedPaths.add(path);
        await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
        if (mounted) {
          setState(() { _recording = true; });
        } else {
          try { await _recorder.cancel(); } catch (_) { /* Recorder may have been disposed. */ }
          try { await File(path).delete(); } catch (_) { /* Best-effort cleanup. */ }
        }
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Audio recording failed: $error')));
    }
  }

  Future<void> _removeAttachment(String path) async {
    setState(() { _photoPaths.remove(path); _audioPaths.remove(path); });
    if (_sessionAddedPaths.remove(path)) {
      try {
        final File file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) { /* Removing an attachment from the form remains successful. */ }
    }
    // Existing saved files are cleaned by the repository state layer after a successful save.
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final DateTime now = DateTime.now();
    final AppData? data = ref.read(appDataProvider).valueOrNull;
    final Task? old = widget.taskId == null ? null : data?.taskById(widget.taskId!);
    final Task task = Task(
      id: old?.id ?? newId(),
      title: _title.text.trim(),
      description: _description.text.trim(),
      dueAt: _dueAt,
      reminderAt: _reminderAt,
      priority: _priority,
      category: _category.text.trim(),
      iconKey: _iconKey,
      colorValue: _colorValue,
      isCompleted: old?.isCompleted ?? false,
      completedAt: old?.completedAt,
      isPaused: old?.isPaused ?? false,
      repeat: _repeat,
      notes: _notes.text.trim(),
      photoPaths: List<String>.of(_photoPaths),
      audioPaths: List<String>.of(_audioPaths),
      subtasks: _subtasks,
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
    );
    try {
      await ref.read(appDataProvider.notifier).saveTask(task);
      _savedSuccessfully = true;
      _sessionAddedPaths.clear();
      if (mounted) context.go(AppRoutes.taskDetail(task.id));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppData? data = ref.watch(appDataProvider).valueOrNull;
    final Task? existing = widget.taskId == null ? null : data?.taskById(widget.taskId!);
    if (!_initialised && existing != null) _fill(existing);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.taskId == null ? 'Add Task' : 'Edit Task'),
        actions: <Widget>[
          TextButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save')),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
            children: <Widget>[
              TextFormField(
                controller: _title,
                autofocus: widget.taskId == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Task title *', hintText: 'What needs to get done?'),
                validator: (String? value) => value == null || value.trim().isEmpty ? 'Task title is required.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _description, textCapitalization: TextCapitalization.sentences, maxLines: 3, decoration: const InputDecoration(labelText: 'Description', alignLabelWithHint: true)),
              const SizedBox(height: 20),
              const _SectionTitle('Schedule'),
              _ActionRow(icon: Icons.event_outlined, label: 'Deadline', value: _dueAt == null ? 'No deadline' : _formatDateTime(_dueAt!, includeTime: _dueAt!.hour != 0 || _dueAt!.minute != 0), onTap: _chooseDueDate, trailing: _dueAt == null ? null : IconButton(tooltip: 'Clear deadline', onPressed: () => setState(() => _dueAt = null), icon: const Icon(Icons.close_rounded))),
              if (_dueAt != null)
                _ActionRow(icon: Icons.schedule_rounded, label: 'Deadline time', value: _dueAt!.hour == 0 && _dueAt!.minute == 0 ? 'No time set' : TimeOfDay.fromDateTime(_dueAt!).format(context), onTap: _chooseDueTime, trailing: IconButton(tooltip: 'Clear time', onPressed: () => setState(() => _dueAt = DateTime(_dueAt!.year, _dueAt!.month, _dueAt!.day)), icon: const Icon(Icons.close_rounded))),
              _ActionRow(icon: Icons.notifications_none_rounded, label: 'Reminder', value: _reminderAt == null ? 'No reminder' : _formatDateTime(_reminderAt!, includeTime: true), onTap: _chooseReminder, trailing: _reminderAt == null ? null : IconButton(tooltip: 'Clear reminder', onPressed: () => setState(() => _reminderAt = null), icon: const Icon(Icons.close_rounded))),
              const SizedBox(height: 20),
              const _SectionTitle('Organisation'),
              DropdownButtonFormField<TaskPriority>(
                value: _priority,
                decoration: const InputDecoration(labelText: 'Priority'),
                items: TaskPriority.values.map((TaskPriority p) => DropdownMenuItem<TaskPriority>(value: p, child: Text(_priorityLabel(p)))).toList(),
                onChanged: (TaskPriority? value) => setState(() => _priority = value ?? TaskPriority.medium),
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _category, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Category', hintText: 'Study, personal, work…')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _iconKey,
                decoration: const InputDecoration(labelText: 'Icon'),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'task', child: Text('✓  Task')),
                  DropdownMenuItem(value: 'study', child: Text('▤  Study')),
                  DropdownMenuItem(value: 'work', child: Text('▣  Work')),
                  DropdownMenuItem(value: 'personal', child: Text('♡  Personal')),
                  DropdownMenuItem(value: 'fitness', child: Text('⚡  Fitness')),
                ],
                onChanged: (String? value) => setState(() => _iconKey = value ?? 'task'),
              ),
              const SizedBox(height: 16),
              Wrap(spacing: 12, children: <Widget>[
                for (final int color in <int>[0xFFFFC857, 0xFF80CBC4, 0xFF90CAF9, 0xFFCE93D8, 0xFFEF9A9A, 0xFFA5D6A7])
                  GestureDetector(key: ValueKey<int>(color), onTap: () => setState(() => _colorValue = color), child: Container(width: 34, height: 34, decoration: BoxDecoration(color: Color(color), shape: BoxShape.circle, border: Border.all(color: _colorValue == color ? Colors.white : Colors.transparent, width: 3)), child: _colorValue == color ? const Icon(Icons.check, color: Colors.black, size: 18) : null)),
              ]),
              const SizedBox(height: 18),
              DropdownButtonFormField<TaskRepeat>(
                value: _repeat,
                decoration: const InputDecoration(labelText: 'Repeat'),
                items: const <DropdownMenuItem<TaskRepeat>>[
                  DropdownMenuItem(value: TaskRepeat.none, child: Text('Does not repeat')),
                  DropdownMenuItem(value: TaskRepeat.daily, child: Text('Every day')),
                  DropdownMenuItem(value: TaskRepeat.weekly, child: Text('Every week')),
                  DropdownMenuItem(value: TaskRepeat.monthly, child: Text('Every month')),
                ],
                onChanged: (TaskRepeat? value) => setState(() => _repeat = value ?? TaskRepeat.none),
              ),
              const SizedBox(height: 24),
              const _SectionTitle('Subtasks'),
              Text('${_subtasks.where((Subtask s) => s.isCompleted).length} of ${_subtasks.length} completed', style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: _editSubtasks, icon: const Icon(Icons.account_tree_outlined), label: const Text('Open Subtask Editor')),
              if (_subtasks.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                for (final Subtask subtask in _subtasks)
                  ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(subtask.isCompleted ? Icons.check_circle_rounded : Icons.circle_outlined, color: subtask.isCompleted ? AppColors.gold : AppColors.textSecondary), title: Text(subtask.title), subtitle: subtask.dueAt == null ? null : Text('Due ${_formatDateTime(subtask.dueAt!, includeTime: subtask.dueAt!.hour != 0 || subtask.dueAt!.minute != 0)}')),
              ],
              const SizedBox(height: 24),
              const _SectionTitle('Notes'),
              TextFormField(controller: _notes, maxLines: 4, decoration: const InputDecoration(hintText: 'Add context or notes for this task…', alignLabelWithHint: true)),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                OutlinedButton.icon(onPressed: _pickPhoto, icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('Add photo')),
                OutlinedButton.icon(onPressed: _toggleRecording, icon: Icon(_recording ? Icons.stop_circle_outlined : Icons.mic_none_rounded), label: Text(_recording ? 'Stop recording' : 'Record audio')),
              ]),
              if (_recording) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Recording audio… tap Stop recording to attach it.', style: TextStyle(color: AppColors.danger))),
              if (_photoPaths.isNotEmpty || _audioPaths.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                for (final String path in _photoPaths) ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.image_outlined), title: Text(path_util.basename(path), maxLines: 1, overflow: TextOverflow.ellipsis), trailing: IconButton(tooltip: 'Remove photo', onPressed: () => _removeAttachment(path), icon: const Icon(Icons.close_rounded))),
                for (final String path in _audioPaths) ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.audio_file_outlined), title: Text(path_util.basename(path), maxLines: 1, overflow: TextOverflow.ellipsis), trailing: IconButton(tooltip: 'Remove audio', onPressed: () => _removeAttachment(path), icon: const Icon(Icons.close_rounded))),
              ],
              const SizedBox(height: 24),
              FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : widget.taskId == null ? 'Create Task' : 'Save Changes')),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)));
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.icon, required this.label, required this.value, required this.onTap, this.trailing});
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(children: <Widget>[
        Expanded(child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(icon, color: AppColors.gold), title: Text(label), subtitle: Text(value), onTap: onTap)),
        if (trailing != null) trailing!,
      ]);
}

String _priorityLabel(TaskPriority priority) => switch (priority) {
      TaskPriority.high => 'High',
      TaskPriority.medium => 'Medium',
      TaskPriority.low => 'Low',
    };

String _formatDateTime(DateTime value, {required bool includeTime}) {
  final String date = '${value.day.toString().padLeft(2, '0')} ${_month(value.month)} ${value.year}';
  if (!includeTime) return date;
  final String hour = (value.hour % 12 == 0 ? 12 : value.hour % 12).toString();
  final String minute = value.minute.toString().padLeft(2, '0');
  return '$date · $hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
}

String _month(int month) => const <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][month - 1];
