import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../state/app_settings.dart';
import '../../state/app_state.dart';

/// Theme presets keep the supplied TickOff palette as the default.
class ThemeSettingsScreen extends ConsumerWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Map<String, String> settings =
        ref.watch(appDataProvider).valueOrNull?.settings ?? const <String, String>{};
    final String selected = settings[AppSettingKeys.theme] ?? 'original';

    return Scaffold(
      appBar: AppBar(title: const Text('Theme')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: <Widget>[
          const Text(
            'Appearance',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Choose a dark appearance. Your habit and task colours stay unchanged.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          _ThemeChoice(
            selected: selected == 'original',
            title: 'TickOff Dark',
            subtitle: 'Original black background with the existing gold and cyan accents.',
            previewBackground: const Color(0xFF000000),
            previewSurface: const Color(0xFF111111),
            onTap: () => _save(context, ref, 'original'),
          ),
          const SizedBox(height: 12),
          _ThemeChoice(
            selected: selected == 'graphite',
            title: 'Graphite',
            subtitle: 'A slightly lighter charcoal app bar and Material surface style.',
            previewBackground: const Color(0xFF101114),
            previewSurface: const Color(0xFF202126),
            onTap: () => _save(context, ref, 'graphite'),
          ),
          const SizedBox(height: 16),
          if (selected != 'original')
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _save(context, ref, 'original'),
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Restore original appearance'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _save(BuildContext context, WidgetRef ref, String value) async {
    try {
      await ref.read(appDataProvider.notifier).saveSetting(AppSettingKeys.theme, value);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save theme: $error')));
      }
    }
  }
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.previewBackground,
    required this.previewSurface,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final Color previewBackground;
  final Color previewSurface;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              Container(
                width: 76,
                height: 76,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: previewBackground,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: <Widget>[
                    Container(height: 9, decoration: BoxDecoration(color: previewSurface, borderRadius: BorderRadius.circular(3))),
                    const SizedBox(height: 7),
                    Row(children: <Widget>[
                      Expanded(child: Container(height: 19, decoration: BoxDecoration(color: previewSurface, borderRadius: BorderRadius.circular(4)))),
                      const SizedBox(width: 5),
                      Expanded(child: Container(height: 19, decoration: BoxDecoration(color: previewSurface, borderRadius: BorderRadius.circular(4)))),
                    ]),
                    const SizedBox(height: 7),
                    Align(alignment: Alignment.centerLeft, child: Container(width: 25, height: 4, decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(2)))),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded, color: selected ? AppColors.gold : AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}
