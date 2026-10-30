import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_dimens.dart';

/// Dark appearance presets for the reference UI.
///
/// The default preset preserves the original black/gold/cyan palette. The
/// optional Graphite preset changes Material surfaces without recolouring
/// user-selected habit or task accents.
class AppTheme {
  AppTheme._();

  static ThemeData dark({bool graphite = false}) {
    final Color background = graphite ? const Color(0xFF101114) : AppColors.background;
    final Color surface = graphite ? const Color(0xFF202126) : AppColors.surface;
    final Color sheet = graphite ? const Color(0xFF17181B) : AppColors.sheet;
    final ColorScheme scheme = ColorScheme.dark(
      primary: AppColors.gold,
      onPrimary: Colors.black,
      secondary: AppColors.cyan,
      onSecondary: Colors.black,
      surface: surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      dividerColor: AppColors.divider,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: sheet,
        modalBackgroundColor: sheet,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppDimens.radiusXl),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? AppColors.cyan
              : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? AppColors.switchTrackOn
              : Colors.black,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : Colors.white,
        ),
      ),
    );
  }
}
