import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/date_utils.dart';
import '../../domain/models/models.dart';
import '../../features/analytics/analytics_screen.dart';
import '../../features/analytics/unified_analytics_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/dashboard/habits_screen.dart';
import '../../features/habit_detail/habit_detail_screen.dart';
import '../../features/habit_form/habit_form_screen.dart';
import '../../features/notes/note_editor_screen.dart';
import '../../features/notes/notes_screen.dart';
import '../../features/productivity/productivity_screen.dart';
import '../../features/notes/note_library_screen.dart';
import '../../features/expenses/expense_editor_screen.dart';
import '../../features/settings/archive_screen.dart';
import '../../features/settings/categories_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/settings/theme_settings_screen.dart';
import '../../features/settings/widgets_settings_screen.dart';
import '../../features/settings/rearrange_screen.dart';
import '../../features/settings/notification_settings_screen.dart';
import '../../features/share/share_progress_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/tasks/subtask_editor_screen.dart';
import '../../features/tasks/task_analytics_screen.dart';
import '../../features/tasks/task_detail_screen.dart';
import '../../features/tasks/task_form_screen.dart';
import '../../features/tasks/task_list_screen.dart';
import '../../features/tasks/task_templates_screen.dart';
import '../../shared/widgets/widgets.dart';
import 'routes.dart';

final Provider<GoRouter> appRouterProvider = Provider<GoRouter>((Ref ref) => buildRouter());

/// The five primary destinations share a navigation shell. Forms, detail pages
/// and analytics remain full-screen so task and habit workflows are not nested
/// inside a small modal.
GoRouter buildRouter({String initialLocation = AppRoutes.dashboard}) {
  // Keep full-screen habit pages on the root Navigator even when they are
  // pushed from a StatefulShellRoute branch. This makes their back-stack
  // ownership explicit and prevents branch navigation from retaining them.
  final GlobalKey<NavigatorState> rootNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'rootNavigator');
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (BuildContext context, GoRouterState state, StatefulNavigationShell shell) => AppShell(navigationShell: shell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(path: AppRoutes.dashboard, builder: (BuildContext c, GoRouterState s) => const DashboardScreen()),
          ]),
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(path: AppRoutes.habits, builder: (BuildContext c, GoRouterState s) => const HabitsScreen()),
          ]),
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(path: AppRoutes.productivity, builder: (BuildContext c, GoRouterState s) => const ProductivityScreen()),
          ]),
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(path: AppRoutes.tasks, builder: (BuildContext c, GoRouterState s) => const TaskListScreen()),
          ]),
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(path: AppRoutes.notes, builder: (BuildContext c, GoRouterState s) => const NotesScreen()),
          ]),
        ],
      ),
      GoRoute(path: AppRoutes.taskNew, builder: (BuildContext c, GoRouterState s) => TaskFormScreen(initialTemplate: s.extra is TaskTemplate ? s.extra as TaskTemplate : null)),
      GoRoute(path: AppRoutes.taskTemplates, builder: (BuildContext c, GoRouterState s) => const TaskTemplatesScreen()),
      GoRoute(path: AppRoutes.subtaskEditor, builder: (BuildContext c, GoRouterState s) => SubtaskEditorScreen(
        initial: s.extra is List<Subtask> ? List<Subtask>.from(s.extra! as List<Subtask>) : const <Subtask>[],
      )),
      GoRoute(path: AppRoutes.taskAnalytics, builder: (BuildContext c, GoRouterState s) => const UnifiedAnalyticsScreen()),
      GoRoute(
        path: '/task/:id',
        builder: (BuildContext c, GoRouterState s) => TaskDetailScreen(taskId: s.pathParameters['id'] ?? ''),
        routes: <RouteBase>[
          GoRoute(path: 'edit', builder: (BuildContext c, GoRouterState s) => TaskFormScreen(taskId: s.pathParameters['id'])),
          GoRoute(path: 'analytics', builder: (BuildContext c, GoRouterState s) => TaskAnalyticsScreen(taskId: s.pathParameters['id'])),
        ],
      ),
      GoRoute(
        path: AppRoutes.habitNew,
        parentNavigatorKey: rootNavigatorKey,
        builder: (BuildContext c, GoRouterState s) => const HabitFormScreen(),
      ),
      GoRoute(
        path: '/habit/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (BuildContext c, GoRouterState s) => HabitDetailScreen(
          habitId: s.pathParameters['id'] ?? '',
          selectedDate: parseDateKey(s.uri.queryParameters['date'] ?? ''),
          returnToDashboard: s.uri.queryParameters['returnTo'] == 'dashboard',
        ),
        routes: <RouteBase>[
          GoRoute(path: 'edit', builder: (BuildContext c, GoRouterState s) => HabitFormScreen(habitId: s.pathParameters['id'])),
          GoRoute(path: 'analytics', builder: (BuildContext c, GoRouterState s) => AnalyticsScreen(habitId: s.pathParameters['id'])),
        ],
      ),
      GoRoute(path: AppRoutes.analytics, builder: (BuildContext c, GoRouterState s) => const UnifiedAnalyticsScreen()),
      GoRoute(path: AppRoutes.noteLibrary, builder: (BuildContext c, GoRouterState s) => const NoteLibraryScreen()),
      GoRoute(path: AppRoutes.noteNewPath, builder: (BuildContext c, GoRouterState s) => NoteEditorScreen(habitId: s.uri.queryParameters['habit'], logDate: parseDateKey(s.uri.queryParameters['date'] ?? ''), noteType: NoteType.values.where((NoteType type) => type.name == s.uri.queryParameters['type']).firstOrNull ?? NoteType.daily, periodDate: parseDateKey(s.uri.queryParameters['period'] ?? ''))),
      GoRoute(path: '/note/:id', builder: (BuildContext c, GoRouterState s) => NoteEditorScreen(noteId: s.pathParameters['id'])),
      GoRoute(path: AppRoutes.expenseNewPath, builder: (BuildContext c, GoRouterState s) => ExpenseEditorScreen(initialDate: parseDateKey(s.uri.queryParameters['date'] ?? ''), initialType: TransactionType.values.where((TransactionType type) => type.name == s.uri.queryParameters['type']).firstOrNull ?? TransactionType.expense)),
      GoRoute(path: '/expense/:id/edit', builder: (BuildContext c, GoRouterState s) => ExpenseEditorScreen(expenseId: s.pathParameters['id'])),
      GoRoute(path: AppRoutes.settings, builder: (BuildContext c, GoRouterState s) => const SettingsScreen()),
      GoRoute(path: AppRoutes.shareProgress, builder: (BuildContext c, GoRouterState s) => ShareProgressScreen(habitId: s.uri.queryParameters['habit'])),
      GoRoute(path: AppRoutes.categories, builder: (BuildContext c, GoRouterState s) => const CategoriesScreen()),
      GoRoute(path: AppRoutes.archive, builder: (BuildContext c, GoRouterState s) => const ArchiveScreen()),
      GoRoute(path: AppRoutes.notifications, builder: (BuildContext c, GoRouterState s) => const NotificationSettingsScreen()),
      GoRoute(path: AppRoutes.theme, builder: (BuildContext c, GoRouterState s) => const ThemeSettingsScreen()),
      _stub(AppRoutes.layout, 'Layout', 4, 'Display and timeline options are available from Settings.'),
      GoRoute(path: AppRoutes.widgets, builder: (BuildContext c, GoRouterState s) => const WidgetsSettingsScreen()),
      _stub(AppRoutes.general, 'General', 4, 'General preferences are available from Settings.'),
      GoRoute(path: AppRoutes.rearrange, builder: (BuildContext c, GoRouterState s) => const RearrangeScreen()),
    ],
  );
}

GoRoute _stub(String path, String title, int stage, String description) => GoRoute(
  path: path,
  builder: (BuildContext c, GoRouterState s) => StagePlaceholderScreen(title: title, stage: stage, description: description),
);

extension _RouterFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
