import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/ids.dart';
import '../../domain/models/models.dart';

class SubtaskEditorScreen extends StatefulWidget {
  const SubtaskEditorScreen({super.key, this.initial = const <Subtask>[]});
  final List<Subtask> initial;
  @override
  State<SubtaskEditorScreen> createState() => _SubtaskEditorScreenState();
}

class _SubtaskEditorScreenState extends State<SubtaskEditorScreen> {
  late List<Subtask> _items;
  @override
  void initState() { super.initState(); _items = List<Subtask>.of(widget.initial); }

  Future<void> _addOrEdit({Subtask? existing, int? index}) async {
    final TextEditingController title = TextEditingController(text: existing?.title ?? '');
    DateTime? dueAt = existing?.dueAt;
    final bool? save = await showDialog<bool>(context: context, builder: (BuildContext context) => StatefulBuilder(builder: (BuildContext context, StateSetter setDialogState) => AlertDialog(
      title: Text(existing == null ? 'Add subtask' : 'Edit subtask'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        TextField(controller: title, autofocus: true, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Subtask name')),
        const SizedBox(height: 12),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.event_outlined), title: const Text('Optional deadline'), subtitle: Text(dueAt == null ? 'No deadline' : '${dueAt!.day}/${dueAt!.month}/${dueAt!.year} ${dueAt!.hour == 0 && dueAt!.minute == 0 ? '' : TimeOfDay.fromDateTime(dueAt!).format(context)}'), onTap: () async {
          final DateTime now = DateTime.now();
          final DateTime? day = await showDatePicker(context: context, initialDate: dueAt ?? now, firstDate: DateTime(now.year - 10), lastDate: DateTime(now.year + 15));
          if (day == null || !context.mounted) return;
          final TimeOfDay? time = await showTimePicker(context: context, initialTime: dueAt == null ? const TimeOfDay(hour: 0, minute: 0) : TimeOfDay.fromDateTime(dueAt!));
          if (!context.mounted) return;
          // Cancelling the time picker keeps the chosen date at midnight;
          // users can still set a specific time by selecting one.
          setDialogState(() => dueAt = DateTime(day.year, day.month, day.day, time?.hour ?? 0, time?.minute ?? 0));
        }),
        if (dueAt != null) Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => setDialogState(() => dueAt = null), child: const Text('Clear deadline'))),
      ])),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (title.text.trim().isEmpty) return; Navigator.pop(context, true); }, child: const Text('Save')),
      ],
    )));
    if (save == true && mounted) {
      final DateTime now = DateTime.now();
      setState(() {
        final Subtask value = Subtask(id: existing?.id ?? newId(), title: title.text.trim(), createdAt: existing?.createdAt ?? now, dueAt: dueAt, isCompleted: existing?.isCompleted ?? false, completedAt: existing?.completedAt, sortOrder: index ?? _items.length);
        if (index == null) _items.add(value); else _items[index] = value;
        _renumber();
      });
    }
    title.dispose();
  }

  void _renumber() => _items = <Subtask>[for (int i = 0; i < _items.length; i++) _items[i].copyWith(sortOrder: i)];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Subtask Editor'), actions: <Widget>[TextButton(onPressed: () => context.pop(_items), child: const Text('Done'))]),
    body: SafeArea(child: Column(children: <Widget>[
      Padding(padding: const EdgeInsets.all(16), child: Row(children: <Widget>[
        Expanded(child: Text('${_items.where((Subtask s) => s.isCompleted).length} of ${_items.length} complete', style: const TextStyle(color: AppColors.textSecondary))),
        FilledButton.icon(onPressed: () => _addOrEdit(), icon: const Icon(Icons.add), label: const Text('Add')),
      ])),
      if (_items.isNotEmpty) LinearProgressIndicator(value: _items.isEmpty ? 0 : _items.where((Subtask s) => s.isCompleted).length / _items.length, minHeight: 3),
      Expanded(child: _items.isEmpty ? const Center(child: Text('Add smaller steps to break down the task.')) : ReorderableListView.builder(
        padding: const EdgeInsets.all(12), itemCount: _items.length,
        onReorder: (int oldIndex, int newIndex) { setState(() { if (newIndex > oldIndex) newIndex--; final Subtask item = _items.removeAt(oldIndex); _items.insert(newIndex, item); _renumber(); }); },
        itemBuilder: (BuildContext context, int index) { final Subtask item = _items[index]; return Card(key: ValueKey<String>(item.id), child: ListTile(
          leading: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Checkbox(value: item.isCompleted, onChanged: (bool? value) => setState(() {
              final DateTime now = DateTime.now();
              _items[index] = item.copyWith(
                isCompleted: value ?? false,
                completedAt: (value ?? false) ? (item.completedAt ?? now) : null,
                clearCompletedAt: !(value ?? false),
              );
            })),
            const Icon(Icons.drag_handle_rounded),
          ]), title: Text(item.title, style: TextStyle(decoration: item.isCompleted ? TextDecoration.lineThrough : null)),
          subtitle: Text(item.dueAt == null ? 'No deadline' : 'Due ${item.dueAt!.day}/${item.dueAt!.month}/${item.dueAt!.year}${item.dueAt!.hour == 0 && item.dueAt!.minute == 0 ? '' : ' · ${TimeOfDay.fromDateTime(item.dueAt!).format(context)}'}${item.dueAt!.isBefore(DateTime.now()) && !item.isCompleted ? ' · Overdue' : ''}'),
          trailing: PopupMenuButton<String>(onSelected: (String action) { if (action == 'edit') _addOrEdit(existing: item, index: index); if (action == 'delete') setState(() { _items.removeAt(index); _renumber(); }); }, itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'delete', child: Text('Remove'))]),
          onTap: () => _addOrEdit(existing: item, index: index),
        )); },
      )),
    ])),
  );
}
