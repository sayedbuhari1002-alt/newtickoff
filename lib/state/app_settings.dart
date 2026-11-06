import 'dart:convert';

/// Stable keys used by the local-only settings store.
class AppSettingKeys {
  AppSettingKeys._();

  static const String theme = 'ui.theme';
  static const String dashboardOrder = 'dashboard.section_order';
  static const String hiddenDashboardWidgets = 'dashboard.hidden_widgets';
}

/// Section IDs are persisted instead of labels so labels can change safely.
const List<String> dashboardSectionIds = <String>[
  'progress',
  'tasks',
  'habits',
  'insights',
];

const Map<String, String> dashboardSectionLabels = <String, String>{
  'progress': 'Daily Progress',
  'tasks': "Today's Tasks",
  'habits': 'Habits Due',
  'insights': 'Insights',
};

List<String> dashboardSectionOrder(Map<String, String> settings) {
  final String? raw = settings[AppSettingKeys.dashboardOrder];
  if (raw == null) return List<String>.of(dashboardSectionIds);
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! List) return List<String>.of(dashboardSectionIds);
    final List<String> order = decoded
        .whereType<String>()
        .where(dashboardSectionIds.contains)
        .toSet()
        .toList();
    for (final String id in dashboardSectionIds) {
      if (!order.contains(id)) order.add(id);
    }
    return order;
  } on FormatException {
    return List<String>.of(dashboardSectionIds);
  }
}

Set<String> hiddenDashboardWidgets(Map<String, String> settings) {
  final String? raw = settings[AppSettingKeys.hiddenDashboardWidgets];
  if (raw == null) return <String>{};
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! List) return <String>{};
    return decoded.whereType<String>().where(dashboardSectionIds.contains).toSet();
  } on FormatException {
    return <String>{};
  }
}
