import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/date_utils.dart';
import '../../domain/logic/habit_engine.dart';
import '../../domain/models/models.dart';
import '../../shared/widgets/widgets.dart';
import '../../state/app_data.dart';
import '../../state/app_state.dart';
import 'dashboard_providers.dart';
import 'habit_card.dart';

/// Dedicated habit management destination; the Dashboard remains an overview.
class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DateTime today = ref.watch(todayProvider);
    final DateTime selected = ref.watch(selectedDateProvider);
    final AsyncValue<AppData> async = ref.watch(appDataProvider);
    return Scaffold(
      body: SafeArea(bottom: false, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Padding(padding: const EdgeInsets.fromLTRB(AppDimens.pagePadding, 12, 10, 0), child: Row(children: <Widget>[
          const Expanded(child: Text('Habits', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800))),
          IconButton(tooltip: 'Habit analytics', onPressed: () => context.push(AppRoutes.analytics), icon: const Icon(Icons.insights_outlined)),
          IconButton(tooltip: 'Settings', onPressed: () => context.push(AppRoutes.settings), icon: const Icon(Icons.settings_outlined)),
        ])),
        const SizedBox(height: 8),
        DateStrip(today: today, selected: selected, onSelected: (DateTime day) => ref.read(selectedDateProvider.notifier).select(day)),
        const SizedBox(height: 10),
        Expanded(child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace _) => EmptyState(icon: Icons.error_outline_rounded, title: 'Could not load habits', message: '$error'),
          data: (AppData data) => _HabitsList(data: data, selected: selected),
        )),
      ])),
    );
  }
}

class _HabitsList extends ConsumerWidget {
  const _HabitsList({required this.data, required this.selected});
  final AppData data;
  final DateTime selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final HabitEngine engine = ref.watch(habitEngineProvider);
    final Map<String, HabitStats> stats = ref.watch(habitStatsProvider);
    final HabitListFilter filter = ref.watch(habitFilterProvider);
    final String? chosenCategory = ref.watch(selectedCategoryProvider);
    final String? categoryId = data.sortedCategories.any((HabitCategory c) => c.id == chosenCategory) ? chosenCategory : null;
    final List<Habit> inCategory = data.activeHabits.where((Habit h) => categoryId == null || h.categoryId == categoryId).toList();
    final List<Habit> due = inCategory.where((Habit h) => engine.isDueOn(h, selected, data.recordsFor(h.id))).toList();
    final List<Habit> shown = filter == HabitListFilter.due ? due : inCategory;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: AppDimens.pagePadding), child: Row(children: <Widget>[
        TickChip(label: 'All', icon: Icons.grid_view_rounded, selected: categoryId == null, onTap: () => ref.read(selectedCategoryProvider.notifier).select(null)),
        for (final HabitCategory category in data.sortedCategories) ...<Widget>[
          const SizedBox(width: 7),
          TickChip(label: category.name, icon: Icons.label_outline_rounded, selected: categoryId == category.id, onTap: () => ref.read(selectedCategoryProvider.notifier).select(category.id)),
        ],
      ])),
      const SizedBox(height: 12),
      Padding(padding: const EdgeInsets.symmetric(horizontal: AppDimens.pagePadding), child: Row(children: <Widget>[
        TickChip(label: 'All (${inCategory.length})', selected: filter == HabitListFilter.all, onTap: () => ref.read(habitFilterProvider.notifier).select(HabitListFilter.all)),
        const SizedBox(width: 7),
        TickChip(label: 'Due (${due.length})', selected: filter == HabitListFilter.due, filledWhenSelected: true, onTap: () => ref.read(habitFilterProvider.notifier).select(HabitListFilter.due)),
        const Spacer(),
        Text('${headerPrefix(selected, ref.watch(todayProvider))} · ${dayMonthLabel(selected)}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ])),
      const SizedBox(height: 12),
      Expanded(child: data.activeHabits.isEmpty
          ? const EmptyState(icon: Icons.repeat_rounded, title: 'No habits yet', message: 'Tap + to add your first habit.')
          : shown.isEmpty
              ? const EmptyState(icon: Icons.event_available_rounded, title: 'Nothing due on this day', message: 'Switch to All to see every habit.')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(AppDimens.pagePadding, 0, AppDimens.pagePadding, 24),
                  itemCount: shown.length,
                  separatorBuilder: (_, int index) => const SizedBox(height: AppDimens.gap),
                  itemBuilder: (BuildContext context, int index) {
                    final Habit habit = shown[index];
                    return HabitCard(key: ValueKey<String>(habit.id), habit: habit, date: selected, engine: engine, stats: stats[habit.id] ?? HabitStats.empty, records: data.recordsFor(habit.id));
                  },
                )),
    ]);
  }
}
