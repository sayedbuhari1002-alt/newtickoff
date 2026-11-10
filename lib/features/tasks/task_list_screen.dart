import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/date_utils.dart';
import '../../domain/logic/task_engine.dart';
import '../../domain/logic/habit_engine.dart';
import '../../domain/models/models.dart';
import '../../shared/widgets/empty_state.dart';
import '../../state/app_data.dart';
import '../../state/app_state.dart';
import 'habit_task_card.dart';
import 'task_card.dart';

class TaskListScreen extends ConsumerStatefulWidget {
  const TaskListScreen({super.key});
  @override
  ConsumerState<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends ConsumerState<TaskListScreen> {
  TaskListFilter _filter = TaskListFilter.all;
  TaskSort _sort = TaskSort.defaultOrder;
  String? _category;
  late DateTime _selectedDate;
  bool _includeCompleted = true;
  bool _selectionMode = false;
  final Set<String> _selectedTaskIds = <String>{};
  final Set<String> _expandedGroups = <String>{};

  @override
  void initState() {
    super.initState();
    _selectedDate = dateOnly(ref.read(todayProvider));
  }

  Future<void> _chooseDate() async {
    final DateTime now = DateTime.now();
    final DateTime? value = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(now.year - 10), lastDate: DateTime(now.year + 15));
    if (value != null && mounted) setState(() { _selectedDate = value; _filter = TaskListFilter.selectedDate; });
  }

  void _startSelection(String taskId) {
    setState(() {
      _selectionMode = true;
      _selectedTaskIds.add(taskId);
    });
  }

  void _toggleSelection(String taskId) {
    setState(() {
      if (!_selectedTaskIds.add(taskId)) _selectedTaskIds.remove(taskId);
      if (_selectedTaskIds.isEmpty) _selectionMode = false;
    });
  }

  void _clearSelection() => setState(() { _selectionMode = false; _selectedTaskIds.clear(); });

  Future<void> _createParentGroup() async {
    if (_selectedTaskIds.isEmpty) return;
    final TextEditingController title = TextEditingController();
    final bool? create = await showDialog<bool>(context: context, builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text('Create parent task'),
      content: TextField(controller: title, autofocus: true, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Parent task name', hintText: 'Mathematics Revision')),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, title.text.trim().isNotEmpty), child: const Text('Create Group')),
      ],
    ));
    if (create == true && mounted) {
      try {
        final Task? parent = await ref.read(appDataProvider.notifier).createTaskGroup(title.text.trim(), _selectedTaskIds.toList());
        _clearSelection();
        if (parent != null && mounted) context.push(AppRoutes.taskDetail(parent.id));
      } catch (error) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
    title.dispose();
  }

  Future<void> _moveToExistingGroup(AppData data) async {
    final List<Task> groups = data.tasks.where((Task task) => task.parentTaskId == null && !_selectedTaskIds.contains(task.id)).toList();
    if (groups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Create a parent task first, then move tasks into it.')));
      return;
    }
    final Task? target = await showModalBottomSheet<Task>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(child: ListView(shrinkWrap: true, children: <Widget>[
        const Padding(padding: EdgeInsets.fromLTRB(20, 4, 20, 12), child: Text('Move selected tasks into', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
        for (final Task group in groups.where((Task item) => !_selectedTaskIds.contains(item.id)))
          ListTile(title: Text(group.title), subtitle: Text('${data.childrenForTask(group.id).length} child task(s)'), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => Navigator.pop(sheetContext, group)),
      ])),
    );
    if (target == null || !mounted) return;
    try {
      await ref.read(appDataProvider.notifier).moveTasksToGroup(_selectedTaskIds.toList(), target.id);
      _clearSelection();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _postponeSelected() async {
    if (_selectedTaskIds.isEmpty) return;
    final int? days = await showModalBottomSheet<int>(context: context, showDragHandle: true, builder: (BuildContext sheetContext) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
      const Padding(padding: EdgeInsets.all(16), child: Text('Postpone selected tasks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
      ListTile(title: const Text('Tomorrow'), onTap: () => Navigator.pop(sheetContext, 1)),
      ListTile(title: const Text('In 3 days'), onTap: () => Navigator.pop(sheetContext, 3)),
      ListTile(title: const Text('Next week'), onTap: () => Navigator.pop(sheetContext, 7)),
    ])));
    if (days == null || !mounted) return;
    try {
      for (final String id in _selectedTaskIds.toList()) {
        await ref.read(appDataProvider.notifier).postponeTask(id, days: days);
      }
      _clearSelection();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _duplicateSelected() async {
    try {
      for (final String id in _selectedTaskIds.toList()) {
        await ref.read(appDataProvider.notifier).duplicateTask(id);
      }
      _clearSelection();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _deleteSelected() async {
    final bool confirmed = await showDialog<bool>(context: context, builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text('Delete selected tasks?'),
      content: Text('${_selectedTaskIds.length} selected task(s) will be deleted. Their activity history will remain.'),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
      ],
    )) ?? false;
    if (!confirmed || !mounted) return;
    try {
      for (final String id in _selectedTaskIds.toList()) {
        await ref.read(appDataProvider.notifier).deleteTask(id);
      }
      _clearSelection();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<AppData> async = ref.watch(appDataProvider);
    final DateTime currentDay = ref.watch(todayProvider);
    return Scaffold(
      body: SafeArea(bottom: false, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Padding(padding: const EdgeInsets.fromLTRB(AppDimens.pagePadding, 12, 12, 4), child: Row(children: <Widget>[
          Expanded(child: Text(_selectionMode ? '${_selectedTaskIds.length} selected' : 'Tasks', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800))),
          if (_selectionMode) ...<Widget>[
            IconButton(tooltip: 'Select all visible tasks', onPressed: () => async.whenData((AppData data) {
              final List<Task> filtered = filterAndSortTasks(data.tasks, filter: _filter, selectedDate: _selectedDate, category: _category, sort: _sort, includeCompleted: _includeCompleted, todayOverride: currentDay);
              setState(() => _selectedTaskIds.addAll(filtered.where((Task task) => !data.isGroupTask(task) && data.childrenForTask(task.id).isEmpty).map((Task task) => task.id)));
            }), icon: const Icon(Icons.select_all_rounded)),
            IconButton(tooltip: 'Cancel selection', onPressed: _clearSelection, icon: const Icon(Icons.close_rounded)),
          ] else ...<Widget>[
            IconButton(tooltip: 'Task templates', onPressed: () => context.push(AppRoutes.taskTemplates), icon: const Icon(Icons.bookmarks_outlined)),
            IconButton(tooltip: 'Analytics', onPressed: () => context.push(AppRoutes.analytics), icon: const Icon(Icons.analytics_outlined)),
            IconButton(tooltip: 'Add task', onPressed: () => context.push(AppRoutes.taskNew), icon: const Icon(Icons.add_circle_outline_rounded)),
          ],
        ])),
        if (!_selectionMode) ...<Widget>[
          SizedBox(height: 46, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: AppDimens.pagePadding), children: <Widget>[
            _FilterChip(label: 'All Tasks', selected: _filter == TaskListFilter.all, onTap: () => setState(() => _filter = TaskListFilter.all)),
            _FilterChip(label: 'Today', selected: _filter == TaskListFilter.today, onTap: () => setState(() { _filter = TaskListFilter.today; _selectedDate = ref.read(todayProvider); })),
            _FilterChip(label: 'Due Tasks', selected: _filter == TaskListFilter.due, onTap: () => setState(() { _filter = TaskListFilter.due; _selectedDate = ref.read(todayProvider); })),
            _FilterChip(label: _filter == TaskListFilter.selectedDate ? '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}' : 'Browse date', selected: _filter == TaskListFilter.selectedDate, onTap: _chooseDate, icon: Icons.calendar_month_outlined),
          ])),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppDimens.pagePadding, 6, AppDimens.pagePadding, 8),
            child: Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
              async.maybeWhen(
                data: (AppData data) {
                  final Set<String> categoryNames = <String>{
                    ...data.tasks.map((Task t) => t.category.trim()).where((String c) => c.isNotEmpty),
                    ...data.sortedCategories.map((HabitCategory c) => c.name.trim()).where((String c) => c.isNotEmpty),
                  };
                  final List<String> categories = categoryNames.toList()..sort();
                  return _SmallDropdown<String?>(label: _category ?? 'All categories', value: _category, items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(value: null, child: Text('All categories')),
                    for (final String c in categories) DropdownMenuItem<String?>(value: c, child: Text(c)),
                  ], onChanged: (String? value) => setState(() => _category = value));
                },
                orElse: () => const SizedBox.shrink(),
              ),
              _SmallDropdown<TaskSort>(label: _sortLabel(_sort), value: _sort, items: const <DropdownMenuItem<TaskSort>>[
                DropdownMenuItem(value: TaskSort.defaultOrder, child: Text('Default order')),
                DropdownMenuItem(value: TaskSort.priority, child: Text('Priority order')),
                DropdownMenuItem(value: TaskSort.deadline, child: Text('Deadline')),
                DropdownMenuItem(value: TaskSort.categoryAscending, child: Text('Category A–Z')),
                DropdownMenuItem(value: TaskSort.categoryDescending, child: Text('Category Z–A')),
              ], onChanged: (TaskSort? value) => setState(() => _sort = value ?? TaskSort.defaultOrder)),
              FilterChip(label: const Text('Completed'), selected: _includeCompleted, onSelected: (bool value) => setState(() => _includeCompleted = value)),
            ]),
          ),
        ],
        Expanded(child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace _) => EmptyState(icon: Icons.error_outline_rounded, title: 'Could not load tasks', message: '$error'),
          data: (AppData data) {
            final List<Task> filteredTasks = filterAndSortTasks(data.tasks, filter: _filter, selectedDate: _selectedDate, category: _category, sort: _sort, includeCompleted: _includeCompleted, todayOverride: currentDay);
            final Set<String> visibleIds = filteredTasks.map((Task task) => task.id).toSet();
            final Map<String, Task> roots = <String, Task>{};
            final List<String> rootOrder = <String>[];
            for (final Task task in filteredTasks) {
              final Task root = task.parentTaskId == null ? task : (data.taskById(task.parentTaskId!) ?? task);
              if (!roots.containsKey(root.id)) rootOrder.add(root.id);
              roots[root.id] = root;
            }
            final List<Task> topLevelTasks = rootOrder.map((String id) => roots[id]!).toList();
            final HabitEngine habitEngine = HabitEngine(today: currentDay);
            final List<Habit> habits = data.activeHabits.where((Habit habit) {
              if (habit.type != HabitType.build) return false;
              final String habitCategory = data.categoryById(habit.categoryId)?.name ?? '';
              if (_category != null && _category!.isNotEmpty && habitCategory != _category) return false;
              if (_filter != TaskListFilter.all && !habitEngine.isScheduledOn(habit, _selectedDate, data.recordsFor(habit.id))) return false;
              if (!_includeCompleted && habitEngine.isCompleted(habit, data.recordsFor(habit.id)[dateKey(_selectedDate)])) return false;
              return true;
            }).toList()
              ..sort((Habit a, Habit b) {
                final int order = a.sortOrder.compareTo(b.sortOrder);
                return order != 0 ? order : a.title.toLowerCase().compareTo(b.title.toLowerCase());
              });

            if (topLevelTasks.isEmpty && habits.isEmpty) return const EmptyState(icon: Icons.task_alt_rounded, title: 'No tasks to show', message: 'Add a task or adjust your filters.');
            final int totalItems = topLevelTasks.length + habits.length;
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(AppDimens.pagePadding, 4, AppDimens.pagePadding, 24),
              itemCount: totalItems,
              separatorBuilder: (_, int i) => const SizedBox(height: 10),
              itemBuilder: (BuildContext context, int i) {
                if (i < topLevelTasks.length) {
                  final Task task = topLevelTasks[i];
                  final List<Task> children = data.childrenForTask(task.id).where((Task child) => visibleIds.contains(child.id)).toList();
                  if (data.isGroupTask(task)) {
                    final bool expanded = !_expandedGroups.contains(task.id) || _selectionMode;
                    return _TaskGroupCard(
                      parent: task,
                      children: children,
                      totalChildren: data.childrenForTask(task.id).length,
                      completedChildren: data.childrenForTask(task.id).where((Task child) => child.isCompleted).length,
                      progress: data.progressForTask(task),
                      expanded: expanded,
                      onOpen: () => context.push(AppRoutes.taskDetail(task.id)),
                      onToggleExpanded: () => setState(() { if (expanded) _expandedGroups.add(task.id); else _expandedGroups.remove(task.id); }),
                      selectionMode: _selectionMode,
                      selectedIds: _selectedTaskIds,
                      onChildOpen: (Task child) => context.push(AppRoutes.taskDetail(child.id)),
                      onChildSelect: (Task child) => _toggleSelection(child.id),
                      onChildLongPress: (Task child) => _startSelection(child.id),
                      onChildToggle: (Task child, bool done) async {
                        try { await ref.read(appDataProvider.notifier).setTaskCompleted(child.id, done); }
                        catch (error) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error'))); }
                      },
                      onChildProgress: (Task child, double value) async {
                        try { await ref.read(appDataProvider.notifier).updateTaskProgress(child.id, value); }
                        catch (error) {
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
                          rethrow;
                        }
                      },
                      selectedDate: _selectedDate,
                      showOverdue: _filter == TaskListFilter.today,
                    );
                  }
                  return TaskCard(
                    key: ValueKey<String>(task.id), task: task, selectedDate: _selectedDate,
                    showOverdue: _filter == TaskListFilter.today,
                    selectionMode: _selectionMode, selected: _selectedTaskIds.contains(task.id),
                    onSelect: () => _toggleSelection(task.id), onLongPress: () => _startSelection(task.id),
                    onOpen: () => context.push(AppRoutes.taskDetail(task.id)),
                    onToggle: (bool done) async {
                      try { await ref.read(appDataProvider.notifier).setTaskCompleted(task.id, done); }
                      catch (error) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error'))); }
                    },
                    onProgressChanged: (double value) async {
                      try { await ref.read(appDataProvider.notifier).updateTaskProgress(task.id, value); }
                      catch (error) {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
                        rethrow;
                      }
                    },
                  );
                }
                final Habit habit = habits[i - topLevelTasks.length];
                final CompletionRecord? record = data.recordsFor(habit.id)[dateKey(_selectedDate)];
                return HabitTaskCard(
                  key: ValueKey<String>('habit-${habit.id}'), habit: habit, engine: habitEngine, record: record,
                  onOpen: () => context.push(AppRoutes.habitDetail(habit.id, date: _selectedDate)),
                  onToggle: (bool done) async {
                    try { await ref.read(appDataProvider.notifier).toggleTick(habit, _selectedDate); }
                    catch (error) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error'))); }
                  },
                );
              },
            );
          },
        )),
        if (_selectionMode)
          SafeArea(top: false, child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.border))),
            child: async.maybeWhen(data: (AppData data) => Wrap(alignment: WrapAlignment.spaceAround, spacing: 8, runSpacing: 6, children: <Widget>[
              _BulkAction(icon: Icons.create_new_folder_outlined, label: 'New parent', onTap: _createParentGroup),
              _BulkAction(icon: Icons.drive_file_move_outline, label: 'Move', onTap: () => _moveToExistingGroup(data)),
              _BulkAction(icon: Icons.event_repeat_outlined, label: 'Postpone', onTap: _postponeSelected),
              _BulkAction(icon: Icons.copy_outlined, label: 'Duplicate', onTap: _duplicateSelected),
              _BulkAction(icon: Icons.delete_outline_rounded, label: 'Delete', color: AppColors.danger, onTap: _deleteSelected),
            ]), orElse: () => const SizedBox.shrink()),
          )),
      ])),
    );
  }
}

class _TaskGroupCard extends StatelessWidget {
  const _TaskGroupCard({
    required this.parent, required this.children, required this.totalChildren,
    required this.completedChildren, required this.progress,
    required this.expanded, required this.onOpen, required this.onToggleExpanded,
    required this.selectionMode, required this.selectedIds, required this.onChildOpen,
    required this.onChildSelect, required this.onChildLongPress, required this.onChildToggle,
    required this.onChildProgress,
    required this.selectedDate, required this.showOverdue,
  });
  final Task parent;
  final List<Task> children;
  final int totalChildren;
  final int completedChildren;
  final double progress;
  final bool expanded;
  final VoidCallback onOpen;
  final VoidCallback onToggleExpanded;
  final bool selectionMode;
  final Set<String> selectedIds;
  final ValueChanged<Task> onChildOpen;
  final ValueChanged<Task> onChildSelect;
  final ValueChanged<Task> onChildLongPress;
  final void Function(Task, bool) onChildToggle;
  final Future<void> Function(Task, double) onChildProgress;
  final DateTime selectedDate;
  final bool showOverdue;

  @override
  Widget build(BuildContext context) {
    return Column(children: <Widget>[
      Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16), onTap: onOpen,
          child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Row(children: <Widget>[
              Icon(Icons.folder_open_rounded, color: AppColors.gold),
              const SizedBox(width: 10),
              Expanded(child: Text(parent.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
              Text('${(progress * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w700)),
              IconButton(tooltip: expanded ? 'Collapse group' : 'Expand group', onPressed: onToggleExpanded, icon: Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: progress.clamp(0, 1), minHeight: 6, backgroundColor: AppColors.border, color: AppColors.gold)),
            const SizedBox(height: 4),
            Text('$completedChildren of $totalChildren child task(s) completed', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ])),
        ),
      ),
      if (expanded)
        Padding(
          padding: const EdgeInsets.only(left: 14, top: 7),
          child: Column(children: <Widget>[
            for (final Task child in children) ...<Widget>[
              TaskCard(
                key: ValueKey<String>(child.id), task: child, selectedDate: selectedDate,
                showOverdue: showOverdue, selectionMode: selectionMode,
                selected: selectedIds.contains(child.id),
                onSelect: () => onChildSelect(child), onLongPress: () => onChildLongPress(child),
                onOpen: () => onChildOpen(child), onToggle: (bool done) => onChildToggle(child, done),
                onProgressChanged: (double value) => onChildProgress(child, value),
              ),
              const SizedBox(height: 7),
            ],
          ]),
        ),
    ]);
  }
}

class _BulkAction extends StatelessWidget {
  const _BulkAction({required this.icon, required this.label, required this.onTap, this.color});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  @override
  Widget build(BuildContext context) => TextButton.icon(onPressed: onTap, icon: Icon(icon, size: 18, color: color), label: Text(label, style: TextStyle(color: color)));
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
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 10), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)), child: DropdownButton<T>(value: value, underline: const SizedBox.shrink(), isDense: true, items: items, onChanged: onChanged));
}

String _sortLabel(TaskSort sort) => switch (sort) { TaskSort.defaultOrder => 'Default order', TaskSort.priority => 'Priority', TaskSort.deadline => 'Deadline', TaskSort.categoryAscending => 'Category A–Z', TaskSort.categoryDescending => 'Category Z–A' };
