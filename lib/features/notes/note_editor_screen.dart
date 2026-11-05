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

/// Daily journal / habit note editor with local photo, audio, and video media.
/// Pass [noteId] to edit, [habitId] to attach a new note to a habit, or
/// [logDate] to create a dated Daily Log entry.
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
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();
  final List<String> _photoPaths = <String>[];
  final List<String> _audioPaths = <String>[];
  final List<String> _videoPaths = <String>[];
  final Set<String> _sessionAddedPaths = <String>{};
  Timer? _debounce;
  bool _initialized = false;
  bool _deleted = false;
  bool _recording = false;
  bool _mediaBusy = false;
  String? _recordingPath;
  Note? _existing;
  late final String _id = widget.noteId ?? newId();
  late final DateTime _createdAt;

  @override
  void initState() {
    super.initState();
    _createdAt = dateOnly(ref.read(todayProvider));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _title.dispose();
    _body.dispose();
    unawaited(_finishRecorderAndCleanup());
    super.dispose();
  }

  Future<void> _finishRecorderAndCleanup() async {
    if (_recording) {
      try {
        await _recorder.cancel();
      } catch (_) {
        // The recorder may already have stopped.
      }
    }
    // Successful saves clear this set. Anything still in it is a newly
    // created file that was never committed to a note and can be removed.
    for (final String path in _sessionAddedPaths) {
      try {
        final File file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Best-effort cleanup of media from an unsaved note.
      }
    }
    try {
      await _recorder.dispose();
    } catch (_) {
      // Disposing a recorder is best effort.
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
        _photoPaths.addAll(note.photoPaths);
        _audioPaths.addAll(note.audioPaths);
        _videoPaths.addAll(note.videoPaths);
        break;
      }
    }
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), _flush);
  }

  /// Persists text and attachment references. Empty new notes are never stored.
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
      _sessionAddedPaths.clear();
    } catch (error) {
      if (mounted) showMessage(context, 'Could not save note: $error');
    }
  }

  Future<void> _close() async {
    _debounce?.cancel();
    if (_recording) await _stopRecording();
    await _flush();
    if (mounted) context.pop();
  }

  Future<void> _delete() async {
    if (_recording) {
      try {
        await _recorder.cancel();
      } catch (_) {
        // Continue with deletion even if recording has already stopped.
      }
      if (mounted) setState(() => _recording = false);
    }
    if (_existing == null) {
      _deleted = true;
      if (mounted) context.pop();
      return;
    }
    final bool sure = await showConfirmDialog(
      context,
      title: 'Delete note?',
      message: 'This note and its local media attachments will be permanently deleted.',
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

  Future<Directory> _attachmentDirectory() async {
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory directory =
        Directory(path_util.join(docs.path, 'tickoff_attachments'));
    await directory.create(recursive: true);
    return directory;
  }

  Future<ImageSource?> _chooseMediaSource(String title) =>
      showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: AppColors.surface,
        builder: (BuildContext sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Camera'),
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Gallery'),
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

  Future<void> _addPhoto() async {
    if (_mediaBusy) return;
    final ImageSource? source = await _chooseMediaSource('Add a photo');
    if (source == null || !mounted) return;
    setState(() => _mediaBusy = true);
    String? target;
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 90,
      );
      if (picked == null) return;
      final Directory directory = await _attachmentDirectory();
      final String extension = path_util.extension(picked.path).isEmpty
          ? '.jpg'
          : path_util.extension(picked.path);
      target = path_util.join(directory.path, 'photo-${newId()}$extension');
      await File(picked.path).copy(target);
      if (!mounted) {
        await _deleteFile(target);
        return;
      }
      _sessionAddedPaths.add(target);
      setState(() => _photoPaths.add(target!));
      await _flush();
    } catch (error) {
      if (target != null) await _deleteFile(target);
      if (mounted) showMessage(context, 'Could not attach photo: $error');
    } finally {
      if (mounted) setState(() => _mediaBusy = false);
    }
  }

  Future<void> _addVideo() async {
    if (_mediaBusy) return;
    final ImageSource? source = await _chooseMediaSource('Add a video');
    if (source == null || !mounted) return;
    setState(() => _mediaBusy = true);
    String? target;
    try {
      final XFile? picked = await _picker.pickVideo(source: source);
      if (picked == null) return;
      final Directory directory = await _attachmentDirectory();
      final String extension = path_util.extension(picked.path).isEmpty
          ? '.mp4'
          : path_util.extension(picked.path);
      target = path_util.join(directory.path, 'video-${newId()}$extension');
      await File(picked.path).copy(target);
      if (!mounted) {
        await _deleteFile(target);
        return;
      }
      _sessionAddedPaths.add(target);
      setState(() => _videoPaths.add(target!));
      await _flush();
    } catch (error) {
      if (target != null) await _deleteFile(target);
      if (mounted) showMessage(context, 'Could not attach video: $error');
    } finally {
      if (mounted) setState(() => _mediaBusy = false);
    }
  }

  Future<void> _toggleRecording() async {
    if (_mediaBusy) return;
    if (_recording) {
      await _stopRecording();
      return;
    }
    String? target;
    try {
      final bool granted = await _recorder.hasPermission();
      if (!granted) {
        if (mounted) {
          showMessage(context, 'Microphone permission is required to record audio.');
        }
        return;
      }
      final Directory directory = await _attachmentDirectory();
      final String path = path_util.join(directory.path, 'audio-${newId()}.m4a');
      target = path;
      _sessionAddedPaths.add(path);
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      _recordingPath = path;
      if (mounted) {
        setState(() => _recording = true);
      } else {
        try {
          await _recorder.cancel();
        } catch (_) {
          // Best-effort stop after the editor was removed.
        }
        await _deleteFile(path);
        _sessionAddedPaths.remove(path);
      }
    } catch (error) {
      if (target != null) {
        _sessionAddedPaths.remove(target);
        await _deleteFile(target);
      }
      if (mounted) showMessage(context, 'Audio recording failed: $error');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final String? stoppedPath = await _recorder.stop();
      final String? path = stoppedPath ?? _recordingPath;
      _recordingPath = null;
      if (mounted) {
        setState(() {
          _recording = false;
          if (path != null &&
              path.isNotEmpty &&
              File(path).existsSync() &&
              !_audioPaths.contains(path)) {
            _audioPaths.add(path);
          }
        });
      }
      if (path != null && path.isNotEmpty && File(path).existsSync()) {
        await _flush();
      } else if (path != null) {
        _sessionAddedPaths.remove(path);
        await _deleteFile(path);
      }
    } catch (error) {
      final String? path = _recordingPath;
      _recordingPath = null;
      if (path != null) {
        _sessionAddedPaths.remove(path);
        await _deleteFile(path);
      }
      if (mounted) {
        setState(() => _recording = false);
        showMessage(context, 'Could not finish audio recording: $error');
      }
    }
  }

  Future<void> _removeAttachment(String path) async {
    setState(() {
      _photoPaths.remove(path);
      _audioPaths.remove(path);
      _videoPaths.remove(path);
    });
    if (_sessionAddedPaths.remove(path)) await _deleteFile(path);
    await _flush();
  }

  Future<void> _deleteFile(String path) async {
    try {
      final File file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Missing or locked local media should not block note editing.
    }
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
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
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
          const SizedBox(height: 18),
          const Text(
            'Media attachments',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: _mediaBusy || _recording ? null : _addPhoto,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Photo'),
              ),
              OutlinedButton.icon(
                onPressed: _mediaBusy ? null : _toggleRecording,
                icon: Icon(_recording ? Icons.stop_rounded : Icons.mic_none_rounded),
                label: Text(_recording ? 'Stop recording' : 'Record audio'),
                style: _recording
                    ? OutlinedButton.styleFrom(foregroundColor: AppColors.danger)
                    : null,
              ),
              OutlinedButton.icon(
                onPressed: _mediaBusy || _recording ? null : _addVideo,
                icon: const Icon(Icons.videocam_outlined),
                label: const Text('Video'),
              ),
            ],
          ),
          if (_mediaBusy) ...<Widget>[
            const SizedBox(height: 10),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (_recording) ...<Widget>[
            const SizedBox(height: 8),
            const Text(
              'Recording audio… tap Stop recording when finished.',
              style: TextStyle(color: AppColors.danger, fontSize: 12),
            ),
          ],
          if (_photoPaths.isNotEmpty || _audioPaths.isNotEmpty || _videoPaths.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            for (final String path in _photoPaths)
              _EditablePhotoAttachment(path: path, onRemove: () => _removeAttachment(path)),
            for (final String path in _audioPaths)
              _EditableMediaRow(
                icon: Icons.graphic_eq_rounded,
                title: 'Audio recording',
                path: path,
                onRemove: () => _removeAttachment(path),
                  player: _NoteAudioPlayer(
                    key: ValueKey<String>(path),
                    path: path,
                  ),
              ),
            for (final String path in _videoPaths)
                _EditableVideoAttachment(
                  path: path,
                  onRemove: () => _removeAttachment(path),
                ),
          ],
        ],
      ),
    );
  }
}

class _EditablePhotoAttachment extends StatelessWidget {
  const _EditablePhotoAttachment({required this.path, required this.onRemove});
  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final File file = File(path);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.image_outlined, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  path_util.basename(path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
              IconButton(
                tooltip: 'Remove photo',
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          if (file.existsSync())
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                file,
                width: double.infinity,
                height: 190,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Text('Could not display this photo.'),
              ),
            )
          else
            const Text('Photo file is unavailable.', style: TextStyle(color: AppColors.textHint)),
        ],
      ),
    );
  }
}

class _EditableMediaRow extends StatelessWidget {
  const _EditableMediaRow({
    required this.icon,
    required this.title,
    required this.path,
    required this.onRemove,
    required this.player,
  });
  final IconData icon;
  final String title;
  final String path;
  final VoidCallback onRemove;
  final Widget player;

  @override
  Widget build(BuildContext context) => Card(
        color: AppColors.surface,
        margin: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: <Widget>[
            const SizedBox(width: 12),
            Icon(icon, color: AppColors.gold),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    path_util.basename(path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                  ),
                ],
              ),
            ),
            player,
            IconButton(
              tooltip: 'Remove attachment',
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      );
}

class _NoteAudioPlayer extends StatefulWidget {
  const _NoteAudioPlayer({super.key, required this.path});
  final String path;

  @override
  State<_NoteAudioPlayer> createState() => _NoteAudioPlayerState();
}

class _NoteAudioPlayerState extends State<_NoteAudioPlayer> {
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
  Widget build(BuildContext context) => IconButton(
        tooltip: _playing ? 'Pause audio' : 'Play audio',
        onPressed: _unavailable ? null : _toggle,
        icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
      );
}

class _EditableVideoAttachment extends StatelessWidget {
  const _EditableVideoAttachment({required this.path, required this.onRemove});
  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Card(
        color: AppColors.surface,
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.video_file_outlined, color: AppColors.gold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      path_util.basename(path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove video',
                    onPressed: onRemove,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            _NoteVideoPlayer(key: ValueKey<String>(path), path: path),
          ],
        ),
      );
}

class _NoteVideoPlayer extends StatefulWidget {
  const _NoteVideoPlayer({required this.path});
  final String path;

  @override
  State<_NoteVideoPlayer> createState() => _NoteVideoPlayerState();
}

class _NoteVideoPlayerState extends State<_NoteVideoPlayer> {
  VideoPlayerController? _controller;
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (!await File(widget.path).exists()) {
      if (mounted) setState(() => _unavailable = true);
      return;
    }
    if (!mounted) return;
    final VideoPlayerController controller =
        VideoPlayerController.file(File(widget.path));
    _controller = controller;
    controller.addListener(_onVideoUpdate);
    try {
      await controller.initialize();
      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      if (mounted) setState(() => _unavailable = true);
    }
  }

  void _onVideoUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    final VideoPlayerController? controller = _controller;
    if (controller != null) {
      controller.removeListener(_onVideoUpdate);
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? controller = _controller;
    if (_unavailable) {
      return const ListTile(
        leading: Icon(Icons.videocam_off_outlined),
        title: Text('Video is unavailable'),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      children: <Widget>[
        AspectRatio(
          aspectRatio: controller.value.aspectRatio > 0
              ? controller.value.aspectRatio
              : 16 / 9,
          child: VideoPlayer(controller),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: controller.value.isPlaying ? 'Pause video' : 'Play video',
            onPressed: () async {
              if (controller.value.isPlaying) {
                await controller.pause();
              } else {
                await controller.play();
              }
              if (mounted) setState(() {});
            },
            icon: Icon(
              controller.value.isPlaying
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_fill_rounded,
              size: 30,
            ),
          ),
        ),
      ],
    );
  }
}
