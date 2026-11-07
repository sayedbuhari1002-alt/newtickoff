import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Runtime palette tokens. The original Obsidian palette remains the default;
/// choosing another preset updates these tokens and Material components
/// together without changing screen layouts or saved habit/task colours.
class AppColors {
  AppColors._();

  static const String obsidian = 'obsidian_graphite_violet';
  static const String ocean = 'midnight_ocean_cyan';
  static const String porcelain = 'porcelain_sand_sage';

  static const Map<String, _Palette> _palettes = <String, _Palette>{
    obsidian: _Palette(
      background: Color(0xFF17171C), surface: Color(0xFF22212A),
      surfaceRaised: Color(0xFF2B2935), field: Color(0xFF1D1C24),
      sheet: Color(0xFF201F28), border: Color(0xFF393642),
      divider: Color(0xFF302E39), textPrimary: Color(0xFFEEEAF5),
      textSecondary: Color(0xFFA6A1B2), textHint: Color(0xFF777285),
      primaryAccent: Color(0xFFA78BFA), secondaryAccent: Color(0xFF8B9BB4),
      accentDim: Color(0xFF3B3154), onAccent: Color(0xFF201A2E),
      selectedSegment: Color(0xFF393544), switchTrackOn: Color(0xFF71638F),
      danger: Color(0xFFE53935), heatmapEmpty: Color(0xFF2B2935),
    ),
    ocean: _Palette(
      background: Color(0xFF101923), surface: Color(0xFF182633),
      surfaceRaised: Color(0xFF233746), field: Color(0xFF14212B),
      sheet: Color(0xFF16232F), border: Color(0xFF324653),
      divider: Color(0xFF293C49), textPrimary: Color(0xFFEAF6FB),
      textSecondary: Color(0xFFA5BEC7), textHint: Color(0xFF718B96),
      primaryAccent: Color(0xFF64D8E5), secondaryAccent: Color(0xFF86BBD8),
      accentDim: Color(0xFF254552), onAccent: Color(0xFF09252C),
      selectedSegment: Color(0xFF29424F), switchTrackOn: Color(0xFF397F8A),
      danger: Color(0xFFFF766F), heatmapEmpty: Color(0xFF233746),
    ),
    porcelain: _Palette(
      background: Color(0xFFF2F0E8), surface: Color(0xFFFFFFFF),
      surfaceRaised: Color(0xFFE8E6DC), field: Color(0xFFF8F7F2),
      sheet: Color(0xFFFFFFFF), border: Color(0xFFDAD7CA),
      divider: Color(0xFFEAE7DD), textPrimary: Color(0xFF272B29),
      textSecondary: Color(0xFF636D65), textHint: Color(0xFF8C968E),
      primaryAccent: Color(0xFF64856B), secondaryAccent: Color(0xFFBA9873),
      accentDim: Color(0xFFDDE9DE), onAccent: Color(0xFFFFFFFF),
      selectedSegment: Color(0xFFE6EEE5), switchTrackOn: Color(0xFFA5B9A5),
      danger: Color(0xFFC34F48), heatmapEmpty: Color(0xFFE6E7E1),
    ),
  };

  static String activeThemeId = obsidian;
  static _Palette get _p => _palettes[activeThemeId] ?? _palettes[obsidian]!;
  static bool get isLight => activeThemeId == porcelain;
  static void setTheme(String id) { activeThemeId = _palettes.containsKey(id) ? id : obsidian; }

  static Color get background => _p.background;
  static Color get surface => _p.surface;
  static Color get surfaceRaised => _p.surfaceRaised;
  static Color get field => _p.field;
  static Color get sheet => _p.sheet;
  static Color get border => _p.border;
  static Color get divider => _p.divider;
  static Color get textPrimary => _p.textPrimary;
  static Color get textSecondary => _p.textSecondary;
  static Color get textHint => _p.textHint;
  static Color get primaryAccent => _p.primaryAccent;
  static Color get secondaryAccent => _p.secondaryAccent;
  static Color get accentDim => _p.accentDim;
  static Color get onAccent => _p.onAccent;
  static Color get gold => primaryAccent;
  static Color get goldDim => accentDim;
  static Color get cyan => secondaryAccent;
  static Color get selectedSegment => _p.selectedSegment;
  static Color get switchTrackOn => _p.switchTrackOn;
  static Color get danger => _p.danger;
  static Color get heatmapEmpty => _p.heatmapEmpty;
  static Color get defaultHabitColor => primaryAccent;

  /// User-selected habit colours remain independent from the active theme.
  static const List<Color> habitPalette = <Color>[
    Color(0xFFA78BFA), Color(0xFFFFE0B2), Color(0xFFFFCC80),
    Color(0xFFFFA726), Color(0xFFFF7043), Color(0xFFE64A19),
    Color(0xFFD32F2F), Color(0xFFB71C1C), Color(0xFFE57373),
    Color(0xFFFFCDD2), Color(0xFFF48FB1), Color(0xFFEC407A),
    Color(0xFFD4A017), Color(0xFFFFB300), Color(0xFFFB8C00),
    Color(0xFFFF5722), Color(0xFFF44336), Color(0xFFA81818),
    Color(0xFFFF5252), Color(0xFFFF6E6E), Color(0xFFFF4081),
    Color(0xFFE91E63), Color(0xFFAB47BC), Color(0xFF7E57C2),
  ];
}

class _Palette {
  const _Palette({
    required this.background, required this.surface, required this.surfaceRaised,
    required this.field, required this.sheet, required this.border,
    required this.divider, required this.textPrimary, required this.textSecondary,
    required this.textHint, required this.primaryAccent,
    required this.secondaryAccent, required this.accentDim, required this.onAccent,
    required this.selectedSegment, required this.switchTrackOn,
    required this.danger, required this.heatmapEmpty,
  });
  final Color background, surface, surfaceRaised, field, sheet, border, divider;
  final Color textPrimary, textSecondary, textHint, primaryAccent, secondaryAccent;
  final Color accentDim, onAccent, selectedSegment, switchTrackOn, danger, heatmapEmpty;
}

extension ColorFade on Color {
  Color fade(double opacity) {
    final int alpha = math.max(0, math.min(255, (opacity * 255).round()));
    return withAlpha(alpha);
  }
}
