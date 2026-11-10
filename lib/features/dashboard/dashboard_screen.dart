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
import '../../data/services/task_reminder_service.dart';
import '../../shared/widgets/widgets.dart';
import '../../shared/utils/format.dart';
import '../../state/app_data.dart';
import '../../state/app_settings.dart';
import '../../state/app_state.dart';
import '../tasks/task_card.dart';
import 'day_actions.dart';
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateMenu(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Create'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(AppDimens.pagePadding, 10, 10, 0),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${headerPrefix(selected, today)}, ${dayMonthLabel(selected)}',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text('Your day, at a glance', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Analytics',
                    icon: const Icon(Icons.analytics_outlined),
                    onPressed: () => context.push(AppRoutes.analytics),
                  ),
                  IconButton(
                    tooltip: 'Settings',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => context.push(AppRoutes.settings),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            DateStrip(
              today: today,
              selected: selected,
              onSelected: (DateTime day) => ref.read(selectedDateProvider.notifier).select(day),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object error, StackTrace _) => EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Could not load your day',
                  message: '$error',
                ),
                data: (AppData data) => _OverviewBody(data: data, selected: selected),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateMenu(BuildContext context) async {
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Create new', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline_rounded),
              title: const Text('Add Habit'),
              onTap: () => Navigator.pop(sheetContext, 'habit'),
            ),
            ListTile(
              leading: const Icon(Icons.task_alt_rounded),
              title: const Text('Add Task'),
              onTap: () => Navigator.pop(sheetContext, 'task'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'habit') context.push(AppRoutes.habitNew);
    if (choice == 'task') context.push(AppRoutes.taskNew);
  }
}

class _OverviewBody extends ConsumerWidget {
  const _OverviewBody({required this.data, required this.selected});

  final AppData data;
  final DateTime selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DateTime today = ref.watch(todayProvider);
    final HabitEngine habits = ref.watch(habitEngineProvider);
    final List<Habit> dueHabits = data.activeHabits
        .where((Habit h) => habits.isDueOn(h, selected, data.recordsFor(h.id)))
        .toList()
      ..sort((Habit a, Habit b) {
        // Keep habits needing attention at the top of the Home section.
        // Successful Build habits and clean Quit habits move below pending/slipped items.
        final bool aSuccessful = habits.isSuccess(a, data.recordsFor(a.id)[dateKey(selected)]);
        final bool bSuccessful = habits.isSuccess(b, data.recordsFor(b.id)[dateKey(selected)]);
        if (aSuccessful != bSuccessful) return aSuccessful ? 1 : -1;
        final int order = a.sortOrder.compareTo(b.sortOrder);
        return order != 0 ? order : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    final int doneHabits = dueHabits
        .where((Habit h) => habits.isSuccess(h, data.recordsFor(h.id)[dateKey(selected)]))
        .length;
    final List<Task> dashboardTasks = data.tasks.where((Task task) => task.parentTaskId != null || !data.isGroupTask(task)).toList();
    final List<Task> dayTasks = filterAndSortTasks(
      dashboardTasks,
      filter: TaskListFilter.today,
      selectedDate: selected,
      includeCompleted: true,
      todayOverride: today,
    );
    final int doneTasks = dayTasks.where((Task t) => t.isCompleted).length;
    final double taskProgress = dayTasks.isEmpty ? 0 : doneTasks / dayTasks.length;
    final double habitProgress = dueHabits.isEmpty ? 0 : doneHabits / dueHabits.length;
    final bool hasConfiguredReminder =
        data.tasks.any((Task t) => t.reminderAt != null && t.reminderAt!.isAfter(DateTime.now()) && !t.isCompleted && !t.isPaused) ||
        data.activeHabits.any((Habit h) => h.reminder.enabled);
    final ReminderPermissionStatus? reminderPermissions =
        ref.watch(reminderPermissionProvider).valueOrNull;
    final Set<String> hidden = hiddenDashboardWidgets(data.settings);
    final List<String> order = dashboardSectionOrder(data.settings);

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppDimens.pagePadding, 0, AppDimens.pagePadding, 104),
      children: <Widget>[
        if (hasConfiguredReminder &&
            reminderPermissions != null &&
            (!reminderPermissions.ready || reminderPermissions.schedulingIssue != null)) ...<Widget>[
          _ReminderWarningBanner(status: reminderPermissions),
          const SizedBox(height: AppDimens.gap),
        ],
        for (final String id in order)
          if (!hidden.contains(id))
            Padding(
              padding: EdgeInsets.only(bottom: id == 'progress' || id == 'habits' ? 24 : 18),
              child: switch (id) {
                'progress' => _progressSection(
                    context,
                    taskProgress: taskProgress,
                    habitProgress: habitProgress,
                    doneTasks: doneTasks,
                    totalTasks: dayTasks.length,
                    doneHabits: doneHabits,
                    totalHabits: dueHabits.length,
                  ),
                'tasks' => _tasksSection(context, ref, dayTasks, today),
                'habits' => _habitsSection(context, ref, data, habits, dueHabits, selected),
                'insights' => _insightsSection(context),
                _ => const SizedBox.shrink(),
              },
            ),
        if (order.every(hidden.contains))
          Padding(
            padding: EdgeInsets.symmetric(vertical: 28, horizontal: 8),
            child: Column(
              children: <Widget>[
                Icon(Icons.widgets_outlined, size: 34, color: AppColors.textSecondary),
                SizedBox(height: 10),
                Text('No Dashboard sections are enabled', style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(height: 5),
                Text('Open Settings → Widgets to show a section again.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _progressSection(
    BuildContext context, {
    required double taskProgress,
    required double habitProgress,
    required int doneTasks,
    required int totalTasks,
    required int doneHabits,
    required int totalHabits,
  }) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _ProgressCard(
            title: 'Tasks',
            value: taskProgress,
            detail: '$doneTasks of $totalTasks',
            icon: Icons.task_alt_rounded,
            color: AppColors.gold,
            onTap: () => context.go(AppRoutes.tasks),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ProgressCard(
            title: 'Habits',
            value: habitProgress,
            detail: '$doneHabits of $totalHabits',
            icon: Icons.repeat_rounded,
            color: AppColors.cyan,
            onTap: () => context.go(AppRoutes.habits),
          ),
        ),
      ],
    );
  }

  Widget _tasksSection(
    BuildContext context,
    WidgetRef ref,
    List<Task> dayTasks,
    DateTime today,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(child: Text("Today's Tasks", style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
            TextButton(onPressed: () => context.go(AppRoutes.tasks), child: const Text('View all')),
          ],
        ),
        if (dayTasks.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: <Widget>[
                Icon(Icons.event_available_rounded, color: AppColors.textSecondary, size: 30),
                SizedBox(height: 8),
                Text('Nothing scheduled for this day', style: TextStyle(fontWeight: FontWeight.w600)),
                SizedBox(height: 4),
                Text('Create a task or check a different date.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          )
        else ...<Widget>[
          for (final Task task in dayTasks.take(8)) ...<Widget>[
            TaskCard(
              key: ValueKey<String>(task.id),
              task: task,
              selectedDate: selected,
              showOverdue: isSameDay(selected, today),
              titleFontSize: 16,
              onOpen: () => context.push(AppRoutes.taskDetail(task.id)),
              onToggle: (bool done) async {
                try {
                  await ref.read(appDataProvider.notifier).setTaskCompleted(task.id, done);
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
                  }
                }
              },
              onProgressChanged: (double value) async {
                try {
                  await ref.read(appDataProvider.notifier).updateTaskProgress(task.id, value);
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
                  }
                  rethrow;
                }
              },
            ),
            const SizedBox(height: 9),
          ],
          if (dayTasks.length > 8)
            TextButton(
              onPressed: () => context.go(AppRoutes.tasks),
              child: Text('View ${dayTasks.length - 8} more task(s)'),
            ),
        ],
      ],
    );
  }

  Widget _habitsSection(
    BuildContext context,
    WidgetRef ref,
    AppData data,
    HabitEngine habits,
    List<Habit> dueHabits,
    DateTime selectedDate,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(child: Text('Habits Due', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
            TextButton(onPressed: () => context.go(AppRoutes.habits), child: const Text('Manage habits')),
          ],
        ),
        if (dueHabits.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
            child: Text('No habits are due on this day.', style: TextStyle(color: AppColors.textSecondary)),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: <Widget>[
                for (int i = 0; i < dueHabits.length && i < 5; i++) ...<Widget>[
                  if (i > 0) const Divider(height: 1),
                  _DashboardHabitRow(
                    habit: dueHabits[i],
                    engine: habits,
                    record: data.recordsFor(dueHabits[i].id)[dateKey(selected)],
                    onOpen: () => context.push(AppRoutes.habitDetail(dueHabits[i].id, date: selectedDate)),
                    onTrack: () => tapDay(context, ref, dueHabits[i], selected),
                  ),
                ],
                if (dueHabits.length > 5)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(onPressed: () => context.go(AppRoutes.habits), child: Text('View ${dueHabits.length - 5} more')),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _insightsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(child: Text('Insights', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
            TextButton(onPressed: () => context.push(AppRoutes.analytics), child: const Text('View analytics')),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: <Widget>[
              Icon(Icons.insights_rounded, color: AppColors.gold, size: 28),
              const SizedBox(width: 12),
              Expanded(child: Text('Review completion history, overdue work and daily progress.', style: TextStyle(color: AppColors.textSecondary, height: 1.3))),
              IconButton(onPressed: () => context.push(AppRoutes.analytics), icon: const Icon(Icons.arrow_forward_rounded)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReminderWarningBanner extends StatelessWidget {
  const _ReminderWarningBanner({required this.status});

  final ReminderPermissionStatus status;

  @override
  Widget build(BuildContext context) {
    final String message = status.schedulingIssue ??
        (!status.notificationsGranted
            ? 'Allow notifications so task and habit reminders can appear.'
            : !status.exactAlarmsGranted
                ? 'Allow exact alarms so reminders can arrive close to their selected time.'
                : 'Tazkiyane could not confirm your device time zone. Check your date and time settings.');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.32)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.notifications_off_outlined, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
            ),
          ),
          TextButton(
            onPressed: () => context.push(AppRoutes.notifications),
            child: const Text('Fix'),
          ),
        ],
      ),
    );
  }
}

class _DashboardHabitRow extends StatelessWidget {
  const _DashboardHabitRow({
    required this.habit,
    required this.engine,
    required this.record,
    required this.onOpen,
    required this.onTrack,
  });

  final Habit habit;
  final HabitEngine engine;
  final CompletionRecord? record;
  final VoidCallback onOpen;
  final VoidCallback onTrack;

  @override
  Widget build(BuildContext context) {
    final bool slipped = habit.type == HabitType.quit && engine.isSlipped(habit, record);
    final bool successful = engine.isSuccess(habit, record);
    final String countDetail = habit.tracking == TrackingMethod.count
        ? ' · ${countLabel(habit, record?.count ?? 0)}'
        : '';
    final bool countBased = habit.tracking == TrackingMethod.count;

    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Color(habit.colorValue).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.repeat_rounded, color: Color(habit.colorValue), size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(habit.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (countDetail.isNotEmpty)
                    Text(countDetail.trimLeft().replaceFirst('· ', ''), style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
            if (countBased)
              Icon(Icons.chevron_right_rounded, color: AppColors.textHint)
            else
              IconButton(
                tooltip: habit.type == HabitType.quit
                    ? (slipped ? 'Undo slip' : 'Record a slip')
                    : (successful ? 'Mark not done' : 'Mark completed'),
                onPressed: onTrack,
                icon: Icon(
                  slipped ? Icons.close_rounded : successful ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: slipped ? AppColors.danger : successful ? Color(habit.colorValue) : AppColors.textHint,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.title, required this.value, required this.detail, required this.icon, required this.color, required this.onTap});
  final String title;
  final double value;
  final String detail;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(children: <Widget>[Icon(icon, color: color, size: 19), const SizedBox(width: 7), Text(title, style: const TextStyle(fontWeight: FontWeight.w700))]),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: value, minHeight: 6, backgroundColor: AppColors.border, color: color))),
                    const SizedBox(width: 7),
                    Text('${(value * 100).round()}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 7),
                Text(detail, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      );
}
