import 'dart:convert';

import 'package:flutter/foundation.dart';

@immutable
class Assignment {
  const Assignment({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.description = '',
    this.dueAt,
    this.priority = 'medium',
    this.difficultyScore = 1.0,
    this.category = '',
    this.isCompleted = false,
    this.completedAt,
    this.completedPoints,
  });

  final String id;
  final String title;
  final String description;
  final DateTime? dueAt;
  final String priority;
  final double difficultyScore;
  final String category;
  final bool isCompleted;
  /// First completion is retained after reopening to prevent duplicate awards.
  final DateTime? completedAt;
  /// The point value captured at first completion, retained if the assignment is edited.
  final double? completedPoints;
  final DateTime createdAt;
  final DateTime updatedAt;

  Assignment copyWith({
    String? title,
    String? description,
    DateTime? dueAt,
    bool clearDueAt = false,
    String? priority,
    double? difficultyScore,
    String? category,
    bool? isCompleted,
    DateTime? completedAt,
    double? completedPoints,
    DateTime? updatedAt,
  }) => Assignment(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    dueAt: clearDueAt ? null : (dueAt ?? this.dueAt),
    priority: priority ?? this.priority,
    difficultyScore: difficultyScore ?? this.difficultyScore,
    category: category ?? this.category,
    isCompleted: isCompleted ?? this.isCompleted,
    completedAt: completedAt ?? this.completedAt,
    completedPoints: completedPoints ?? this.completedPoints,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
  );

  String? validate() {
    if (title.trim().isEmpty) return 'Enter an assignment title.';
    if (!difficultyScore.isFinite || difficultyScore < 1 || difficultyScore > 10) {
      return 'Assignment points must be between 1 and 10.';
    }
    return null;
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id, 'title': title.trim(), 'description': description,
    'due_at': dueAt?.toIso8601String(), 'priority': priority,
    'difficulty_score': difficultyScore, 'category': category,
    'is_completed': isCompleted ? 1 : 0,
    'completed_at': completedAt?.toIso8601String(),
    'completed_points': completedPoints,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory Assignment.fromMap(Map<String, Object?> row) => Assignment(
    id: row['id'] as String,
    title: row['title'] as String? ?? '',
    description: row['description'] as String? ?? '',
    dueAt: DateTime.tryParse(row['due_at'] as String? ?? ''),
    priority: row['priority'] as String? ?? 'medium',
    difficultyScore: (row['difficulty_score'] as num?)?.toDouble() ?? 1.0,
    category: row['category'] as String? ?? '',
    isCompleted: (row['is_completed'] as int? ?? 0) != 0,
    completedAt: DateTime.tryParse(row['completed_at'] as String? ?? ''),
    completedPoints: (row['completed_points'] as num?)?.toDouble(),
    createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
  );
}

@immutable
class DistractionCategory {
  const DistractionCategory({
    required this.id,
    required this.name,
    required this.severityPointsPerHour,
    required this.createdAt,
    this.details = '',
    this.autoTrack = false,
    this.packageNames = const <String>[],
  });
  final String id;
  final String name;
  final double severityPointsPerHour;
  final String details;
  final bool autoTrack;
  final List<String> packageNames;
  final DateTime createdAt;

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id, 'name': name.trim(), 'severity_points_per_hour': severityPointsPerHour,
    'details': details, 'auto_track': autoTrack ? 1 : 0,
    'package_names_json': jsonEncode(packageNames.toSet().toList()),
    'created_at': createdAt.toIso8601String(),
  };

  factory DistractionCategory.fromMap(Map<String, Object?> row) => DistractionCategory(
    id: row['id'] as String,
    name: row['name'] as String? ?? '',
    severityPointsPerHour: (row['severity_points_per_hour'] as num?)?.toDouble() ?? 1.0,
    details: row['details'] as String? ?? '',
    autoTrack: (row['auto_track'] as int? ?? 0) != 0,
    packageNames: _decodePackageNames(row['package_names_json'] as String? ?? '[]'),
    createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
  );
}

@immutable
class DistractionLog {
  const DistractionLog({
    required this.id,
    required this.categoryId,
    required this.startAt,
    required this.endAt,
    this.details = '',
    this.severityPointsPerHour,
  });
  final String id;
  final String categoryId;
  final DateTime startAt;
  final DateTime endAt;
  final String details;
  final double? severityPointsPerHour;
  double get durationMinutes => endAt.difference(startAt).inSeconds / 60;
  Map<String, Object?> toMap() => <String, Object?>{
    'id': id, 'category_id': categoryId, 'start_at': startAt.toIso8601String(),
    'end_at': endAt.toIso8601String(), 'details': details,
    'severity_points_per_hour': severityPointsPerHour,
  };
  factory DistractionLog.fromMap(Map<String, Object?> row) => DistractionLog(
    id: row['id'] as String, categoryId: row['category_id'] as String,
    startAt: DateTime.tryParse(row['start_at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
    endAt: DateTime.tryParse(row['end_at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
    details: row['details'] as String? ?? '',
    severityPointsPerHour: (row['severity_points_per_hour'] as num?)?.toDouble(),
  );
}

@immutable
class AppUsageRecord {
  const AppUsageRecord({
    required this.id,
    required this.categoryId,
    required this.packageName,
    required this.startAt,
    required this.endAt,
    this.severityPointsPerHour,
  });
  final String id;
  final String categoryId;
  final String packageName;
  final DateTime startAt;
  final DateTime endAt;
  final double? severityPointsPerHour;
  Map<String, Object?> toMap() => <String, Object?>{
    'id': id, 'category_id': categoryId, 'package_name': packageName,
    'start_at': startAt.toIso8601String(), 'end_at': endAt.toIso8601String(),
    'severity_points_per_hour': severityPointsPerHour,
  };
  factory AppUsageRecord.fromMap(Map<String, Object?> row) => AppUsageRecord(
    id: row['id'] as String, categoryId: row['category_id'] as String,
    packageName: row['package_name'] as String? ?? '',
    startAt: DateTime.tryParse(row['start_at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
    endAt: DateTime.tryParse(row['end_at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
    severityPointsPerHour: (row['severity_points_per_hour'] as num?)?.toDouble(),
  );
}

@immutable
class ProductivityTargetChange {
  const ProductivityTargetChange({required this.effectiveDate, required this.target});
  final String effectiveDate;
  final double target;
  Map<String, Object?> toMap() => <String, Object?>{
    'effective_date': effectiveDate, 'target': target,
  };
}

List<String> _decodePackageNames(String raw) {
  try {
    final Object? value = jsonDecode(raw);
    return value is List ? value.whereType<String>().map((String p) => p.trim()).where((String p) => p.isNotEmpty).toSet().toList() : <String>[];
  } catch (_) {
    return <String>[];
  }
}
