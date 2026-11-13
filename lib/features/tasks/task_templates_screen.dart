import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/ids.dart';
import '../../core/router/routes.dart';
import 'package:go_router/go_router.dart';
import '../../domain/models/models.dart';
import '../../state/app_data.dart';
import '../../state/app_state.dart';
import 'task_template_editor_screen.dart';

class TaskTemplatesScreen extends ConsumerWidget {
  const TaskTemplatesScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, TaskTemplate template) async {
    await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
      builder: (BuildContext _) => TaskTemplateEditorScreen(template: template),
    ));
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
          notes: template.notes,
          photoPaths: List<String>.of(template.photoPaths),
          audioPaths: List<String>.of(template.audioPaths),
          subtasks: <Subtask>[
            for (int index = 0; index < template.subtasks.length; index++)
              Subtask(
                id: newId(), title: template.subtasks[index].title,
                createdAt: now, sortOrder: index,
                difficultyScore: template.subtasks[index].difficultyScore,
              ),
          ],
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
                  subtitle: Text('$progressLabel · ${template.priority.name} priority · Difficulty ${template.difficultyScore} · ${template.category.isEmpty ? 'Uncategorised' : template.category}\n${template.subtasks.length} subtasks · ${template.photoPaths.length} photos · ${template.audioPaths.length} audio notes${template.notes.trim().isEmpty ? '' : ' · Notes'}'),
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
