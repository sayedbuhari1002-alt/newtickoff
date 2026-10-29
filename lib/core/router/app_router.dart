import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/models.dart';
import '../../features/analytics/analytics_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/dashboard/habits_screen.dart';
import '../../features/habit_detail/habit_detail_screen.dart';
import '../../features/habit_form/habit_form_screen.dart';
import '../../features/notes/note_editor_screen.dart';
import '../../features/notes/notes_screen.dart';
import '../../features/settings/archive_screen.dart';
import '../../features/settings/categories_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/share/share_progress_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/tasks/subtask_editor_screen.dart';
import '../../features/tasks/task_analytics_screen.dart';
import '../../features/tasks/task_detail_screen.dart';
import '../../features/tasks/task_form_screen.dart';
import '../../features/tasks/task_list_screen.dart';
import '../../shared/widgets/widgets.dart';
import 'routes.dart';

final Provider<GoRouter> appRouterProvider = Provider<GoRouter>((Ref ref) => buildRouter());

/// The four primary destinations share a navigation shell. Forms, detail pages
/// and analytics remain full-screen so task and habit workflows are not nested
/// inside a small modal.
GoRouter buildRouter({String initialLocation = AppRoutes.dashboard}) {
  return GoRouter(
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
            GoRoute(path: AppRoutes.tasks, builder: (BuildContext c, GoRouterState s) => const TaskListScreen()),
          ]),
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(path: AppRoutes.notes, builder: (BuildContext c, GoRouterState s) => const NotesScreen()),
          ]),
        ],
      ),
      GoRoute(path: AppRoutes.taskNew, builder: (BuildContext c, GoRouterState s) => const TaskFormScreen()),
      GoRoute(path: AppRoutes.subtaskEditor, builder: (BuildContext c, GoRouterState s) => SubtaskEditorScreen(
        initial: s.extra is List<Subtask> ? List<Subtask>.from(s.extra! as List<Subtask>) : const <Subtask>[],
      )),
      GoRoute(path: AppRoutes.taskAnalytics, builder: (BuildContext c, GoRouterState s) => const TaskAnalyticsScreen()),
      GoRoute(
        path: '/task/:id',
        builder: (BuildContext c, GoRouterState s) => TaskDetailScreen(taskId: s.pathParameters['id'] ?? ''),
        routes: <RouteBase>[
          GoRoute(path: 'edit', builder: (BuildContext c, GoRouterState s) => TaskFormScreen(taskId: s.pathParameters['id'])),
          GoRoute(path: 'analytics', builder: (BuildContext c, GoRouterState s) => TaskAnalyticsScreen(taskId: s.pathParameters['id'])),
        ],
      ),
      GoRoute(path: AppRoutes.habitNew, builder: (BuildContext c, GoRouterState s) => const HabitFormScreen()),
      GoRoute(
        path: '/habit/:id',
        builder: (BuildContext c, GoRouterState s) => HabitDetailScreen(habitId: s.pathParameters['id'] ?? ''),
        routes: <RouteBase>[
          GoRoute(path: 'edit', builder: (BuildContext c, GoRouterState s) => HabitFormScreen(habitId: s.pathParameters['id'])),
          GoRoute(path: 'analytics', builder: (BuildContext c, GoRouterState s) => AnalyticsScreen(habitId: s.pathParameters['id'])),
        ],
      ),
      GoRoute(path: AppRoutes.analytics, builder: (BuildContext c, GoRouterState s) => const AnalyticsScreen()),
      GoRoute(path: AppRoutes.noteNewPath, builder: (BuildContext c, GoRouterState s) => NoteEditorScreen(habitId: s.uri.queryParameters['habit'])),
      GoRoute(path: '/note/:id', builder: (BuildContext c, GoRouterState s) => NoteEditorScreen(noteId: s.pathParameters['id'])),
      GoRoute(path: AppRoutes.settings, builder: (BuildContext c, GoRouterState s) => const SettingsScreen()),
      GoRoute(path: AppRoutes.shareProgress, builder: (BuildContext c, GoRouterState s) => ShareProgressScreen(habitId: s.uri.queryParameters['habit'])),
      GoRoute(path: AppRoutes.categories, builder: (BuildContext c, GoRouterState s) => const CategoriesScreen()),
      GoRoute(path: AppRoutes.archive, builder: (BuildContext c, GoRouterState s) => const ArchiveScreen()),
      _stub(AppRoutes.theme, 'Theme', 4, 'Theme preferences are available from Settings.'),
      _stub(AppRoutes.layout, 'Layout', 4, 'Display and timeline options are available from Settings.'),
      _stub(AppRoutes.widgets, 'Widgets', 4, 'Native Android launcher widgets are not included.'),
      _stub(AppRoutes.general, 'General', 4, 'General preferences are available from Settings.'),
      _stub(AppRoutes.rearrange, 'Rearrange', 4, 'Habit ordering follows the stored habit order.'),
    ],
  );
}

GoRoute _stub(String path, String title, int stage, String description) => GoRoute(
  path: path,
  builder: (BuildContext c, GoRouterState s) => StagePlaceholderScreen(title: title, stage: stage, description: description),
);
