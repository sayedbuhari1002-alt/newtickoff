import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/models/models.dart';
import '../../state/app_data.dart';
import '../../shared/widgets/empty_state.dart';

class NoteLibraryScreen extends ConsumerStatefulWidget {
  const NoteLibraryScreen({super.key});
  @override
  ConsumerState<NoteLibraryScreen> createState() => _NoteLibraryScreenState();
}

class _NoteLibraryScreenState extends ConsumerState<NoteLibraryScreen> {
  NoteType _filter = NoteType.daily;

  @override
  Widget build(BuildContext context) {
    final AppData? data = ref.watch(appDataProvider).valueOrNull;
    final List<Note> notes = (data?.notes ?? const <Note>[])
        .where((Note note) => note.habitId == null && note.noteType == _filter)
        .toList()
      ..sort((Note a, Note b) {
        final DateTime da = a.periodDate ?? a.logDate ?? a.updatedAt;
        final DateTime db = b.periodDate ?? b.logDate ?? b.updatedAt;
        return db.compareTo(da);
      });
    return Scaffold(
      appBar: AppBar(title: const Text('Notes Library')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New note'),
      ),
      body: data == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: <Widget>[
              SizedBox(
                height: 60,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  scrollDirection: Axis.horizontal,
                  children: <Widget>[
                    _filterChip(NoteType.daily, 'Daily'),
                    _filterChip(NoteType.general, 'General'),
                    _filterChip(NoteType.monthly, 'Monthly'),
                    _filterChip(NoteType.yearly, 'Yearly'),
                  ],
                ),
              ),
              Expanded(
                child: notes.isEmpty
                    ? EmptyState(
                        icon: Icons.sticky_note_2_outlined,
                        title: 'No ${_label(_filter).toLowerCase()} notes yet',
                        message: 'Create a note and it will stay organised in this category.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                        itemCount: notes.length,
                        separatorBuilder: (_, __) => Divider(color: AppColors.divider, height: 1),
                        itemBuilder: (BuildContext context, int index) => _LibraryNoteTile(note: notes[index]),
                      ),
              ),
            ]),
    );
  }

  Widget _filterChip(NoteType type, String label) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: _filter == type,
          onSelected: (_) => setState(() => _filter = type),
        ),
      );

  Future<void> _create() async {
    final NoteType? type = await showModalBottomSheet<NoteType>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          const Padding(padding: EdgeInsets.all(16), child: Text('Choose note type', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          for (final (NoteType, String, IconData) option in <(NoteType, String, IconData)>[
            (NoteType.daily, 'Daily note', Icons.today_outlined),
            (NoteType.general, 'General note', Icons.sticky_note_2_outlined),
            (NoteType.monthly, 'Monthly note', Icons.calendar_month_outlined),
            (NoteType.yearly, 'Yearly note', Icons.event_note_outlined),
          ])
            ListTile(leading: Icon(option.$3, color: AppColors.primaryAccent), title: Text(option.$2), onTap: () => Navigator.of(sheetContext).pop(option.$1)),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (type == null || !mounted) return;
    setState(() => _filter = type);
    context.push(AppRoutes.noteNew(noteType: type));
  }
}

class _LibraryNoteTile extends StatelessWidget {
  const _LibraryNoteTile({required this.note});
  final Note note;

  @override
  Widget build(BuildContext context) {
    final DateTime date = note.periodDate ?? note.logDate ?? note.updatedAt;
    final String period = switch (note.noteType) {
      NoteType.daily => '${date.day}/${date.month}/${date.year}',
      NoteType.general => 'General',
      NoteType.monthly => '${_month(date.month)} ${date.year}',
      NoteType.yearly => '${date.year}',
    };
    final String title = note.title.trim().isEmpty ? 'Untitled note' : note.title.trim();
    final int mediaCount = note.photoPaths.length + note.audioPaths.length + note.videoPaths.length;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: AppColors.accentDim, borderRadius: BorderRadius.circular(12)), child: Icon(Icons.sticky_note_2_outlined, color: AppColors.primaryAccent)),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(period, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        if (note.body.trim().isNotEmpty) Text(note.body.trim(), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        if (mediaCount > 0) Text('$mediaCount attachment${mediaCount == 1 ? '' : 's'}', style: TextStyle(color: AppColors.textHint, fontSize: 11)),
      ]),
      trailing: Icon(Icons.chevron_right_rounded, color: AppColors.textHint),
      onTap: () => context.push(AppRoutes.noteEdit(note.id)),
    );
  }
}

String _label(NoteType type) => switch (type) {
  NoteType.daily => 'Daily', NoteType.general => 'General', NoteType.monthly => 'Monthly', NoteType.yearly => 'Yearly',
};
String _month(int value) => const <String>['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][value - 1];
