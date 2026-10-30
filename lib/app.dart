import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/utils/date_utils.dart';
import 'domain/logic/habit_engine.dart';
import 'data/services/task_reminder_service.dart';
import 'domain/models/models.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'state/app_settings.dart';
import 'state/app_data.dart';
import 'state/app_state.dart';

/// Root widget: dark theme + router.
class TickOffApp extends ConsumerStatefulWidget {
  const TickOffApp({super.key});

  @override
  ConsumerState<TickOffApp> createState() => _TickOffAppState();
}

class _TickOffAppState extends ConsumerState<TickOffApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshReminders());
    }
  }

  Future<void> _refreshReminders() async {
    final TaskReminderService service = TaskReminderService.instance;
    await service.refreshTimeZone();
    final AppData? data = ref.read(appDataProvider).valueOrNull;
    if (data == null) return;
    for (final Task task in data.tasks) {
      unawaited(service.scheduleTask(task));
    }
    final DateTime today = ref.read(todayProvider);
    final HabitEngine engine = HabitEngine(today: today);
    for (final Habit habit in data.habits.where((Habit h) => !h.isArchived)) {
      final bool skipToday = habit.type == HabitType.build &&
          engine.isCompleted(habit, data.recordsFor(habit.id)[dateKey(today)]);
      unawaited(service.scheduleHabit(habit, skipToday: skipToday));
    }
  }

  @override
  Widget build(BuildContext context) {
    final String themeName = ref.watch(appDataProvider).valueOrNull?.settings[AppSettingKeys.theme] ?? 'original';
    return MaterialApp.router(
      title: 'TickOff',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(graphite: themeName == 'graphite'),
      darkTheme: AppTheme.dark(graphite: themeName == 'graphite'),
      themeMode: ThemeMode.dark,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}

/// Shown instead of the app when the local database cannot be opened, so the
/// problem is visible rather than a blank screen.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.error_outline_rounded,
                  size: 48,
                  color: AppColors.danger,
                ),
                const SizedBox(height: 16),
                const Text(
                  'TickOff could not open its database',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
