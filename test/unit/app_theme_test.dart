import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tickoff_replacement/core/theme/app_colors.dart';
import 'package:tickoff_replacement/core/theme/app_theme.dart';
import 'package:tickoff_replacement/domain/models/models.dart';

void main() {
  group('Obsidian Graphite + Violet theme', () {
    test('uses the agreed surface and accent palette', () {
      expect(AppColors.background, const Color(0xFF17171C));
      expect(AppColors.surface, const Color(0xFF22212A));
      expect(AppColors.surfaceRaised, const Color(0xFF2B2935));
      expect(AppColors.primaryAccent, const Color(0xFFA78BFA));
      expect(AppColors.secondaryAccent, const Color(0xFF8B9BB4));
      expect(AppColors.textPrimary, const Color(0xFFEEEAF5));
      expect(AppColors.textSecondary, const Color(0xFFA6A1B2));
      expect(AppColors.border, const Color(0xFF393642));
    });

    test('newly created items use the violet accent by default', () {
      final DateTime now = DateTime(2026, 11, 6);
      final Task task = Task(
        id: 'task-1',
        title: 'New task',
        createdAt: now,
        updatedAt: now,
      );
      const ExpenseCategory category = ExpenseCategory(
        id: 'category-1',
        name: 'General',
      );

      expect(Habit.defaultColorValue, 0xFFA78BFA);
      expect(task.colorValue, 0xFFA78BFA);
      expect(category.colorValue, 0xFFA78BFA);
    });

    test('Material theme uses the same palette', () {
      final theme = AppTheme.dark();
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, AppColors.background);
      expect(theme.colorScheme.primary, AppColors.primaryAccent);
      expect(theme.colorScheme.secondary, AppColors.secondaryAccent);
      expect(theme.colorScheme.surface, AppColors.surface);
    });
  });
}
