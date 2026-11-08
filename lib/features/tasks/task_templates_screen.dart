import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/ids.dart';
import '../../core/router/routes.dart';
import 'package:go_router/go_router.dart';
import '../../domain/models/models.dart';
import '../../state/app_data.dart';
import '../../state/app_state.dart';

class TaskTemplatesScreen extends ConsumerWidget {
  const TaskTemplatesScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, TaskTemplate template) async {
    final TextEditingController name = TextEditingController(text: template.name);
    final TextEditingController category = TextEditingController(text: template.category);
    final TextEditingController difficulty = TextEditingController(text: template.difficultyScore.toString());
    final TextEditingController target = TextEditingController(text: template.progressTarget.toString());
    final TextEditingController unit = TextEditingController(text: template.progressUnit);
    TaskType type = template.taskType;
    TaskProgressMode mode = template.progressMode;
    TaskPriority priority = template.priority;
    TaskRepeat repeat = template.repeat;
    final bool? save = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext dialogContext, StateSetter setDialogState) => AlertDialog(
          title: const Text('Edit task template'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Template name')),
                const SizedBox(height: 8),
                DropdownButtonFormField<TaskType>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Task type'),
                  items: const <DropdownMenuItem<TaskType>>[
                    DropdownMenuItem(value: TaskType.standard, child: Text('Standard')),
                    DropdownMenuItem(value: TaskType.progressive, child: Text('Progressive')),
                  ],
                  onChanged: (TaskType? value) => setDialogState(() => type = value ?? TaskType.standard),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<TaskPriority>(
                  value: priority,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: TaskPriority.values.map((TaskPriority value) => DropdownMenuItem(value: value, child: Text(value.name))).toList(),
                  onChanged: (TaskPriority? value) => setDialogState(() => priority = value ?? TaskPriority.medium),
                ),
                const SizedBox(height: 8),
                TextField(controller: difficulty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Difficulty (1–5)')),
                const SizedBox(height: 8),
                TextField(controller: category, decoration: const InputDecoration(labelText: 'Category')),
                if (type == TaskType.progressive) ...<Widget>[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<TaskProgressMode>(
                    value: mode,
                    decoration: const InputDecoration(labelText: 'Progress method'),
                    items: const <DropdownMenuItem<TaskProgressMode>>[
                      DropdownMenuItem(value: TaskProgressMode.percentage, child: Text('Percentage')),
                      DropdownMenuItem(value: TaskProgressMode.count, child: Text('Count / target')),
                    ],
                    onChanged: (TaskProgressMode? value) => setDialogState(() => mode = value ?? TaskProgressMode.percentage),
                  ),
                  if (mode == TaskProgressMode.count) ...<Widget>[
                    const SizedBox(height: 8),
                    TextField(controller: target, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Count target')),
                    const SizedBox(height: 8),
                    TextField(controller: unit, decoration: const InputDecoration(labelText: 'Unit')),
                  ],
                ],
                const SizedBox(height: 8),
                DropdownButtonFormField<TaskRepeat>(
                  value: repeat,
                  decoration: const InputDecoration(labelText: 'Repeat'),
                  items: const <DropdownMenuItem<TaskRepeat>>[
                    DropdownMenuItem(value: TaskRepeat.none, child: Text('Does not repeat')),
                    DropdownMenuItem(value: TaskRepeat.daily, child: Text('Every day')),
                    DropdownMenuItem(value: TaskRepeat.weekly, child: Text('Every week')),
                    DropdownMenuItem(value: TaskRepeat.monthly, child: Text('Every month')),
                  ],
                  onChanged: (TaskRepeat? value) => setDialogState(() => repeat = value ?? TaskRepeat.none),
                ),
              ]),
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, name.text.trim().isNotEmpty), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (save == true && context.mounted) {
      final double? parsedDifficulty = double.tryParse(difficulty.text.trim());
      final double? parsedTarget = double.tryParse(target.text.trim());
      if (parsedDifficulty == null || parsedDifficulty < 1 || parsedDifficulty > 5 || (type == TaskType.progressive && mode == TaskProgressMode.count && (parsedTarget == null || parsedTarget <= 0))) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Check the difficulty and progress target values.')));
      } else {
        try {
          await ref.read(appDataProvider.notifier).saveTaskTemplate(template.copyWith(
            name: name.text.trim(), category: category.text.trim(), difficultyScore: parsedDifficulty,
            taskType: type, progressMode: mode,
            progressTarget: mode == TaskProgressMode.percentage ? 100 : parsedTarget!,
            progressUnit: unit.text.trim(), priority: priority, repeat: repeat,
          ));
        } catch (error) {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
        }
      }
    }
    name.dispose(); category.dispose(); difficulty.dispose(); target.dispose(); unit.dispose();
  }

  Future<void> _duplicate(BuildContext context, WidgetRef ref, TaskTemplate template) async {
    final TextEditingController name = TextEditingController(text: '${template.name} Copy');
    final bool? confirm = await showDialog<bool>(context: context, builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text('Duplicate template'),
      content: TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'New template name')),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, name.text.trim().isNotEmpty), child: const Text('Duplicate')),
      ],
    ));
    if (confirm == true && context.mounted) {
      final DateTime now = DateTime.now();
      try {
        await ref.read(appDataProvider.notifier).saveTaskTemplate(TaskTemplate(
          id: newId(), name: name.text.trim(), createdAt: now, updatedAt: now,
          taskType: template.taskType, progressMode: template.progressMode,
          progressTarget: template.progressTarget, progressUnit: template.progressUnit,
          difficultyScore: template.difficultyScore, priority: template.priority,
          category: template.category, iconKey: template.iconKey,
          colorValue: template.colorValue, repeat: template.repeat,
        ));
      } catch (error) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
    name.dispose();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<AppData> async = ref.watch(appDataProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Task Templates')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => Center(child: Text('$error')),
        data: (AppData data) {
          if (data.taskTemplates.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(28), child: Text('No task templates yet. Open task creation and save reusable settings as a template.')));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: data.taskTemplates.length,
            separatorBuilder: (_, int index) => const SizedBox(height: 8),
            itemBuilder: (BuildContext context, int index) {
              final TaskTemplate template = data.taskTemplates[index];
              final String progressLabel = template.taskType == TaskType.standard
                  ? 'Standard'
                  : template.progressMode == TaskProgressMode.percentage
                      ? 'Progressive · Percentage'
                      : 'Progressive · ${template.progressTarget.toStringAsFixed(template.progressTarget == template.progressTarget.roundToDouble() ? 0 : 1)} ${template.progressUnit}'.trim();
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.bookmark_outline_rounded),
                  title: Text(template.name),
                  subtitle: Text('$progressLabel · ${template.priority.name} priority · Difficulty ${template.difficultyScore} · ${template.category.isEmpty ? 'Uncategorised' : template.category}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (String action) async {
                      if (action == 'edit') await _edit(context, ref, template);
                      if (action == 'duplicate') await _duplicate(context, ref, template);
                      if (action == 'delete') {
                        final bool confirmed = await showDialog<bool>(context: context, builder: (BuildContext dialogContext) => AlertDialog(
                          title: const Text('Delete template?'),
                          content: Text('"${template.name}" will be removed. Tasks already created from it will not be affected.'),
                          actions: <Widget>[
                            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
                            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
                          ],
                        )) ?? false;
                        if (confirmed && context.mounted) await ref.read(appDataProvider.notifier).deleteTaskTemplate(template.id);
                      }
                    },
                    itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                  onTap: () => context.push(AppRoutes.taskNew, extra: template),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
