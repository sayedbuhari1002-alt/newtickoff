import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../state/app_settings.dart';
import '../../state/app_state.dart';

class ThemeSettingsScreen extends ConsumerWidget {
  const ThemeSettingsScreen({super.key});

  static const List<_ThemeOption> _options = <_ThemeOption>[
    _ThemeOption(AppColors.obsidian, 'Obsidian Graphite + Violet', 'The original deep graphite theme with quiet violet highlights.', Color(0xFF17171C), Color(0xFF22212A), Color(0xFFA78BFA)),
    _ThemeOption(AppColors.ocean, 'Midnight Ocean + Cyan', 'A cool blue-black palette with clear cyan accents.', Color(0xFF101923), Color(0xFF182633), Color(0xFF64D8E5)),
    _ThemeOption(AppColors.porcelain, 'Porcelain Sand + Sage', 'A calm light palette with warm neutral surfaces and sage green accents.', Color(0xFFF2F0E8), Color(0xFFFFFFFF), Color(0xFF64856B)),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String selected = ref.watch(appDataProvider).valueOrNull?.settings[AppSettingKeys.theme] ?? AppColors.obsidian;
    return Scaffold(
      appBar: AppBar(title: const Text('Theme')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: <Widget>[
          const Text('Appearance', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Choose the colour palette used throughout Tazkiyane. Your habits, tasks, notes and saved data are not changed.', style: TextStyle(color: AppColors.textSecondary, height: 1.4)),
          const SizedBox(height: 16),
          for (final _ThemeOption option in _options) ...<Widget>[
            _ThemeChoice(option: option, selected: selected == option.id, onTap: () async {
              try {
                await ref.read(appDataProvider.notifier).saveSetting(AppSettingKeys.theme, option.id);
              } catch (error) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save theme: $error')));
              }
            }),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _ThemeOption {
  const _ThemeOption(this.id, this.title, this.subtitle, this.background, this.surface, this.accent);
  final String id, title, subtitle;
  final Color background, surface, accent;
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({required this.option, required this.selected, required this.onTap});
  final _ThemeOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: selected ? AppColors.primaryAccent : AppColors.border, width: selected ? 1.6 : 1)),
      padding: const EdgeInsets.all(14),
      child: Row(children: <Widget>[
        Container(width: 78, height: 70, padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: option.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: option.accent.withAlpha(110))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Container(width: 34, height: 5, decoration: BoxDecoration(color: option.accent, borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 7),
          Expanded(child: Container(decoration: BoxDecoration(color: option.surface, borderRadius: BorderRadius.circular(5)))),
          const SizedBox(height: 6),
          Row(children: <Widget>[for (int i = 0; i < 3; i++) Container(width: 12, height: 5, margin: const EdgeInsets.only(right: 4), decoration: BoxDecoration(color: option.accent.withAlpha(i == 0 ? 255 : 100), borderRadius: BorderRadius.circular(3))) ]),
        ])),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(option.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(option.subtitle, style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35)),
          if (selected) Padding(padding: const EdgeInsets.only(top: 7), child: Text('ACTIVE THEME', style: TextStyle(color: AppColors.primaryAccent, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1))),
        ])),
        const SizedBox(width: 8),
        Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: selected ? AppColors.primaryAccent : AppColors.textHint),
      ]),
    ),
  );
}
