import 'package:flutter_test/flutter_test.dart';
import 'package:tickoff_replacement/state/app_settings.dart';

void main() {
  group('Dashboard preferences', () {
    test('uses the original section order when no preference was saved', () {
      expect(dashboardSectionOrder(const <String, String>{}), dashboardSectionIds);
      expect(hiddenDashboardWidgets(const <String, String>{}), isEmpty);
    });

    test('keeps a saved order, removes duplicates and ignores unknown sections', () {
      final List<String> order = dashboardSectionOrder(<String, String>{
        AppSettingKeys.dashboardOrder: '["tasks","tasks","unknown","insights"]',
      });
      expect(order, <String>['tasks', 'insights', 'progress', 'habits']);
    });

    test('parses hidden Dashboard sections and ignores unknown section IDs', () {
      expect(
        hiddenDashboardWidgets(<String, String>{
          AppSettingKeys.hiddenDashboardWidgets: '["tasks","unknown","habits"]',
        }),
        <String>{'tasks', 'habits'},
      );
    });

    test('falls back safely when saved preference JSON is invalid', () {
      expect(
        dashboardSectionOrder(<String, String>{AppSettingKeys.dashboardOrder: 'not json'}),
        dashboardSectionIds,
      );
      expect(
        hiddenDashboardWidgets(<String, String>{AppSettingKeys.hiddenDashboardWidgets: 'not json'}),
        isEmpty,
      );
    });
  });
}
