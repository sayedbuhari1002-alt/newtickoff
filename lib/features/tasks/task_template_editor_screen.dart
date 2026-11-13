import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path_util;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/ids.dart';
import '../../domain/models/models.dart';
import '../../state/app_data.dart';
import '../../state/app_state.dart';
import '../habit_form/category_picker.dart';

class TaskTemplateEditorScreen extends ConsumerStatefulWidget {
  const TaskTemplateEditorScreen({super.key, required this.template});
  final TaskTemplate template;

  @override
  ConsumerState<TaskTemplateEditorScreen> createState() => _TaskTemplateEditorScreenState();
}

class _TaskTemplateEditorScreenState extends ConsumerState<TaskTemplateEditorScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _notes;
  late final TextEditingController _difficulty;
  late final TextEditingController _target;
  late final TextEditingController _unit;
  late TaskType _type;
  late TaskProgressMode _mode;
  late TaskPriority _priority;
  late TaskRepeat _repeat;
  String? _selectedCategoryId;
  String _legacyCategoryName = '';
  late List<Subtask> _subtasks;
  late List<String> _photoPaths;
  late List<String> _audioPaths;
  final Set<String> _sessionAddedPaths = <String>{};
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  bool _saving = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    final TaskTemplate template = widget.template;
    _name = TextEditingController(text: template.name);
    _notes = TextEditingController(text: template.notes);
    _difficulty = TextEditingController(text: template.difficultyScore.toString());
    _target = TextEditingController(text: template.progressTarget.toString());
    _unit = TextEditingController(text: template.progressUnit);
    _type = template.taskType;
    _mode = template.progressMode;
    _priority = template.priority;
    _repeat = template.repeat;
    _subtasks = List<Subtask>.of(template.subtasks);
    _photoPaths = List<String>.of(template.photoPaths);
    _audioPaths = List<String>.of(template.audioPaths);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _setCategoryByName(template.category);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    _difficulty.dispose();
    _target.dispose();
    _unit.dispose();
    unawaited(_finishRecorderAndCleanup());
    super.dispose();
  }

  Future<void> _finishRecorderAndCleanup() async {
    if (_recording) {
      try { await _recorder.cancel(); } catch (_) { /* Recording may already have stopped. */ }
    }
    if (!_saved) {
      for (final String path in _sessionAddedPaths) {
        try {
          final File file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) { /* Best-effort cleanup of unsaved template attachments. */ }
      }
    }
    try { await _recorder.dispose(); } catch (_) { /* Best effort. */ }
  }

  String get _categoryName => ref.read(appDataProvider).valueOrNull?.categoryById(_selectedCategoryId)?.name ?? _legacyCategoryName;

  void _setCategoryByName(String name) {
    final List<HabitCategory> categories = ref.read(appDataProvider).valueOrNull?.categories ?? const <HabitCategory>[];
    final String normalized = name.trim().toLowerCase();
    final List<HabitCategory> matches = normalized.isEmpty
        ? <HabitCategory>[]
        : categories.where((HabitCategory item) => item.name.trim().toLowerCase() == normalized).toList();
    final HabitCategory? match = matches.isEmpty ? null : matches.first;
    setState(() {
      _selectedCategoryId = match?.id;
      _legacyCategoryName = match == null && normalized.isNotEmpty ? name.trim() : '';
    });
  }

  Future<void> _chooseCategory() async {
    final CategoryChoice? choice = await showCategoryPicker(context, selectedId: _selectedCategoryId);
    if (choice == null || !mounted) return;
    setState(() {
      _selectedCategoryId = choice.id;
      _legacyCategoryName = '';
    });
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
      final String target = path_util.join(directory.path, 'template-photo-${newId()}$extension');
      await File(picked.path).copy(target);
      if (!mounted) {
        try { await File(target).delete(); } catch (_) { /* Best effort. */ }
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
        final String path = path_util.join(directory.path, 'template-audio-${newId()}.m4a');
        _sessionAddedPaths.add(path);
        await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
        if (mounted) {
          setState(() => _recording = true);
        } else {
          try { await _recorder.cancel(); } catch (_) { /* Best effort. */ }
          try { await File(path).delete(); } catch (_) { /* Best effort. */ }
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
      } catch (_) { /* Best-effort cleanup. */ }
    }
  }

  Future<void> _addSubtask() async {
    final _SubtaskDraft? draft = await _showSubtaskDraft();
    if (draft == null || !mounted) return;
    setState(() => _subtasks.add(Subtask(
      id: newId(), title: draft.title, createdAt: DateTime.now(),
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

  Future<_SubtaskDraft?> _showSubtaskDraft({Subtask? existing}) async {
    final TextEditingController title = TextEditingController(text: existing?.title ?? '');
    final TextEditingController points = TextEditingController(text: (existing?.difficultyScore ?? 1).toString());
    String? error;
    final _SubtaskDraft? result = await showDialog<_SubtaskDraft>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext dialogContext, StateSetter setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Add template subtask' : 'Edit template subtask'),
          content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            TextField(controller: title, autofocus: true, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: 'Subtask name', errorText: error)),
            const SizedBox(height: 12),
            TextField(controller: points, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Difficulty score (1–10)')),
          ]),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () {
              final double? value = double.tryParse(points.text.trim());
              if (title.text.trim().isEmpty || value == null || !value.isFinite || value < 1 || value > 10) {
                setDialogState(() => error = title.text.trim().isEmpty ? 'Enter a subtask name.' : 'Difficulty must be between 1 and 10.');
                return;
              }
              Navigator.pop(dialogContext, _SubtaskDraft(title.text.trim(), value));
            }, child: const Text('Save')),
          ],
        ),
      ),
    );
    title.dispose();
    points.dispose();
    return result;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final double? difficulty = double.tryParse(_difficulty.text.trim());
    final double? target = double.tryParse(_target.text.trim());
    if (difficulty == null || !difficulty.isFinite || difficulty < 1 || difficulty > 10 ||
        (_type == TaskType.progressive && _mode == TaskProgressMode.count && (target == null || !target.isFinite || target <= 0))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Check the difficulty and progress target values.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final TaskTemplate updated = widget.template.copyWith(
        name: _name.text.trim(),
        taskType: _type,
        progressMode: _mode,
        progressTarget: _mode == TaskProgressMode.percentage ? 100 : target!,
        progressUnit: _unit.text.trim(),
        difficultyScore: difficulty,
        priority: _priority,
        category: _categoryName,
        repeat: _repeat,
        notes: _notes.text.trim(),
        photoPaths: List<String>.of(_photoPaths),
        audioPaths: List<String>.of(_audioPaths),
        subtasks: List<Subtask>.of(_subtasks),
      );
      await ref.read(appDataProvider.notifier).saveTaskTemplate(updated);
      _saved = true;
      _sessionAddedPaths.clear();
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Task Template'),
        actions: <Widget>[TextButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'))],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
            children: <Widget>[
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Template name *'),
                validator: (String? value) => value == null || value.trim().isEmpty ? 'Template name is required.' : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<TaskType>(
                value: _type,
                decoration: const InputDecoration(labelText: 'Task type'),
                items: const <DropdownMenuItem<TaskType>>[
                  DropdownMenuItem(value: TaskType.standard, child: Text('Standard')),
                  DropdownMenuItem(value: TaskType.progressive, child: Text('Progressive')),
                ],
                onChanged: (TaskType? value) => setState(() => _type = value ?? TaskType.standard),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<TaskPriority>(
                value: _priority,
                decoration: const InputDecoration(labelText: 'Priority'),
                items: TaskPriority.values.map((TaskPriority value) => DropdownMenuItem(value: value, child: Text(value.name))).toList(),
                onChanged: (TaskPriority? value) => setState(() => _priority = value ?? TaskPriority.medium),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _difficulty,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Difficulty score (1–10)'),
                validator: (String? value) {
                  final double? number = double.tryParse(value?.trim() ?? '');
                  return number == null || !number.isFinite || number < 1 || number > 10 ? 'Enter a score between 1 and 10.' : null;
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.label_outline_rounded),
                title: const Text('Category'),
                subtitle: Text(_categoryName.isEmpty ? 'No category' : _categoryName),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _chooseCategory,
              ),
              if (_type == TaskType.progressive) ...<Widget>[
                const SizedBox(height: 8),
                DropdownButtonFormField<TaskProgressMode>(
                  value: _mode,
                  decoration: const InputDecoration(labelText: 'Progress method'),
                  items: const <DropdownMenuItem<TaskProgressMode>>[
                    DropdownMenuItem(value: TaskProgressMode.percentage, child: Text('Percentage')),
                    DropdownMenuItem(value: TaskProgressMode.count, child: Text('Count / target')),
                  ],
                  onChanged: (TaskProgressMode? value) => setState(() => _mode = value ?? TaskProgressMode.percentage),
                ),
                if (_mode == TaskProgressMode.count) ...<Widget>[
                  const SizedBox(height: 12),
                  TextFormField(controller: _target, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Count target'), validator: (String? value) { if (_type != TaskType.progressive || _mode != TaskProgressMode.count) return null; final double? number = double.tryParse(value?.trim() ?? ''); return number == null || !number.isFinite || number <= 0 ? 'Enter a target greater than zero.' : null; }),
                  const SizedBox(height: 12),
                  TextFormField(controller: _unit, decoration: const InputDecoration(labelText: 'Unit')),
                ],
              ],
              const SizedBox(height: 12),
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
              const _SectionTitle('Notes'),
              TextFormField(controller: _notes, maxLines: 4, decoration: const InputDecoration(hintText: 'Reusable notes that will be copied to tasks…', alignLabelWithHint: true)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                OutlinedButton.icon(onPressed: _pickPhoto, icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('Add photo')),
                OutlinedButton.icon(onPressed: _toggleRecording, icon: Icon(_recording ? Icons.stop_circle_outlined : Icons.mic_none_rounded), label: Text(_recording ? 'Stop recording' : 'Record audio')),
              ]),
              if (_recording) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Recording audio… tap Stop recording to attach it.', style: TextStyle(color: AppColors.danger))),
              if (_photoPaths.isNotEmpty || _audioPaths.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                for (final String path in _photoPaths)
                  ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.image_outlined), title: Text(path_util.basename(path), maxLines: 1, overflow: TextOverflow.ellipsis), trailing: IconButton(tooltip: 'Remove photo', onPressed: () => _removeAttachment(path), icon: const Icon(Icons.close_rounded))),
                for (final String path in _audioPaths)
                  ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.audio_file_outlined), title: Text(path_util.basename(path), maxLines: 1, overflow: TextOverflow.ellipsis), trailing: IconButton(tooltip: 'Remove audio', onPressed: () => _removeAttachment(path), icon: const Icon(Icons.close_rounded))),
              ],
              const SizedBox(height: 24),
              const _SectionTitle('Subtasks'),
              Text('These steps will be added whenever you create a task from this template.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: _addSubtask, icon: const Icon(Icons.add_rounded), label: const Text('Add subtask')),
              if (_subtasks.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                for (final Subtask subtask in _subtasks)
                  Card(child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.checklist_rounded),
                    title: Text(subtask.title),
                    subtitle: Text('Difficulty ${subtask.difficultyScore.toStringAsFixed(subtask.difficultyScore == subtask.difficultyScore.roundToDouble() ? 0 : 1)}'),
                    trailing: Wrap(children: <Widget>[
                      IconButton(tooltip: 'Edit subtask', onPressed: () => _editSubtask(subtask), icon: const Icon(Icons.edit_outlined)),
                      IconButton(tooltip: 'Remove subtask', onPressed: () => setState(() => _subtasks.removeWhere((Subtask item) => item.id == subtask.id)), icon: const Icon(Icons.close_rounded)),
                    ]),
                  )),
              ],
              const SizedBox(height: 24),
              FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save Template')),
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
