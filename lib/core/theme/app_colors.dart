import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared colour tokens for the Obsidian Graphite + Violet appearance.
///
/// The historic [gold] and [cyan] names remain as compatibility aliases so
/// existing screens keep their layout and behaviour while using the new,
/// unified accent system.
class AppColors {
  AppColors._();

  // Surfaces
  static const Color background = Color(0xFF17171C);
  static const Color surface = Color(0xFF22212A);
  static const Color surfaceRaised = Color(0xFF2B2935);
  static const Color field = Color(0xFF1D1C24);
  static const Color sheet = Color(0xFF201F28);
  static const Color border = Color(0xFF393642);
  static const Color divider = Color(0xFF302E39);

  // Text
  static const Color textPrimary = Color(0xFFEEEAF5);
  static const Color textSecondary = Color(0xFFA6A1B2);
  static const Color textHint = Color(0xFF777285);

  // Accent system
  static const Color primaryAccent = Color(0xFFA78BFA);
  static const Color secondaryAccent = Color(0xFF8B9BB4);
  static const Color accentDim = Color(0xFF3B3154);
  static const Color onAccent = Color(0xFF201A2E);

  // Compatibility aliases used by the existing screens.
  static const Color gold = primaryAccent;
  static const Color goldDim = accentDim;
  static const Color cyan = secondaryAccent;

  static const Color selectedSegment = Color(0xFF393544);
  static const Color switchTrackOn = Color(0xFF71638F);

  // Status and data visualisation
  static const Color danger = Color(0xFFE53935);
  static const Color heatmapEmpty = Color(0xFF2B2935);

  /// Default colour for a newly created habit.
  static const Color defaultHabitColor = primaryAccent;

  /// Habit colour palette. The first swatch follows the current app accent;
  /// the remaining user-selectable colours are intentionally unchanged.
  static const List<Color> habitPalette = <Color>[
    primaryAccent,
    Color(0xFFFFE0B2),
    Color(0xFFFFCC80),
    Color(0xFFFFA726),
    Color(0xFFFF7043),
    Color(0xFFE64A19),
    Color(0xFFD32F2F),
    Color(0xFFB71C1C),
    Color(0xFFE57373),
    Color(0xFFFFCDD2),
    Color(0xFFF48FB1),
    Color(0xFFEC407A),
    Color(0xFFD4A017),
    Color(0xFFFFB300),
    Color(0xFFFB8C00),
    Color(0xFFFF5722),
    Color(0xFFF44336),
    Color(0xFFA81818),
    Color(0xFFFF5252),
    Color(0xFFFF6E6E),
    Color(0xFFFF4081),
    Color(0xFFE91E63),
    Color(0xFFAB47BC),
    Color(0xFF7E57C2),
  ];
}

extension ColorFade on Color {
  /// Returns this colour with the given opacity (0.0 - 1.0).
  Color fade(double opacity) {
    final int alpha = math.max(0, math.min(255, (opacity * 255).round()));
    return withAlpha(alpha);
  }
}
