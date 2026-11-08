import 'package:flutter/foundation.dart';

@immutable
class TaskProgressEvent {
  const TaskProgressEvent({
    required this.id,
    required this.taskId,
    required this.previousValue,
    required this.newValue,
    required this.previousPercent,
    required this.newPercent,
    required this.progressDelta,
    required this.occurredAt,
    this.difficultyScore = 1.0,
    this.note = '',
  });

  final String id;
  final String taskId;
  final double previousValue;
  final double newValue;
  final double previousPercent;
  final double newPercent;
  /// Signed percentage-point change. Positive deltas can feed future daily scoring.
  final double progressDelta;
  /// Difficulty captured at the time of the progress event so later edits do
  /// not rewrite historical productivity calculations.
  final double difficultyScore;
  final DateTime occurredAt;
  final String note;

  factory TaskProgressEvent.fromMap(Map<String, Object?> row) => TaskProgressEvent(
        id: row['id'] as String,
        taskId: row['task_id'] as String,
        previousValue: (row['previous_value'] as num?)?.toDouble() ?? 0,
        newValue: (row['new_value'] as num?)?.toDouble() ?? 0,
        previousPercent: (row['previous_percent'] as num?)?.toDouble() ?? 0,
        newPercent: (row['new_percent'] as num?)?.toDouble() ?? 0,
        progressDelta: (row['progress_delta'] as num?)?.toDouble() ?? 0,
        difficultyScore: (row['difficulty_score'] as num?)?.toDouble() ?? 1.0,
        occurredAt: DateTime.tryParse(row['occurred_at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
        note: row['note'] as String? ?? '',
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'task_id': taskId,
        'previous_value': previousValue,
        'new_value': newValue,
        'previous_percent': previousPercent,
        'new_percent': newPercent,
        'progress_delta': progressDelta,
        'difficulty_score': difficultyScore,
        'occurred_at': occurredAt.toIso8601String(),
        'note': note,
      };
}
