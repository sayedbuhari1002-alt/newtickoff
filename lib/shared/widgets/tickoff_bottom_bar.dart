import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';

/// Five primary destinations: Home, Habits, Activity, Tasks and Notes.
class TickoffBottomBar extends StatelessWidget {
  const TickoffBottomBar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  /// 0 = Dashboard, 1 = Habits, 2 = Activity, 3 = Tasks, 4 = Notes.
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: AppDimens.bottomBarHeight + 8,
          child: Row(
            children: <Widget>[
              Expanded(child: _NavItem(icon: Icons.dashboard_rounded, label: 'Home', selected: currentIndex == 0, onTap: () => onSelect(0))),
              Expanded(child: _NavItem(icon: Icons.check_circle_outline_rounded, label: 'Habits', selected: currentIndex == 1, onTap: () => onSelect(1))),
              Expanded(child: _NavItem(icon: Icons.history_rounded, label: 'Activity', selected: currentIndex == 2, onTap: () => onSelect(2))),
              Expanded(child: _NavItem(icon: Icons.checklist_rounded, label: 'Tasks', selected: currentIndex == 3, onTap: () => onSelect(3))),
              Expanded(child: _NavItem(icon: Icons.sticky_note_2_rounded, label: 'Notes', selected: currentIndex == 4, onTap: () => onSelect(4))),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkResponse(
          onTap: onTap,
          radius: 32,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 22, color: selected ? AppColors.gold : AppColors.textHint),
              const SizedBox(height: 3),
              Text(label, maxLines: 1, style: TextStyle(fontSize: 10, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: selected ? AppColors.gold : AppColors.textHint)),
            ],
          ),
        ),
      );
}
