import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_dimens.dart';

/// Material theme builder for the three saved Tazkiyane appearance presets.
class AppTheme {
  AppTheme._();

  static ThemeData dark() => forId(AppColors.obsidian);

  static ThemeData forId(String id) {
    AppColors.setTheme(id);
    final bool light = AppColors.isLight;
    final ColorScheme scheme = light
        ? ColorScheme.light(
            primary: AppColors.primaryAccent,
            onPrimary: AppColors.onAccent,
            secondary: AppColors.secondaryAccent,
            onSecondary: Colors.white,
            surface: AppColors.surface,
            onSurface: AppColors.textPrimary,
            error: AppColors.danger,
            onError: Colors.white,
            outline: AppColors.border,
            outlineVariant: AppColors.divider,
          )
        : ColorScheme.dark(
            primary: AppColors.primaryAccent,
            onPrimary: AppColors.onAccent,
            secondary: AppColors.secondaryAccent,
            onSecondary: AppColors.background,
            surface: AppColors.surface,
            onSurface: AppColors.textPrimary,
            error: AppColors.danger,
            onError: Colors.white,
            outline: AppColors.border,
            outlineVariant: AppColors.divider,
          );

    return ThemeData(
      useMaterial3: true,
      brightness: light ? Brightness.light : Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      dividerColor: AppColors.divider,
      cardColor: AppColors.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.sheet,
        modalBackgroundColor: AppColors.sheet,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimens.radiusXl)),
        ),
      ),
      dialogTheme: DialogThemeData(backgroundColor: AppColors.surfaceRaised, surfaceTintColor: Colors.transparent),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.field,
        hintStyle: TextStyle(color: AppColors.textHint),
        labelStyle: TextStyle(color: AppColors.textSecondary),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          borderSide: BorderSide(color: AppColors.primaryAccent, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          borderSide: BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          borderSide: BorderSide(color: AppColors.danger, width: 1.4),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.primaryAccent,
        selectionColor: AppColors.primaryAccent.withAlpha(70),
        selectionHandleColor: AppColors.primaryAccent,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.primaryAccent,
        linearTrackColor: AppColors.surfaceRaised,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) =>
          states.contains(WidgetState.selected) ? AppColors.primaryAccent : AppColors.textSecondary),
        trackColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) =>
          states.contains(WidgetState.selected) ? AppColors.switchTrackOn : AppColors.surfaceRaised),
        trackOutlineColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) =>
          states.contains(WidgetState.selected) ? Colors.transparent : AppColors.border),
      ),
    );
  }
}
