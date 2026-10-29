import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/ids.dart';
import '../../domain/models/models.dart';
import '../../shared/utils/guarded.dart';
import '../../shared/widgets/widgets.dart';
import '../../state/app_data.dart';
import '../../state/app_state.dart';

/// Note editor. Changes are saved automatically a moment after typing stops
/// and when leaving with the back arrow. Pass [noteId] to edit, [habitId] to
/// attach a new note to a habit.
class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({super.key, this.noteId, this.habitId});

  final String? noteId;
  final String? habitId;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  Timer? _debounce;
  bool _initialized = false;
  Note? _existing;
  late final String _id = widget.noteId ?? newId();
  late final DateTime _createdAt = DateTime.now();
  bool _deleted = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _initialize(AppData data) {
    _initialized = true;
    final String? id = widget.noteId;
    if (id == null) return;
    for (final Note n in data.notes) {
      if (n.id == id) {
        _existing = n;
        _title.text = n.title;
        _body.text = n.body;
      }
    }
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), _flush);
  }

  /// Saves now. Empty new notes are never stored.
  Future<void> _flush() async {
    _debounce?.cancel();
    if (_deleted || !mounted) return;
    final DateTime now = DateTime.now();
    final Note note = (_existing ??
            Note(
              id: _id,
              habitId: widget.habitId,
              createdAt: _createdAt,
              updatedAt: now,
            ))
        .copyWith(title: _title.text, body: _body.text, updatedAt: now);
    if (note.isEmpty && _existing == null) return;
    try {
      await ref.read(appDataProvider.notifier).saveNote(note);
      _existing = note;
    } catch (e) {
      if (mounted) showMessage(context, 'Could not save note: $e');
    }
  }

  Future<void> _close() async {
    await _flush();
    if (mounted) context.pop();
  }

  Future<void> _delete() async {
    if (_existing == null) {
      _deleted = true;
      context.pop();
      return;
    }
    final bool sure = await showConfirmDialog(
      context,
      title: 'Delete note?',
      message: 'This note will be permanently deleted.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!sure || !mounted) return;
    _deleted = true;
    final bool ok = await guarded(
      context,
      () => ref.read(appDataProvider.notifier).deleteNote(_id),
      message: 'Could not delete',
    );
    if (ok && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final AppData? data = ref.watch(appDataProvider).valueOrNull;
    if (data == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (!_initialized) _initialize(data);
    final String? habitId = _existing?.habitId ?? widget.habitId;
    final Habit? habit = habitId == null ? null : data.habitById(habitId);
    final DateTime shown = _existing?.createdAt ?? _createdAt;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: _close,
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Delete note',
            icon: const Icon(Icons.delete_outline_rounded,
                color: AppColors.danger),
            onPressed: _delete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppDimens.pagePadding),
        children: <Widget>[
          Text(
            '${monthShort(shown)} ${shown.day}, ${shown.year}'
            '${habit == null ? '' : '  ·  ${habit.title}'}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppDimens.gap),
          TextField(
            controller: _title,
            onChanged: (String _) => _scheduleSave(),
            textInputAction: TextInputAction.next,
            cursorColor: AppColors.gold,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(
              hintText: 'Title',
              hintStyle: TextStyle(color: AppColors.textHint),
              border: InputBorder.none,
            ),
          ),
          TextField(
            controller: _body,
            onChanged: (String _) => _scheduleSave(),
            cursorColor: AppColors.gold,
            minLines: 8,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(
              hintText: 'Note',
              hintStyle: TextStyle(color: AppColors.textHint),
              border: InputBorder.none,
            ),
          ),
        ],
      ),
    );
  }
}
