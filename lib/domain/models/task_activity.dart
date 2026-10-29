import 'dart:convert';

import 'package:flutter/foundation.dart';

@immutable
class TaskActivity {
  const TaskActivity({
    required this.id,
    required this.taskId,
    required this.entityId,
    required this.entityType,
    required this.eventType,
    required this.occurredAt,
    required this.snapshotJson,
  });

  final String id;
  final String taskId;
  final String entityId;
  final String entityType; // task or subtask
  final String eventType;
  final DateTime occurredAt;
  final String snapshotJson;

  Map<String, dynamic> get snapshot {
    try {
      final Object? decoded = jsonDecode(snapshotJson);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  factory TaskActivity.fromMap(Map<String, Object?> row) => TaskActivity(
        id: row['id'] as String,
        taskId: row['task_id'] as String,
        entityId: row['entity_id'] as String,
        entityType: row['entity_type'] as String,
        eventType: row['event_type'] as String,
        occurredAt: DateTime.tryParse(row['occurred_at'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
        snapshotJson: row['snapshot_json'] as String? ?? '{}',
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'task_id': taskId,
        'entity_id': entityId,
        'entity_type': entityType,
        'event_type': eventType,
        'occurred_at': occurredAt.toIso8601String(),
        'snapshot_json': snapshotJson,
      };
}
