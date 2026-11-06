import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../state/app_settings.dart';
import '../../state/app_state.dart';

/// Controls which overview cards appear on the in-app Dashboard.
class WidgetsSettingsScreen extends ConsumerWidget {
  const WidgetsSettingsScreen({super.key});

  static const Map<String, IconData> _icons = <String, IconData>{
    'progress': Icons.donut_large_rounded,
    'tasks': Icons.task_alt_rounded,
    'habits': Icons.repeat_rounded,
    'insights': Icons.insights_rounded,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Map<String, String> settings =
        ref.watch(appDataProvider).valueOrNull?.settings ?? const <String, String>{};
    final Set<String> hidden = hiddenDashboardWidgets(settings);

    return Scaffold(
      appBar: AppBar(title: const Text('Widgets')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: <Widget>[
          const Text('Dashboard widgets', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text(
            'Show or hide sections on the Dashboard. Your changes are saved on this device.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: <Widget>[
                for (int i = 0; i < dashboardSectionIds.length; i++) ...<Widget>[
                  if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                  SwitchListTile.adaptive(
                    value: !hidden.contains(dashboardSectionIds[i]),
                    secondary: Icon(_icons[dashboardSectionIds[i]], color: AppColors.textSecondary),
                    title: Text(dashboardSectionLabels[dashboardSectionIds[i]]!),
                    subtitle: Text('Display on the Dashboard', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    activeColor: AppColors.gold,
                    onChanged: (bool visible) async {
                      final Set<String> updated = Set<String>.of(hidden);
                      if (visible) {
                        updated.remove(dashboardSectionIds[i]);
                      } else {
                        updated.add(dashboardSectionIds[i]);
                      }
                      try {
                        await ref.read(appDataProvider.notifier).saveSetting(
                          AppSettingKeys.hiddenDashboardWidgets,
                          jsonEncode(updated.toList()),
                        );
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save widget settings: $error')));
                        }
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'These are in-app Dashboard sections, not Android home-screen launcher widgets.',
            style: TextStyle(color: AppColors.textHint, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}
