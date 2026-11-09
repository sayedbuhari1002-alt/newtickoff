import '../utils/date_utils.dart';
import '../../domain/models/note.dart';

/// Every route path in one place.
class AppRoutes {
  AppRoutes._();

  // Bottom-navigation tabs (inside the shell)
  static const String dashboard = '/dashboard';
  static const String habits = '/habits';
  static const String tasks = '/tasks';
  static const String notes = '/notes';
  static const String activity = '/activity';

  // Habits (full-screen, no bottom bar)
  static const String habitNew = '/habit/new';
  static String habitDetail(
    String id, {
    DateTime? date,
    bool returnToDashboard = false,
  }) {
    final Map<String, String> query = <String, String>{};
    if (date != null) query['date'] = dateKey(date);
    if (returnToDashboard) query['returnTo'] = 'dashboard';
    return Uri(
      path: '/habit/$id',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }
  static String habitEdit(String id) => '/habit/$id/edit';
  static String habitAnalytics(String id) => '/habit/$id/analytics';

  // Analytics across habits and tasks
  static const String productivity = '/productivity';
  static const String analytics = '/analytics';
  static const String taskAnalytics = '/task-analytics';

  // Tasks (full-screen)
  static const String taskNew = '/task/new';
  static const String taskTemplates = '/task-templates';
  static String taskDetail(String id) => '/task/$id';
  static String taskEdit(String id) => '/task/$id/edit';
  static String taskProgress(String id) => '/task/$id/analytics';
  static const String subtaskEditor = '/subtask-editor';

  // Notes
  static const String noteLibrary = '/notes/library';
  static const String noteNewPath = '/note/new';
  static String noteNew({
    String? habitId,
    DateTime? date,
    NoteType noteType = NoteType.daily,
    DateTime? periodDate,
  }) {
    final Map<String, String> query = <String, String>{};
    if (habitId != null) query['habit'] = habitId;
    if (date != null) query['date'] = dateKey(date);
    if (noteType != NoteType.daily) query['type'] = noteType.name;
    if (periodDate != null) query['period'] = dateKey(periodDate);
    return query.isEmpty
        ? noteNewPath
        : Uri(path: noteNewPath, queryParameters: query).toString();
  }
  static String noteEdit(String id) => '/note/$id';

  // Expense routes stay separate from journal-note routes.
  static const String expenseNewPath = '/expense/new';
  static String expenseNew({DateTime? date}) => date == null
      ? expenseNewPath
      : Uri(
          path: expenseNewPath,
          queryParameters: <String, String>{'date': dateKey(date)},
        ).toString();
  static String expenseEdit(String id) => '/expense/$id/edit';

  // Settings
  static const String settings = '/settings';
  static const String shareProgress = '/settings/share-progress';
  static String shareProgressFor(String habitId) =>
      '$shareProgress?habit=$habitId';
  static const String theme = '/settings/theme';
  static const String layout = '/settings/layout';
  static const String widgets = '/settings/widgets';
  static const String general = '/settings/general';
  static const String notifications = '/settings/notifications';
  static const String rearrange = '/settings/rearrange';
  static const String categories = '/settings/categories';
  static const String archive = '/settings/archive';
}
