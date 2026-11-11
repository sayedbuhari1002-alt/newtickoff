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

  Future<List<InstalledApp>> getInstalledApps() async {
    final List<dynamic>? raw = await _channel.invokeListMethod<dynamic>('getInstalledApps');
    final List<InstalledApp> apps = <InstalledApp>[];
    for (final dynamic item in raw ?? const <dynamic>[]) {
      if (item is! Map) continue;
      final String packageName = item['packageName'] as String? ?? '';
      final String label = item['label'] as String? ?? packageName;
      if (packageName.isNotEmpty) apps.add(InstalledApp(packageName: packageName, label: label));
    }
    apps.sort((InstalledApp a, InstalledApp b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return apps;
  }

  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openUsageAccessSettings');
    } on MissingPluginException {
      throw StateError('Automatic app-usage tracking is available in the Android app only.');
    }
  }

  /// Reads two independent Android sources for a local calendar day:
  /// - UsageEvents gives timestamped foreground sessions.
  /// - UsageStatsManager gives Android's aggregated foreground duration.
  ///
  /// The daily aggregate is used for the displayed daily total and the event
  /// timeline is retained for time-aware, overlap-safe productivity scoring.
  Future<UsageDayResult> readUsageForDay({
    required DateTime day,
    required List<DistractionCategory> categories,
  }) async {
    final Map<String, DistractionCategory> packageToCategory = <String, DistractionCategory>{};
    for (final DistractionCategory category in categories.where((DistractionCategory c) => c.autoTrack)) {
      for (final String packageName in category.packageNames) {
        if (packageName.trim().isNotEmpty) packageToCategory[packageName.trim()] = category;
      }
    }
    if (packageToCategory.isEmpty) {
      return const UsageDayResult(sessions: <AppUsageRecord>[], dailyTotals: <AppUsageDailyTotal>[]);
    }

    final DateTime start = DateTime(day.year, day.month, day.day);
    final DateTime end = start.add(const Duration(days: 1));
    final List<String> packages = packageToCategory.keys.toList();

    List<dynamic> rawEvents = <dynamic>[];
    try {
      rawEvents = await _channel.invokeListMethod<dynamic>('queryUsageEvents', <String, Object?>{
        // Look back one complete day so sessions crossing midnight can be paired.
        'startMillis': start.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
        'endMillis': end.millisecondsSinceEpoch,
        'packageNames': packages,
      }) ?? <dynamic>[];
    } on MissingPluginException {
      // The native aggregate query below can still supply daily usage.
    } on PlatformException {
      // Keep the independent aggregate result rather than losing all tracking.
    }

    final List<AppUsageRecord> sessions = <AppUsageRecord>[];
    for (final dynamic item in rawEvents) {
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
      if (!to.isAfter(from)) continue;
      final String id = 'usage_${packageName}_${startMillis}_$endMillis'.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      sessions.add(AppUsageRecord(
        id: id,
        categoryId: category.id,
        packageName: packageName,
        startAt: from,
        endAt: to,
        severityPointsPerHour: category.severityPointsPerHour,
      ));
    }
    sessions.sort((AppUsageRecord a, AppUsageRecord b) => a.startAt.compareTo(b.startAt));

    bool nativeStatsAvailable = false;
    final Map<String, int> androidMillisByPackage = <String, int>{};
    try {
      final Map<String, dynamic>? nativeResult = await _channel.invokeMapMethod<String, dynamic>(
        'queryDailyUsageStats',
        <String, Object?>{
          'startMillis': start.millisecondsSinceEpoch,
          'endMillis': end.millisecondsSinceEpoch,
          'packageNames': packages,
        },
      );
      nativeStatsAvailable = nativeResult?['available'] == true;
      final dynamic nativeItems = nativeResult?['items'];
      if (nativeItems is List) {
        for (final dynamic item in nativeItems) {
          if (item is! Map) continue;
          final String packageName = item['packageName'] as String? ?? '';
          final int? foregroundMillis = (item['foregroundMillis'] as num?)?.toInt();
          if (packageToCategory.containsKey(packageName) && foregroundMillis != null) {
            androidMillisByPackage[packageName] = foregroundMillis < 0 ? 0 : foregroundMillis;
          }
        }
      }
    } on MissingPluginException {
      nativeStatsAvailable = false;
    } on PlatformException {
      nativeStatsAvailable = false;
    }

    final Map<String, int> reconstructedMillisByPackage = <String, int>{};
    for (final AppUsageRecord session in sessions) {
      reconstructedMillisByPackage.update(
        session.packageName,
        (int old) => old + session.endAt.difference(session.startAt).inMilliseconds,
        ifAbsent: () => session.endAt.difference(session.startAt).inMilliseconds,
      );
    }

    final String key = _dateKey(start);
    final List<AppUsageDailyTotal> dailyTotals = <AppUsageDailyTotal>[];
    for (final MapEntry<String, DistractionCategory> entry in packageToCategory.entries) {
      final String packageName = entry.key;
      final int reconstructedMillis = reconstructedMillisByPackage[packageName] ?? 0;
      dailyTotals.add(AppUsageDailyTotal(
        id: 'usage_day_${key}_$packageName'.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_'),
        dateKey: key,
        categoryId: entry.value.id,
        packageName: packageName,
        androidForegroundMillis: nativeStatsAvailable ? (androidMillisByPackage[packageName] ?? 0) : 0,
        reconstructedMillis: reconstructedMillis,
        nativeStatsAvailable: nativeStatsAvailable,
      ));
    }
    dailyTotals.sort((AppUsageDailyTotal a, AppUsageDailyTotal b) => a.packageName.compareTo(b.packageName));
    return UsageDayResult(sessions: sessions, dailyTotals: dailyTotals);
  }

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class UsageDayResult {
  const UsageDayResult({required this.sessions, required this.dailyTotals});
  final List<AppUsageRecord> sessions;
  final List<AppUsageDailyTotal> dailyTotals;
}

/// An installed Android application shown by name in the distraction-app picker.
class InstalledApp {
  const InstalledApp({required this.packageName, required this.label});
  final String packageName;
  final String label;
}
