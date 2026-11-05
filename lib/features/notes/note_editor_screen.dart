import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path_util;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/ids.dart';
import '../../domain/models/models.dart';
import '../../shared/utils/guarded.dart';
import '../../shared/widgets/widgets.dart';
import '../../state/app_data.dart';
import '../../state/app_state.dart';

/// Note editor for daily journal and habit notes. Text is saved automatically;
/// photo, audio and video attachments are copied into app-private storage.
class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({super.key, this.noteId, this.habitId, this.logDate});

  final String? noteId;
  final String? habitId;
  final DateTime? logDate;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _debounce;
  bool _initialized = false;
  bool _deleted = false;
  bool _recording = false;
  String? _recordingPath;
  Note? _existing;
  List<String> _photoPaths = <String>[];
  List<String> _audioPaths = <String>[];
  List<String> _videoPaths = <String>[];
  late final String _id = widget.noteId ?? newId();
  late final DateTime _createdAt;

  @override
  void initState() {
    super.initState();
    // Keep the note date aligned with the same local-day source used by the app.
    _createdAt = dateOnly(ref.read(todayProvider));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _title.dispose();
    _body.dispose();
    unawaited(_disposeRecorder());
    super.dispose();
  }

  Future<void> _disposeRecorder() async {
    if (_recording) {
      try {
        await _recorder.cancel();
      } catch (_) {
        // The recorder may already have stopped.
      }
    }
    final String? path = _recordingPath;
    _recordingPath = null;
    if (path != null) {
      try {
        final File file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Best-effort cleanup of an unfinished recording.
      }
    }
    try {
      await _recorder.dispose();
    } catch (_) {
      // Disposal is best effort when the platform recorder is already closed.
    }
  }

  void _initialize(AppData data) {
    _initialized = true;
    final String? id = widget.noteId;
    if (id == null) return;
    for (final Note note in data.notes) {
      if (note.id == id) {
        _existing = note;
        _title.text = note.title;
        _body.text = note.body;
        _photoPaths = List<String>.of(note.photoPaths);
        _audioPaths = List<String>.of(note.audioPaths);
        _videoPaths = List<String>.of(note.videoPaths);
        break;
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
              logDate: widget.habitId == null ? widget.logDate : null,
              createdAt: _createdAt,
              updatedAt: now,
            ))
        .copyWith(
      title: _title.text,
      body: _body.text,
      photoPaths: List<String>.of(_photoPaths),
      audioPaths: List<String>.of(_audioPaths),
      videoPaths: List<String>.of(_videoPaths),
      updatedAt: now,
    );
    if (note.isEmpty && _existing == null) return;
    try {
      await ref.read(appDataProvider.notifier).saveNote(note);
      _existing = note;
    } catch (error) {
      if (mounted) showMessage(context, 'Could not save note: $error');
    }
  }

  Future<void> _close() async {
    if (_recording) await _finishRecording();
    await _flush();
    if (mounted) context.pop();
  }

  Future<void> _delete() async {
    if (_existing == null) {
      _deleted = true;
      if (mounted) context.pop();
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
    if (_recording) {
      try {
        await _recorder.cancel();
      } catch (_) {
        // Ignore a recorder that has already stopped.
      }
      _recording = false;
    }
    final bool ok = await guarded(
      context,
      () => ref.read(appDataProvider.notifier).deleteNote(_id),
      message: 'Could not delete',
    );
    if (ok && mounted) context.pop();
  }

  Future<Directory> _attachmentDirectory() async {
    final Directory documents = await getApplicationDocumentsDirectory();
    final Directory directory = Directory(
      path_util.join(documents.path, 'tickoff_attachments'),
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<ImageSource?> _chooseSource({required bool video}) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text(video ? 'Record video' : 'Take photo'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(video ? 'Choose video' : 'Choose photo'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addPhoto() async {
    final ImageSource? source = await _chooseSource(video: false);
    if (source == null || !mounted) return;
    try {
      final XFile? picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 90,
      );
      if (picked == null || !mounted) return;
      final Directory directory = await _attachmentDirectory();
      final String extension = path_util.extension(picked.path).isEmpty
          ? '.jpg'
          : path_util.extension(picked.path);
      final String target = path_util.join(
        directory.path,
        'note-photo-${newId()}$extension',
      );
      await File(picked.path).copy(target);
      if (!mounted) return;
      setState(() => _photoPaths.add(target));
      await _flush();
    } catch (error) {
      if (mounted) showMessage(context, 'Could not attach photo: $error');
    }
  }

  Future<void> _addVideo() async {
    final ImageSource? source = await _chooseSource(video: true);
    if (source == null || !mounted) return;
    try {
      final XFile? picked = await ImagePicker().pickVideo(
        source: source,
        maxDuration: const Duration(minutes: 5),
      );
      if (picked == null || !mounted) return;
      final Directory directory = await _attachmentDirectory();
      final String extension = path_util.extension(picked.path).isEmpty
          ? '.mp4'
          : path_util.extension(picked.path);
      final String target = path_util.join(
        directory.path,
        'note-video-${newId()}$extension',
      );
      await File(picked.path).copy(target);
      if (!mounted) return;
      setState(() => _videoPaths.add(target));
      await _flush();
    } catch (error) {
      if (mounted) showMessage(context, 'Could not attach video: $error');
    }
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _finishRecording();
      return;
    }
    try {
      final bool granted = await _recorder.hasPermission();
      if (!granted) {
        if (mounted) {
          showMessage(context, 'Microphone permission is required to record audio.');
        }
        return;
      }
      final Directory directory = await _attachmentDirectory();
      final String path = path_util.join(
        directory.path,
        'note-audio-${newId()}.m4a',
      );
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      if (!mounted) {
        try {
          await _recorder.cancel();
        } catch (_) {
          // Ignore recorder shutdown during navigation.
        }
        return;
      }
      setState(() {
        _recordingPath = path;
        _recording = true;
      });
    } catch (error) {
      if (mounted) showMessage(context, 'Audio recording failed: $error');
    }
  }

  Future<void> _finishRecording() async {
    try {
      final String? path = await _recorder.stop();
      if (mounted && path != null && path.isNotEmpty) {
        setState(() {
          _audioPaths.add(path);
          _recording = false;
          _recordingPath = null;
        });
        await _flush();
      } else if (mounted) {
        setState(() {
          _recording = false;
          _recordingPath = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _recording = false;
          _recordingPath = null;
        });
        showMessage(context, 'Could not finish audio recording: $error');
      }
    }
  }

  Future<void> _removeAttachment(String kind, String path) async {
    setState(() {
      if (kind == 'photo') {
        _photoPaths.remove(path);
      } else if (kind == 'audio') {
        _audioPaths.remove(path);
      } else if (kind == 'video') {
        _videoPaths.remove(path);
      }
    });
    await _flush();
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
    final DateTime shown = _existing?.logDate ??
        widget.logDate ??
        _existing?.createdAt ??
        _createdAt;

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
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.danger,
            ),
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
          const SizedBox(height: AppDimens.gap),
          const Divider(color: AppColors.divider),
          const SizedBox(height: 8),
          const Text(
            'Attachments',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: _addPhoto,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Photo'),
              ),
              OutlinedButton.icon(
                onPressed: _toggleRecording,
                icon: Icon(_recording ? Icons.stop_rounded : Icons.mic_none_rounded),
                label: Text(_recording ? 'Stop recording' : 'Record audio'),
              ),
              OutlinedButton.icon(
                onPressed: _recording ? null : _addVideo,
                icon: const Icon(Icons.videocam_outlined),
                label: const Text('Video'),
              ),
            ],
          ),
          if (_recording) ...<Widget>[
            const SizedBox(height: 8),
            const Row(
              children: <Widget>[
                Icon(Icons.fiber_manual_record, color: AppColors.danger, size: 14),
                SizedBox(width: 8),
                Text('Recording audio…', style: TextStyle(color: AppColors.danger)),
              ],
            ),
          ],
          if (_photoPaths.isNotEmpty ||
              _audioPaths.isNotEmpty ||
              _videoPaths.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            for (final String path in _photoPaths)
              _PhotoNoteAttachment(
                path: path,
                onRemove: () => _removeAttachment('photo', path),
              ),
            for (final String path in _audioPaths)
              _AudioNoteAttachment(
                path: path,
                onRemove: () => _removeAttachment('audio', path),
              ),
            for (final String path in _videoPaths)
              _VideoNoteAttachment(
                path: path,
                onRemove: () => _removeAttachment('video', path),
              ),
          ],
        ],
      ),
    );
  }
}

class _PhotoNoteAttachment extends StatelessWidget {
  const _PhotoNoteAttachment({required this.path, required this.onRemove});
  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Card(
        color: AppColors.surface,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(path),
                  width: 76,
                  height: 68,
                  fit: BoxFit.cover,
                  errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                      const SizedBox(
                    width: 76,
                    height: 68,
                    child: Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Text('Photo attachment')),
              IconButton(
                tooltip: 'Remove photo',
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
      );
}

class _AudioNoteAttachment extends StatefulWidget {
  const _AudioNoteAttachment({required this.path, required this.onRemove});
  final String path;
  final VoidCallback onRemove;

  @override
  State<_AudioNoteAttachment> createState() => _AudioNoteAttachmentState();
}

class _AudioNoteAttachmentState extends State<_AudioNoteAttachment> {
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
    unawaited(_player.dispose());
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
      if (mounted) {
        setState(() {
          _playing = false;
          _unavailable = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Card(
        color: AppColors.surface,
        child: ListTile(
          leading: Icon(_unavailable ? Icons.audio_file_outlined : Icons.graphic_eq_rounded),
          title: Text(_unavailable ? 'Audio is unavailable' : 'Audio recording'),
          subtitle: Text(
            _unavailable
                ? 'The local recording could not be opened.'
                : path_util.basename(widget.path),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                tooltip: _playing ? 'Pause recording' : 'Play recording',
                onPressed: _unavailable ? null : _toggle,
                icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
              ),
              IconButton(
                tooltip: 'Remove audio',
                onPressed: widget.onRemove,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
      );
}

class _VideoNoteAttachment extends StatefulWidget {
  const _VideoNoteAttachment({required this.path, required this.onRemove});
  final String path;
  final VoidCallback onRemove;

  @override
  State<_VideoNoteAttachment> createState() => _VideoNoteAttachmentState();
}

class _VideoNoteAttachmentState extends State<_VideoNoteAttachment> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path));
    _controller.addListener(_refresh);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    unawaited(_controller.dispose());
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (!_ready) return;
    if (_controller.value.isPlaying) {
      await _controller.pause();
    } else {
      await _controller.play();
    }
  }

  @override
  Widget build(BuildContext context) => Card(
        color: AppColors.surface,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AspectRatio(
              aspectRatio: _ready && _controller.value.aspectRatio > 0
                  ? _controller.value.aspectRatio
                  : 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: <Widget>[
                  if (_ready)
                    VideoPlayer(_controller)
                  else
                    Container(
                      color: Colors.black,
                      alignment: Alignment.center,
                      child: Icon(
                        _failed ? Icons.videocam_off_outlined : Icons.hourglass_empty_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                  if (_ready)
                    Center(
                      child: IconButton.filledTonal(
                        tooltip: _controller.value.isPlaying ? 'Pause video' : 'Play video',
                        onPressed: _togglePlayback,
                        icon: Icon(
                          _controller.value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.videocam_outlined),
              title: Text(_failed ? 'Video is unavailable' : 'Video attachment'),
              subtitle: Text(path_util.basename(widget.path), maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                tooltip: 'Remove video',
                onPressed: widget.onRemove,
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
        ),
      );
}
