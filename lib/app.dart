import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/router/routes.dart';
import 'data/services/task_reminder_service.dart';
import 'data/services/home_screen_widget_service.dart';
import 'domain/models/models.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'state/app_data.dart';
import 'state/app_settings.dart';
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
    TaskReminderService.instance.setTaskActionHandler(
      (String taskId, String actionId) async {
        try {
          await ref.read(appDataProvider.future);
          if (!mounted) return;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            try {
              final AppData? data = ref.read(appDataProvider).valueOrNull;
              final Task? task = data?.taskById(taskId);
              if (task == null) return;
              final router = ref.read(appRouterProvider);

              if (actionId == TaskReminderService.actionPostponeTask) {
                router.push(AppRoutes.taskEdit(taskId));
                return;
              }
              if (actionId == TaskReminderService.actionMarkTaskCompleted) {
                final AppDataNotifier notifier = ref.read(appDataProvider.notifier);
                // Complete outstanding subtasks through the normal task state
                // path. The final subtask completion automatically completes
                // the parent, records history, and creates a repeating task
                // instance when the task uses a repeat rule.
                for (final Subtask item in task.subtasks.where((Subtask item) => !item.isCompleted)) {
                  await notifier.toggleSubtask(taskId, item.id);
                }
                final AppData? latestData = ref.read(appDataProvider).valueOrNull;
                for (final Task child in (latestData?.childrenForTask(taskId) ?? <Task>[]).where((Task item) => !item.isCompleted)) {
                  await notifier.setTaskCompleted(child.id, true);
                }
                final Task? latest = ref.read(appDataProvider).valueOrNull?.taskById(taskId);
                if (latest != null && !latest.isCompleted && !latest.isPaused) {
                  await notifier.setTaskCompleted(taskId, true);
                }
                return;
              }
              router.push(AppRoutes.taskDetail(taskId));
            } catch (error) {
              debugPrint('Could not process task notification action: $error');
            }
          });
        } catch (error) {
          debugPrint('Could not process task notification action: $error');
        }
      },
    );
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
    await TaskReminderService.instance.refreshTimeZone();
    // Reconcile the saved data and notification schedules after returning
    // from Android Settings or a task notification action.
    await ref.read(appDataProvider.notifier).reload();
  }

  @override
  Widget build(BuildContext context) {
    final AppData? data = ref.watch(appDataProvider).valueOrNull;
    final String themeId = data?.settings[AppSettingKeys.theme] ?? AppColors.obsidian;
    final ThemeData selectedTheme = AppTheme.forId(themeId);
    ref.listen<AsyncValue<AppData>>(appDataProvider, (previous, next) {
      final AppData? latest = next.valueOrNull;
      if (latest != null) unawaited(HomeScreenWidgetService.update(latest));
    });
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: AppColors.isLight ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: AppColors.isLight ? Brightness.dark : Brightness.light,
    ));
    if (data != null) unawaited(HomeScreenWidgetService.update(data));
    return MaterialApp.router(
      title: 'Tazkiyane',
      debugShowCheckedModeBanner: false,
      // The user's selected palette is authoritative regardless of the
      // Android system-wide light/dark preference. Building a second theme
      // here would also change the global AppColors palette used by widgets.
      theme: selectedTheme,
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
                Icon(
                  Icons.error_outline_rounded,
                  size: 48,
                  color: AppColors.danger,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Tazkiyane could not open its database',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
