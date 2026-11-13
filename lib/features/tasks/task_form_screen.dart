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
import '../../data/services/task_reminder_service.dart';
import '../habit_form/category_picker.dart';
import '../../domain/models/models.dart';
import '../../state/app_data.dart';
import '../../state/app_state.dart';

class TaskFormScreen extends ConsumerStatefulWidget {
  const TaskFormScreen({super.key, this.taskId, this.initialTemplate});
  final String? taskId;
  final TaskTemplate? initialTemplate;

  @override
  ConsumerState<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends ConsumerState<TaskFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  String? _selectedCategoryId;
  String _legacyCategoryName = '';
  final TextEditingController _notes = TextEditingController();
  DateTime? _dueAt;
  DateTime? _reminderAt;
  TaskPriority _priority = TaskPriority.medium;
  TaskRepeat _repeat = TaskRepeat.none;
  TaskType _taskType = TaskType.standard;
  TaskProgressMode _progressMode = TaskProgressMode.percentage;
  final TextEditingController _progressTarget = TextEditingController(text: '100');
  final TextEditingController _progressUnit = TextEditingController();
  final TextEditingController _difficulty = TextEditingController(text: '1.0');
  int _colorValue = 0xFFA78BFA;
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
    _notes.dispose();
    _progressTarget.dispose();
    _progressUnit.dispose();
    _difficulty.dispose();
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
    _setCategoryByName(task.category);
    _notes.text = task.notes;
    _dueAt = task.dueAt;
    _reminderAt = task.reminderAt;
    _priority = task.priority;
    _repeat = task.repeat;
    _taskType = task.taskType;
    _progressMode = task.progressMode;
    _progressTarget.text = task.progressTarget.toString();
    _progressUnit.text = task.progressUnit;
    _difficulty.text = task.difficultyScore.toString();
    _colorValue = task.colorValue;
    _iconKey = task.iconKey;
    _subtasks = List<Subtask>.of(task.subtasks);
    _photoPaths = List<String>.of(task.photoPaths);
    _audioPaths = List<String>.of(task.audioPaths);
    _initialised = true;
  }

  void _fillTemplate(TaskTemplate template) {
    _taskType = template.taskType;
    _progressMode = template.progressMode;
    _progressTarget.text = template.progressTarget.toString();
    _progressUnit.text = template.progressUnit;
    _difficulty.text = template.difficultyScore.toString();
    _priority = template.priority;
    _setCategoryByName(template.category);
    _notes.text = template.notes;
    _subtasks = _instantiateTemplateSubtasks(template.subtasks);
    _photoPaths = List<String>.of(template.photoPaths);
    _audioPaths = List<String>.of(template.audioPaths);
    _iconKey = template.iconKey;
    _colorValue = template.colorValue;
    _repeat = template.repeat;
    // Titles, deadlines, reminders and current completion/progress remain task-specific.
    _initialised = true;
  }

  String get _selectedCategoryName {
    final AppData? data = ref.read(appDataProvider).valueOrNull;
    return data?.categoryById(_selectedCategoryId)?.name ?? _legacyCategoryName;
  }

  void _setCategoryByName(String name) {
    final AppData? data = ref.read(appDataProvider).valueOrNull;
    final String normalized = name.trim().toLowerCase();
    final List<HabitCategory> matches = normalized.isEmpty
        ? <HabitCategory>[]
        : (data?.categories ?? const <HabitCategory>[]).where((HabitCategory category) => category.name.trim().toLowerCase() == normalized).toList();
    final HabitCategory? match = matches.isEmpty ? null : matches.first;
    _selectedCategoryId = match?.id;
    _legacyCategoryName = match == null && normalized.isNotEmpty ? name.trim() : '';
  }

  Future<void> _chooseCategory() async {
    final CategoryChoice? choice = await showCategoryPicker(context, selectedId: _selectedCategoryId);
    if (choice == null || !mounted) return;
    setState(() {
      _selectedCategoryId = choice.id;
      _legacyCategoryName = '';
    });
  }

  List<Subtask> _instantiateTemplateSubtasks(List<Subtask> source) {
    final DateTime now = DateTime.now();
    return <Subtask>[
      for (int index = 0; index < source.length; index++)
        Subtask(
          id: newId(),
          title: source[index].title,
          createdAt: now,
          sortOrder: index,
          difficultyScore: source[index].difficultyScore,
        ),
    ];
  }

  List<Subtask> _subtasksForTemplate(List<Subtask> source) {
    final DateTime now = DateTime.now();
    return <Subtask>[
      for (int index = 0; index < source.length; index++)
        Subtask(
          id: newId(),
          title: source[index].title,
          createdAt: now,
          sortOrder: index,
          difficultyScore: source[index].difficultyScore,
        ),
    ];
  }

  Future<void> _addSubtask() async {
    final _SubtaskDraft? draft = await _showSubtaskDraft();
    if (draft == null || !mounted) return;
    final DateTime now = DateTime.now();
    setState(() => _subtasks.add(Subtask(
      id: newId(), title: draft.title, createdAt: now,
      sortOrder: _subtasks.length, difficultyScore: draft.difficultyScore,
    )));
  }

  Future<void> _editSubtask(Subtask subtask) async {
    final _SubtaskDraft? draft = await _showSubtaskDraft(existing: subtask);
    if (draft == null || !mounted) return;
    setState(() {
      final int index = _subtasks.indexWhere((Subtask item) => item.id == subtask.id);
      if (index >= 0) _subtasks[index] = subtask.copyWith(title: draft.title, difficultyScore: draft.difficultyScore);
    });
  }

  void _removeSubtask(String id) => setState(() => _subtasks.removeWhere((Subtask item) => item.id == id));

  Future<_SubtaskDraft?> _showSubtaskDraft({Subtask? existing}) async {
    final TextEditingController title = TextEditingController(text: existing?.title ?? '');
    final TextEditingController difficulty = TextEditingController(text: (existing?.difficultyScore ?? 1).toString());
    String? error;
    final _SubtaskDraft? result = await showDialog<_SubtaskDraft>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext dialogContext, StateSetter setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Add subtask' : 'Edit subtask'),
          content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            TextField(controller: title, autofocus: true, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: 'Subtask name', errorText: error)),
            const SizedBox(height: 12),
            TextField(controller: difficulty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Difficulty score (1–10)')),
          ]),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () {
              final double? points = double.tryParse(difficulty.text.trim());
              if (title.text.trim().isEmpty || points == null || !points.isFinite || points < 1 || points > 10) {
                setDialogState(() => error = title.text.trim().isEmpty ? 'Enter a subtask name.' : 'Difficulty must be between 1 and 10.');
                return;
              }
              Navigator.pop(dialogContext, _SubtaskDraft(title.text.trim(), points));
            }, child: const Text('Save')),
          ],
        ),
      ),
    );
    title.dispose();
    difficulty.dispose();
    return result;
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

  Future<void> _cleanupUnusedSessionAttachments(Iterable<String> retainedPaths) async {
    final Set<String> retained = retainedPaths.toSet();
    for (final String path in _sessionAddedPaths.toList()) {
      if (retained.contains(path)) continue;
      _sessionAddedPaths.remove(path);
      try {
        final File file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) { /* Best-effort cleanup of replaced attachments. */ }
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

  Future<void> _applyTemplate() async {
    final AppData? data = ref.read(appDataProvider).valueOrNull;
    final List<TaskTemplate> templates = data?.taskTemplates ?? <TaskTemplate>[];
    if (templates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No task templates yet. Save your current task settings as a template first.')));
      return;
    }
    final TaskTemplate? selected = await showModalBottomSheet<TaskTemplate>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            const Padding(padding: EdgeInsets.fromLTRB(20, 4, 20, 12), child: Text('Choose a task template', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            for (final TaskTemplate template in templates)
              ListTile(
                title: Text(template.name),
                subtitle: Text('${template.taskType.name == 'standard' ? 'Standard' : 'Progressive'} · ${template.priority.name} priority · Difficulty ${template.difficultyScore}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(sheetContext, template),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _taskType = selected.taskType;
      _progressMode = selected.progressMode;
      _progressTarget.text = selected.progressTarget.toString();
      _progressUnit.text = selected.progressUnit;
      _difficulty.text = selected.difficultyScore.toString();
      _priority = selected.priority;
      _setCategoryByName(selected.category);
      _notes.text = selected.notes;
      _subtasks = _instantiateTemplateSubtasks(selected.subtasks);
      _photoPaths = List<String>.of(selected.photoPaths);
      _audioPaths = List<String>.of(selected.audioPaths);
      _iconKey = selected.iconKey;
      _colorValue = selected.colorValue;
      _repeat = selected.repeat;
    });
  }

  Future<void> _saveAsTemplate() async {
    final TextEditingController name = TextEditingController();
    final bool? save = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Save task template'),
        content: TextField(controller: name, autofocus: true, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Template name', hintText: 'Academic Revision')),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, name.text.trim().isNotEmpty), child: const Text('Save Template')),
        ],
      ),
    );
    if (save != true || !mounted) { name.dispose(); return; }
    final double? difficulty = double.tryParse(_difficulty.text.trim());
    final double? target = double.tryParse(_progressTarget.text.trim());
    if (difficulty == null || !difficulty.isFinite || difficulty < 1 || difficulty > 10 || (_taskType == TaskType.progressive && target != null && (!target.isFinite || target <= 0)) || (_taskType == TaskType.progressive && target == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Check the difficulty and progress target values.')));
      name.dispose();
      return;
    }
    try {
      final DateTime now = DateTime.now();
      final AppData? data = ref.read(appDataProvider).valueOrNull;
      final List<TaskTemplate> matches = (data?.taskTemplates ?? <TaskTemplate>[]).where((TaskTemplate item) => item.name.toLowerCase() == name.text.trim().toLowerCase()).toList();
      final TaskTemplate? existing = matches.isEmpty ? null : matches.first;
      final TaskTemplate template = TaskTemplate(
        id: existing?.id ?? newId(), name: name.text.trim(), createdAt: existing?.createdAt ?? now, updatedAt: now,
        taskType: _taskType, progressMode: _progressMode,
        progressTarget: double.tryParse(_progressTarget.text.trim()) ?? 100,
        progressUnit: _progressUnit.text.trim(),
        difficultyScore: double.tryParse(_difficulty.text.trim()) ?? 1.0,
        priority: _priority, category: _selectedCategoryName, iconKey: _iconKey,
        colorValue: _colorValue, repeat: _repeat,
        notes: _notes.text.trim(), photoPaths: List<String>.of(_photoPaths),
        audioPaths: List<String>.of(_audioPaths), subtasks: _subtasksForTemplate(_subtasks),
      );
      await ref.read(appDataProvider.notifier).saveTaskTemplate(template);
      // The template now owns references to these new attachment files. Do not
      // delete them when this form is closed before the task itself is saved.
      await _cleanupUnusedSessionAttachments(<String>{...template.photoPaths, ...template.audioPaths});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Template "${template.name}" saved.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      name.dispose();
    }
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
      category: _selectedCategoryName,
      iconKey: _iconKey,
      colorValue: _colorValue,
      isCompleted: old?.isCompleted ?? false,
      completedAt: old?.completedAt,
      isPaused: old?.isPaused ?? false,
      repeat: _repeat,
      taskType: _taskType,
      progressMode: _progressMode,
      progressValue: _taskType == TaskType.progressive && old?.taskType == TaskType.progressive && old?.progressMode == _progressMode ? (old?.progressValue ?? 0) : 0,
      progressTarget: _taskType == TaskType.progressive && _progressMode == TaskProgressMode.count ? (double.tryParse(_progressTarget.text.trim()) ?? 100) : 100,
      progressUnit: _progressUnit.text.trim(),
      difficultyScore: double.tryParse(_difficulty.text.trim()) ?? 1.0,
      parentTaskId: old?.parentTaskId,
      isGroup: old?.isGroup ?? false,
      sortOrder: old?.sortOrder ?? 0,
      notes: _notes.text.trim(),
      photoPaths: List<String>.of(_photoPaths),
      audioPaths: List<String>.of(_audioPaths),
      subtasks: _subtasks,
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
    );
    try {
      await ref.read(appDataProvider.notifier).saveTask(task);
      await _cleanupUnusedSessionAttachments(<String>{...task.photoPaths, ...task.audioPaths});
      _savedSuccessfully = true;
      _sessionAddedPaths.clear();
      final String? reminderIssue = TaskReminderService.instance.lastSchedulingIssue;
      if (mounted && reminderIssue != null && (_reminderAt != null || _dueAt != null)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(reminderIssue)),
        );
      }
      if (mounted) {
        if (widget.taskId == null) {
          context.pushReplacement(AppRoutes.taskDetail(task.id));
        } else if (context.canPop()) {
          context.pop();
        } else {
          context.go(AppRoutes.taskDetail(task.id));
        }
      }
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
    if (!_initialised) {
      if (existing != null) {
        _fill(existing);
      } else if (widget.initialTemplate != null) {
        _fillTemplate(widget.initialTemplate!);
      } else if (widget.taskId == null) {
        _initialised = true;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.taskId == null ? 'Add Task' : 'Edit Task'),
        actions: <Widget>[
          IconButton(tooltip: 'Use template', onPressed: _saving ? null : _applyTemplate, icon: const Icon(Icons.playlist_add_rounded)),
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
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.label_outline_rounded),
                title: const Text('Category'),
                subtitle: Text(_selectedCategoryName.isEmpty ? 'No category' : _selectedCategoryName),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _chooseCategory,
              ),
              const SizedBox(height: 8),
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
                for (final int color in <int>[0xFFA78BFA, 0xFF80CBC4, 0xFF90CAF9, 0xFFCE93D8, 0xFFEF9A9A, 0xFFA5D6A7])
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
              const SizedBox(height: 18),
              const _SectionTitle('Task Type and Progress'),
              DropdownButtonFormField<TaskType>(
                value: _taskType,
                decoration: const InputDecoration(labelText: 'Task type'),
                items: const <DropdownMenuItem<TaskType>>[
                  DropdownMenuItem(value: TaskType.standard, child: Text('Standard task · Complete / Incomplete')),
                  DropdownMenuItem(value: TaskType.progressive, child: Text('Progressive task · Track progress')),
                ],
                onChanged: (TaskType? value) => setState(() { _taskType = value ?? TaskType.standard; }),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _difficulty,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Difficulty score (1.0–10.0)', hintText: 'Used to calculate productivity points'),
                validator: (String? value) {
                  final double? parsed = double.tryParse(value?.trim() ?? '');
                  return parsed == null || !parsed.isFinite || parsed < 1 || parsed > 10 ? 'Enter a score between 1 and 10.' : null;
                },
              ),
              if (_taskType == TaskType.progressive) ...<Widget>[
                const SizedBox(height: 12),
                DropdownButtonFormField<TaskProgressMode>(
                  value: _progressMode,
                  decoration: const InputDecoration(labelText: 'Progress tracking method'),
                  items: const <DropdownMenuItem<TaskProgressMode>>[
                    DropdownMenuItem(value: TaskProgressMode.percentage, child: Text('Percentage (0–100%)')),
                    DropdownMenuItem(value: TaskProgressMode.count, child: Text('Count / target')),
                  ],
                  onChanged: (TaskProgressMode? value) => setState(() { _progressMode = value ?? TaskProgressMode.percentage; _progressTarget.text = _progressMode == TaskProgressMode.percentage ? '100' : _progressTarget.text; }),
                ),
                if (_progressMode == TaskProgressMode.count) ...<Widget>[
                  const SizedBox(height: 12),
                  TextFormField(controller: _progressTarget, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Total count / target'), validator: (String? value) { final double? parsed = double.tryParse(value?.trim() ?? ''); return parsed == null || !parsed.isFinite || parsed <= 0 ? 'Enter a target greater than zero.' : null; }),
                  const SizedBox(height: 12),
                  TextFormField(controller: _progressUnit, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Unit (optional)', hintText: 'Chapters, pages, questions…')),
                ] else
                  Padding(padding: const EdgeInsets.only(top: 8), child: Text('You can update the percentage as you work over multiple sessions.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
              ],
              const SizedBox(height: 16),
              Text('To organise related tasks, create them individually and group them from the Tasks screen using long-press selection.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 24),
              const _SectionTitle('Subtasks'),
              Text('Break this task into smaller steps. Each subtask can be completed separately.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: _addSubtask, icon: const Icon(Icons.add_rounded), label: const Text('Add subtask')),
              if (_subtasks.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                for (final Subtask subtask in _subtasks)
                  Card(
                    child: ListTile(
                      dense: true,
                      leading: Icon(subtask.isCompleted ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: subtask.isCompleted ? AppColors.gold : AppColors.textSecondary),
                      title: Text(subtask.title),
                      subtitle: Text('Difficulty ${subtask.difficultyScore.toStringAsFixed(subtask.difficultyScore == subtask.difficultyScore.roundToDouble() ? 0 : 1)}'),
                      trailing: Wrap(children: <Widget>[
                        IconButton(tooltip: 'Edit subtask', onPressed: () => _editSubtask(subtask), icon: const Icon(Icons.edit_outlined)),
                        IconButton(tooltip: 'Remove subtask', onPressed: () => _removeSubtask(subtask.id), icon: const Icon(Icons.close_rounded)),
                      ]),
                    ),
                  ),
              ],
              const SizedBox(height: 24),
              const _SectionTitle('Notes'),
              TextFormField(controller: _notes, maxLines: 4, decoration: const InputDecoration(hintText: 'Add context or notes for this task…', alignLabelWithHint: true)),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                OutlinedButton.icon(onPressed: _pickPhoto, icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('Add photo')),
                OutlinedButton.icon(onPressed: _toggleRecording, icon: Icon(_recording ? Icons.stop_circle_outlined : Icons.mic_none_rounded), label: Text(_recording ? 'Stop recording' : 'Record audio')),
              ]),
              if (_recording) Padding(padding: EdgeInsets.only(top: 8), child: Text('Recording audio… tap Stop recording to attach it.', style: TextStyle(color: AppColors.danger))),
              if (_photoPaths.isNotEmpty || _audioPaths.isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                for (final String path in _photoPaths) ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.image_outlined), title: Text(path_util.basename(path), maxLines: 1, overflow: TextOverflow.ellipsis), trailing: IconButton(tooltip: 'Remove photo', onPressed: () => _removeAttachment(path), icon: const Icon(Icons.close_rounded))),
                for (final String path in _audioPaths) ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.audio_file_outlined), title: Text(path_util.basename(path), maxLines: 1, overflow: TextOverflow.ellipsis), trailing: IconButton(tooltip: 'Remove audio', onPressed: () => _removeAttachment(path), icon: const Icon(Icons.close_rounded))),
              ],
              const SizedBox(height: 18),
              OutlinedButton.icon(onPressed: _saving ? null : _saveAsTemplate, icon: const Icon(Icons.bookmark_add_outlined), label: const Text('Save these settings as a template')),
              const SizedBox(height: 12),
              FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : widget.taskId == null ? 'Create Task' : 'Save Changes')),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubtaskDraft {
  const _SubtaskDraft(this.title, this.difficultyScore);
  final String title;
  final double difficultyScore;
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
