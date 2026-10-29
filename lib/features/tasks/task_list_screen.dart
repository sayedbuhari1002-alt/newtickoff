import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../domain/logic/task_engine.dart';
import '../../domain/models/models.dart';
import '../../shared/widgets/empty_state.dart';
import '../../state/app_data.dart';
import '../../state/app_state.dart';
import 'task_card.dart';

class TaskListScreen extends ConsumerStatefulWidget {
  const TaskListScreen({super.key});
  @override
  ConsumerState<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends ConsumerState<TaskListScreen> {
  TaskListFilter _filter = TaskListFilter.all;
  TaskSort _sort = TaskSort.defaultOrder;
  TaskPriority? _priority;
  String? _category;
  DateTime _selectedDate = DateTime.now();
  bool _includeCompleted = true;

  Future<void> _chooseDate() async {
    final DateTime now = DateTime.now();
    final DateTime? value = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(now.year - 10), lastDate: DateTime(now.year + 15));
    if (value != null && mounted) setState(() { _selectedDate = value; _filter = TaskListFilter.selectedDate; });
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<AppData> async = ref.watch(appDataProvider);
    return Scaffold(
      body: SafeArea(bottom: false, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Padding(padding: const EdgeInsets.fromLTRB(AppDimens.pagePadding, 12, 12, 4), child: Row(children: <Widget>[
          const Expanded(child: Text('Tasks', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800))),
          IconButton(tooltip: 'Task analytics', onPressed: () => context.push(AppRoutes.taskAnalytics), icon: const Icon(Icons.insights_rounded)),
          IconButton(tooltip: 'Add task', onPressed: () => context.push(AppRoutes.taskNew), icon: const Icon(Icons.add_circle_outline_rounded)),
        ])),
        SizedBox(height: 46, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: AppDimens.pagePadding), children: <Widget>[
          _FilterChip(label: 'All Tasks', selected: _filter == TaskListFilter.all, onTap: () => setState(() => _filter = TaskListFilter.all)),
          _FilterChip(label: 'Today', selected: _filter == TaskListFilter.today, onTap: () => setState(() { _filter = TaskListFilter.today; _selectedDate = DateTime.now(); })),
          _FilterChip(label: 'Due Tasks', selected: _filter == TaskListFilter.due, onTap: () => setState(() { _filter = TaskListFilter.due; _selectedDate = DateTime.now(); })),
          _FilterChip(label: _filter == TaskListFilter.selectedDate ? '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}' : 'Browse date', selected: _filter == TaskListFilter.selectedDate, onTap: _chooseDate, icon: Icons.calendar_month_outlined),
        ])),
        Padding(padding: const EdgeInsets.fromLTRB(AppDimens.pagePadding, 6, AppDimens.pagePadding, 8), child: Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
          _SmallDropdown<TaskPriority?>(label: _priority == null ? 'All priorities' : _priority!.name, value: _priority, items: <DropdownMenuItem<TaskPriority?>>[
            const DropdownMenuItem<TaskPriority?>(value: null, child: Text('All priorities')),
            for (final TaskPriority p in TaskPriority.values) DropdownMenuItem<TaskPriority?>(value: p, child: Text('${p.name[0].toUpperCase()}${p.name.substring(1)}')),
          ], onChanged: (TaskPriority? p) => setState(() => _priority = p)),
          async.maybeWhen(data: (AppData data) {
            final List<String> categories = data.tasks.map((Task t) => t.category.trim()).where((String c) => c.isNotEmpty).toSet().toList()..sort();
            return _SmallDropdown<String?>(label: _category ?? 'All categories', value: _category, items: <DropdownMenuItem<String?>>[
              const DropdownMenuItem<String?>(value: null, child: Text('All categories')),
              for (final String c in categories) DropdownMenuItem<String?>(value: c, child: Text(c)),
            ], onChanged: (String? value) => setState(() => _category = value));
          }, orElse: () => const SizedBox.shrink()),
          _SmallDropdown<TaskSort>(label: _sortLabel(_sort), value: _sort, items: const <DropdownMenuItem<TaskSort>>[
            DropdownMenuItem(value: TaskSort.defaultOrder, child: Text('Default order')),
            DropdownMenuItem(value: TaskSort.priority, child: Text('Priority')),
            DropdownMenuItem(value: TaskSort.deadline, child: Text('Deadline')),
            DropdownMenuItem(value: TaskSort.categoryAscending, child: Text('Category A–Z')),
            DropdownMenuItem(value: TaskSort.categoryDescending, child: Text('Category Z–A')),
          ], onChanged: (TaskSort? value) => setState(() => _sort = value ?? TaskSort.defaultOrder)),
          FilterChip(label: const Text('Completed'), selected: _includeCompleted, onSelected: (bool value) => setState(() => _includeCompleted = value)),
        ])),
        Expanded(child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace _) => EmptyState(icon: Icons.error_outline_rounded, title: 'Could not load tasks', message: '$error'),
          data: (AppData data) {
            final List<Task> tasks = filterAndSortTasks(data.tasks, filter: _filter, selectedDate: _selectedDate, priority: _priority, category: _category, sort: _sort, includeCompleted: _includeCompleted);
            if (tasks.isEmpty) return const EmptyState(icon: Icons.task_alt_rounded, title: 'No tasks to show', message: 'Add a task or adjust your filters.');
            return ListView.separated(padding: const EdgeInsets.fromLTRB(AppDimens.pagePadding, 4, AppDimens.pagePadding, 24), itemCount: tasks.length, separatorBuilder: (_, int i) => const SizedBox(height: 10), itemBuilder: (BuildContext context, int i) {
              final Task task = tasks[i];
              return TaskCard(key: ValueKey<String>(task.id), task: task, selectedDate: _selectedDate, onOpen: () => context.push(AppRoutes.taskDetail(task.id)), onToggle: (bool done) async {
                try { await ref.read(appDataProvider.notifier).setTaskCompleted(task.id, done); } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
              });
            });
          },
        )),
      ])),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap, this.icon});
  final String label; final bool selected; final VoidCallback onTap; final IconData? icon;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(right: 7), child: ChoiceChip(selected: selected, label: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[if (icon != null) ...<Widget>[Icon(icon, size: 15), const SizedBox(width: 4)], Text(label)]), onSelected: (_) => onTap()));
}

class _SmallDropdown<T> extends StatelessWidget {
  const _SmallDropdown({required this.label, required this.value, required this.items, required this.onChanged});
  final String label; final T value; final List<DropdownMenuItem<T>> items; final ValueChanged<T?> onChanged;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 8), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)), child: DropdownButton<T>(value: value, items: items, onChanged: onChanged, underline: const SizedBox.shrink(), isDense: true, borderRadius: BorderRadius.circular(12), style: const TextStyle(fontSize: 12, color: AppColors.textPrimary), icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 17)));
}

String _sortLabel(TaskSort sort) => switch (sort) { TaskSort.defaultOrder => 'Default order', TaskSort.priority => 'Priority', TaskSort.deadline => 'Deadline', TaskSort.categoryAscending => 'Category A–Z', TaskSort.categoryDescending => 'Category Z–A' };
