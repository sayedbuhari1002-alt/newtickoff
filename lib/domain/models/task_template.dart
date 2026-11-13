import 'package:flutter/foundation.dart';

import 'task.dart';

@immutable
class TaskTemplate {
  const TaskTemplate({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.taskType = TaskType.standard,
    this.progressMode = TaskProgressMode.percentage,
    this.progressTarget = 100,
    this.progressUnit = '',
    this.difficultyScore = 1.0,
    this.priority = TaskPriority.medium,
    this.category = '',
    this.iconKey = 'task',
    this.colorValue = 0xFFA78BFA,
    this.repeat = TaskRepeat.none,
    this.notes = '',
    this.photoPaths = const <String>[],
    this.audioPaths = const <String>[],
    this.subtasks = const <Subtask>[],
  });

  final String id;
  final String name;
  final TaskType taskType;
  final TaskProgressMode progressMode;
  final double progressTarget;
  final String progressUnit;
  final double difficultyScore;
  final TaskPriority priority;
  final String category;
  final String iconKey;
  final int colorValue;
  final TaskRepeat repeat;
  final String notes;
  final List<String> photoPaths;
  final List<String> audioPaths;
  final List<Subtask> subtasks;
  final DateTime createdAt;
  final DateTime updatedAt;

  TaskTemplate copyWith({
    String? name,
    TaskType? taskType,
    TaskProgressMode? progressMode,
    double? progressTarget,
    String? progressUnit,
    double? difficultyScore,
    TaskPriority? priority,
    String? category,
    String? iconKey,
    int? colorValue,
    TaskRepeat? repeat,
    String? notes,
    List<String>? photoPaths,
    List<String>? audioPaths,
    List<Subtask>? subtasks,
    DateTime? updatedAt,
  }) => TaskTemplate(
        id: id,
        name: name ?? this.name,
        taskType: taskType ?? this.taskType,
        progressMode: progressMode ?? this.progressMode,
        progressTarget: progressTarget ?? this.progressTarget,
        progressUnit: progressUnit ?? this.progressUnit,
        difficultyScore: difficultyScore ?? this.difficultyScore,
        priority: priority ?? this.priority,
        category: category ?? this.category,
        iconKey: iconKey ?? this.iconKey,
        colorValue: colorValue ?? this.colorValue,
        repeat: repeat ?? this.repeat,
        notes: notes ?? this.notes,
        photoPaths: photoPaths ?? this.photoPaths,
        audioPaths: audioPaths ?? this.audioPaths,
        subtasks: subtasks ?? this.subtasks,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
