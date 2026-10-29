import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/date_utils.dart';
import '../../domain/logic/habit_engine.dart';
import '../../domain/logic/task_engine.dart';
import '../../domain/models/models.dart';
import '../../shared/widgets/widgets.dart';
import '../../state/app_data.dart';
import '../../state/app_state.dart';
import '../tasks/task_card.dart';
import 'dashboard_providers.dart';

/// Overview of the selected day: task and habit progress are kept independent.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DateTime today = ref.watch(todayProvider);
    final DateTime selected = ref.watch(selectedDateProvider);
    final AsyncValue<AppData> async = ref.watch(appDataProvider);
    return Scaffold(
      body: SafeArea(bottom: false, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Padding(padding: const EdgeInsets.fromLTRB(AppDimens.pagePadding, 10, 10, 0), child: Row(children: <Widget>[
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text('${headerPrefix(selected, today)}, ${dayMonthLabel(selected)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            const Text('Your day, at a glance', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ])),
          IconButton(tooltip: 'Task analytics', icon: const Icon(Icons.insights_outlined), onPressed: () => context.push(AppRoutes.taskAnalytics)),
          IconButton(tooltip: 'Settings', icon: const Icon(Icons.settings_outlined), onPressed: () => context.push(AppRoutes.settings)),
        ])),
        const SizedBox(height: 10),
        DateStrip(today: today, selected: selected, onSelected: (DateTime day) => ref.read(selectedDateProvider.notifier).select(day)),
        const SizedBox(height: 12),
        Expanded(child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace _) => EmptyState(icon: Icons.error_outline_rounded, title: 'Could not load your day', message: '$error'),
          data: (AppData data) => _OverviewBody(data: data, selected: selected),
        )),
      ])),
    );
  }
}

class _OverviewBody extends ConsumerWidget {
  const _OverviewBody({required this.data, required this.selected});
  final AppData data;
  final DateTime selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HabitEngine habits = ref.watch(habitEngineProvider);
    final List<Habit> dueHabits = data.activeHabits.where((Habit h) => habits.isDueOn(h, selected, data.recordsFor(h.id))).toList();
    final int doneHabits = dueHabits.where((Habit h) => habits.isCompleted(h, data.recordsFor(h.id)[dateKey(selected)])).length;
    final List<Task> dayTasks = filterAndSortTasks(data.tasks, filter: TaskListFilter.today, selectedDate: selected, includeCompleted: true);
    final int doneTasks = dayTasks.where((Task t) => t.isCompleted).length;
    final double taskProgress = dayTasks.isEmpty ? 0 : doneTasks / dayTasks.length;
    final double habitProgress = dueHabits.isEmpty ? 0 : doneHabits / dueHabits.length;

    return ListView(padding: const EdgeInsets.fromLTRB(AppDimens.pagePadding, 0, AppDimens.pagePadding, 24), children: <Widget>[
      Row(children: <Widget>[
        Expanded(child: _ProgressCard(title: 'Tasks', value: taskProgress, detail: '$doneTasks of ${dayTasks.length}', icon: Icons.task_alt_rounded, color: AppColors.gold, onTap: () => context.go(AppRoutes.tasks))),
        const SizedBox(width: 10),
        Expanded(child: _ProgressCard(title: 'Habits', value: habitProgress, detail: '$doneHabits of ${dueHabits.length}', icon: Icons.repeat_rounded, color: const Color(0xFF83D3CF), onTap: () => context.go(AppRoutes.habits))),
      ]),
      const SizedBox(height: 24),
      Row(children: <Widget>[
        const Expanded(child: Text("Today's Tasks", style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
        TextButton(onPressed: () => context.go(AppRoutes.tasks), child: const Text('View all')),
      ]),
      if (dayTasks.isEmpty)
        Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)), child: const Column(children: <Widget>[Icon(Icons.event_available_rounded, color: AppColors.textSecondary, size: 30), SizedBox(height: 8), Text('Nothing scheduled for this day', style: TextStyle(fontWeight: FontWeight.w600)), SizedBox(height: 4), Text('Create a task or check a different date.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12))]))
      else ...<Widget>[
        for (final Task task in dayTasks.take(8)) ...<Widget>[
          TaskCard(key: ValueKey<String>(task.id), task: task, selectedDate: selected, titleFontSize: 16, onOpen: () => context.push(AppRoutes.taskDetail(task.id)), onToggle: (bool done) async {
            try { await ref.read(appDataProvider.notifier).setTaskCompleted(task.id, done); }
            catch (error) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error'))); }
          }),
          const SizedBox(height: 9),
        ],
        if (dayTasks.length > 8) TextButton(onPressed: () => context.go(AppRoutes.tasks), child: Text('View ${dayTasks.length - 8} more task(s)')),
      ],
      const SizedBox(height: 18),
      Row(children: <Widget>[
        const Expanded(child: Text('Habits Due', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
        TextButton(onPressed: () => context.go(AppRoutes.habits), child: const Text('Manage habits')),
      ]),
      if (dueHabits.isEmpty)
        Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)), child: const Text('No habits are due on this day.', style: TextStyle(color: AppColors.textSecondary)))
      else
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)), child: Column(children: <Widget>[
          for (int i = 0; i < dueHabits.length && i < 5; i++) ...<Widget>[
            if (i > 0) const Divider(height: 16),
            InkWell(onTap: () => context.push(AppRoutes.habitDetail(dueHabits[i].id)), child: Row(children: <Widget>[
              Container(width: 34, height: 34, decoration: BoxDecoration(color: Color(dueHabits[i].colorValue).withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)), child: Icon(Icons.repeat_rounded, color: Color(dueHabits[i].colorValue), size: 18)),
              const SizedBox(width: 10),
              Expanded(child: Text(dueHabits[i].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
              Icon(habits.isCompleted(dueHabits[i], data.recordsFor(dueHabits[i].id)[dateKey(selected)]) ? Icons.check_circle_rounded : Icons.circle_outlined, color: habits.isCompleted(dueHabits[i], data.recordsFor(dueHabits[i].id)[dateKey(selected)]) ? AppColors.gold : AppColors.textHint),
            ])),
          ],
          if (dueHabits.length > 5) Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => context.go(AppRoutes.habits), child: Text('View ${dueHabits.length - 5} more'))),
        ])),
      const SizedBox(height: 24),
      Row(children: <Widget>[
        const Expanded(child: Text('Insights', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
        TextButton(onPressed: () => context.push(AppRoutes.taskAnalytics), child: const Text('Task analytics')),
      ]),
      Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)), child: Row(children: <Widget>[
        const Icon(Icons.insights_rounded, color: AppColors.gold, size: 28), const SizedBox(width: 12),
        const Expanded(child: Text('Review completion history, overdue work and daily progress.', style: TextStyle(color: AppColors.textSecondary, height: 1.3))),
        IconButton(onPressed: () => context.push(AppRoutes.analytics), icon: const Icon(Icons.arrow_forward_rounded)),
      ])),
    ]);
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.title, required this.value, required this.detail, required this.icon, required this.color, required this.onTap});
  final String title; final double value; final String detail; final IconData icon; final Color color; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(color: AppColors.surface, borderRadius: BorderRadius.circular(16), child: InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap, child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
    Row(children: <Widget>[Icon(icon, color: color, size: 19), const SizedBox(width: 7), Text(title, style: const TextStyle(fontWeight: FontWeight.w700))]),
    const SizedBox(height: 14),
    Row(children: <Widget>[Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: value, minHeight: 6, backgroundColor: AppColors.border, color: color))), const SizedBox(width: 7), Text('${(value * 100).round()}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))]),
    const SizedBox(height: 7), Text(detail, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
  ]))));
}
