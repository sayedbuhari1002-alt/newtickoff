import 'package:flutter/services.dart';

import '../../domain/models/models.dart';

/// Android UsageStats bridge. On every other platform the service reports
/// permission unavailable and manual distraction logging remains usable.
class ProductivityUsageService {
  ProductivityUsageService._();
  static final ProductivityUsageService instance = ProductivityUsageService._();
  static const MethodChannel _channel = MethodChannel('tazkiyane/usage_stats');

  Future<bool> hasPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasUsageAccess') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openUsageAccessSettings');
    } on MissingPluginException {
      throw StateError('Automatic app-usage tracking is available in the Android app only.');
    }
  }

  Future<List<AppUsageRecord>> readUsageForDay({
    required DateTime day,
    required List<DistractionCategory> categories,
  }) async {
    final Map<String, DistractionCategory> packageToCategory = <String, DistractionCategory>{};
    for (final DistractionCategory category in categories.where((DistractionCategory c) => c.autoTrack)) {
      for (final String packageName in category.packageNames) {
        if (packageName.trim().isNotEmpty) packageToCategory[packageName.trim()] = category;
      }
    }
    if (packageToCategory.isEmpty) return <AppUsageRecord>[];
    final DateTime start = DateTime(day.year, day.month, day.day);
    final DateTime end = start.add(const Duration(days: 1));
    final List<dynamic>? raw;
    try {
      raw = await _channel.invokeListMethod<dynamic>('queryUsageEvents', <String, Object?>{
        // Include the previous day so an app already in the foreground at
        // midnight is still paired with its first background event. Returned
        // sessions are clipped back to the selected date below.
        'startMillis': start.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
        'endMillis': end.millisecondsSinceEpoch,
        'packageNames': packageToCategory.keys.toList(),
      });
    } on MissingPluginException {
      return <AppUsageRecord>[];
    }
    final List<AppUsageRecord> records = <AppUsageRecord>[];
    for (final dynamic item in raw ?? const <dynamic>[]) {
      if (item is! Map) continue;
      final String packageName = item['packageName'] as String? ?? '';
      final DistractionCategory? category = packageToCategory[packageName];
      final int? startMillis = (item['startMillis'] as num?)?.toInt();
      final int? endMillis = (item['endMillis'] as num?)?.toInt();
      if (category == null || startMillis == null || endMillis == null || endMillis <= startMillis) continue;
      final DateTime rawFrom = DateTime.fromMillisecondsSinceEpoch(startMillis);
      final DateTime rawTo = DateTime.fromMillisecondsSinceEpoch(endMillis);
      final DateTime from = rawFrom.isBefore(start) ? start : rawFrom;
      final DateTime to = rawTo.isAfter(end) ? end : rawTo;
      final String id = 'usage_${packageName}_${startMillis}_$endMillis'.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      records.add(AppUsageRecord(id: id, categoryId: category.id, packageName: packageName, startAt: from, endAt: to, severityPointsPerHour: category.severityPointsPerHour));
    }
    return records;
  }
}
