import 'dart:convert';

import 'package:flutter/foundation.dart';

enum TaskPriority { low, medium, high }
enum TaskRepeat { none, daily, weekly, monthly }

enum TaskType { standard, progressive }
enum TaskProgressMode { percentage, count }

@immutable
class Subtask {
  const Subtask({
    required this.id,
    required this.title,
    required this.createdAt,
    this.dueAt,
    this.reminderAt,
    this.isCompleted = false,
    this.completedAt,
    this.sortOrder = 0,
    this.difficultyScore = 1.0,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime? dueAt;
  final DateTime? reminderAt;
  final bool isCompleted;
  final DateTime? completedAt;
  final int sortOrder;
  final double difficultyScore;

  Subtask copyWith({
    String? title,
    DateTime? dueAt,
    bool clearDueAt = false,
    DateTime? reminderAt,
    bool clearReminderAt = false,
    bool? isCompleted,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    int? sortOrder,
    double? difficultyScore,
  }) => Subtask(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        dueAt: clearDueAt ? null : (dueAt ?? this.dueAt),
        reminderAt: clearReminderAt ? null : (reminderAt ?? this.reminderAt),
        isCompleted: isCompleted ?? this.isCompleted,
        completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
        sortOrder: sortOrder ?? this.sortOrder,
        difficultyScore: difficultyScore ?? this.difficultyScore,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'dueAt': dueAt?.toIso8601String(),
        'reminderAt': reminderAt?.toIso8601String(),
        'isCompleted': isCompleted,
        'completedAt': completedAt?.toIso8601String(),
        'sortOrder': sortOrder,
        'difficultyScore': difficultyScore,
      };

  factory Subtask.fromJson(Map<String, dynamic> json) {
    final DateTime created = DateTime.tryParse('${json['createdAt'] ?? ''}') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return Subtask(
      id: json['id'] as String,
      title: (json['title'] as String? ?? '').trim(),
      createdAt: created,
      dueAt: DateTime.tryParse('${json['dueAt'] ?? ''}'),
      reminderAt: DateTime.tryParse('${json['reminderAt'] ?? ''}'),
      isCompleted: json['isCompleted'] == true,
      completedAt: DateTime.tryParse('${json['completedAt'] ?? ''}'),
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      difficultyScore: (json['difficultyScore'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

@immutable
class Task {
  const Task({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.description = '',
    this.dueAt,
    this.reminderAt,
    this.priority = TaskPriority.medium,
    this.category = '',
    this.iconKey = 'task',
    this.colorValue = 0xFFA78BFA,
    this.isCompleted = false,
    this.completedAt,
    this.isPaused = false,
    this.repeat = TaskRepeat.none,
    this.notes = '',
    this.photoPaths = const <String>[],
    this.audioPaths = const <String>[],
    this.subtasks = const <Subtask>[],
    this.parentTaskId,
    this.isGroup = false,
    this.taskType = TaskType.standard,
    this.progressMode = TaskProgressMode.percentage,
    this.progressValue = 0,
    this.progressTarget = 100,
    this.progressUnit = '',
    this.difficultyScore = 1.0,
    this.sortOrder = 0,
    this.scheduledDate,
  });

  final String id;
  final String title;
  final String description;
  final DateTime? dueAt;
  final DateTime? reminderAt;
  /// Calendar date the user has planned to work on this task, separate from its deadline.
  final DateTime? scheduledDate;
  final TaskPriority priority;
  final String category;
  final String iconKey;
  final int colorValue;
  final bool isCompleted;
  final DateTime? completedAt;
  final bool isPaused;
  final TaskRepeat repeat;
  final String notes;
  final List<String> photoPaths;
  final List<String> audioPaths;

  /// Legacy inline checklist items are retained for existing installations.
  /// New task grouping uses independent [Task] records and [parentTaskId].
  final List<Subtask> subtasks;

  /// Parent relationship for a first-class task group. A group has no parent;
  /// its children are ordinary Task records with this ID.
  final String? parentTaskId;
  final bool isGroup;

  final TaskType taskType;
  final TaskProgressMode progressMode;
  /// Percentage (0..100) or completed count, depending on [progressMode].
  final double progressValue;
  /// 100 for percentage mode; configured total for count mode.
  final double progressTarget;
  final String progressUnit;
  /// Reusable weight for future Productivity scoring (supports decimals).
  final double difficultyScore;
  final int sortOrder;

  final DateTime createdAt;
  final DateTime updatedAt;

  int get completedSubtasks => subtasks.where((Subtask s) => s.isCompleted).length;
  double get subtaskProgress => subtasks.isEmpty ? (isCompleted ? 1 : 0) : completedSubtasks / subtasks.length;
  bool get hasSubtasks => subtasks.isNotEmpty;

  double get progressPercent {
    if (taskType == TaskType.standard) return isCompleted ? 100 : 0;
    if (progressMode == TaskProgressMode.count) {
      if (progressTarget <= 0) return 0;
      return ((progressValue / progressTarget) * 100).clamp(0, 100).toDouble();
    }
    return progressValue.clamp(0, 100).toDouble();
  }

  String get progressDisplay => progressMode == TaskProgressMode.count
      ? '${progressValue.toStringAsFixed(progressValue == progressValue.roundToDouble() ? 0 : 1)} / ${progressTarget.toStringAsFixed(progressTarget == progressTarget.roundToDouble() ? 0 : 1)}${progressUnit.isEmpty ? '' : ' $progressUnit'}'
      : '${progressPercent.toStringAsFixed(progressPercent == progressPercent.roundToDouble() ? 0 : 1)}%';

  /// A task is overdue only after its deadline calendar day has ended.
  /// A time-of-day deadline never makes a task overdue on the same date.
  bool get isOverdue {
    if (isCompleted || isPaused || dueAt == null) return false;
    final DateTime dueDay = DateTime(dueAt!.year, dueAt!.month, dueAt!.day);
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    return dueDay.isBefore(today);
  }

  String? validate() {
    if (title.trim().isEmpty) return 'Please enter a task title.';
    if (subtasks.any((Subtask s) => s.title.trim().isEmpty)) return 'Subtask names cannot be empty.';
    if (subtasks.any((Subtask s) => !s.difficultyScore.isFinite || s.difficultyScore < 1 || s.difficultyScore > 5)) {
      return 'Subtask points must be between 1 and 5.';
    }
    if (dueAt != null && reminderAt != null) {
      final DateTime deadlineDay = DateTime(dueAt!.year, dueAt!.month, dueAt!.day);
      final DateTime reminderDay = DateTime(reminderAt!.year, reminderAt!.month, reminderAt!.day);
      if (reminderDay.isAfter(deadlineDay)) {
        return 'The reminder date cannot be after the deadline date.';
      }
    }
    if (difficultyScore < 1 || difficultyScore > 5) {
      return 'Difficulty score must be between 1 and 5.';
    }
    if (taskType == TaskType.progressive && progressTarget <= 0) {
      return 'Progress target must be greater than zero.';
    }
    if (progressValue < 0 || progressValue > progressTarget) {
      return 'Progress must be between zero and the configured target.';
    }
    return null;
  }

  Task copyWith({
    String? title,
    String? description,
    DateTime? dueAt,
    bool clearDueAt = false,
    DateTime? reminderAt,
    bool clearReminderAt = false,
    DateTime? scheduledDate,
    bool clearScheduledDate = false,
    TaskPriority? priority,
    String? category,
    String? iconKey,
    int? colorValue,
    bool? isCompleted,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    bool? isPaused,
    TaskRepeat? repeat,
    String? notes,
    List<String>? photoPaths,
    List<String>? audioPaths,
    List<Subtask>? subtasks,
    String? parentTaskId,
    bool clearParentTaskId = false,
    bool? isGroup,
    TaskType? taskType,
    TaskProgressMode? progressMode,
    double? progressValue,
    double? progressTarget,
    String? progressUnit,
    double? difficultyScore,
    int? sortOrder,
    DateTime? updatedAt,
  }) => Task(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        dueAt: clearDueAt ? null : (dueAt ?? this.dueAt),
        reminderAt: clearReminderAt ? null : (reminderAt ?? this.reminderAt),
        scheduledDate: clearScheduledDate ? null : (scheduledDate ?? this.scheduledDate),
        priority: priority ?? this.priority,
        category: category ?? this.category,
        iconKey: iconKey ?? this.iconKey,
        colorValue: colorValue ?? this.colorValue,
        isCompleted: isCompleted ?? this.isCompleted,
        completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
        isPaused: isPaused ?? this.isPaused,
        repeat: repeat ?? this.repeat,
        notes: notes ?? this.notes,
        photoPaths: photoPaths ?? this.photoPaths,
        audioPaths: audioPaths ?? this.audioPaths,
        subtasks: subtasks ?? this.subtasks,
        parentTaskId: clearParentTaskId ? null : (parentTaskId ?? this.parentTaskId),
        isGroup: isGroup ?? this.isGroup,
        taskType: taskType ?? this.taskType,
        progressMode: progressMode ?? this.progressMode,
        progressValue: progressValue ?? this.progressValue,
        progressTarget: progressTarget ?? this.progressTarget,
        progressUnit: progressUnit ?? this.progressUnit,
        difficultyScore: difficultyScore ?? this.difficultyScore,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'description': description,
        'dueAt': dueAt?.toIso8601String(),
        'reminderAt': reminderAt?.toIso8601String(),
        'scheduledDate': scheduledDate?.toIso8601String(),
        'priority': priority.name,
        'category': category,
        'iconKey': iconKey,
        'colorValue': colorValue,
        'isCompleted': isCompleted,
        'completedAt': completedAt?.toIso8601String(),
        'isPaused': isPaused,
        'repeat': repeat.name,
        'notes': notes,
        'photoPaths': photoPaths,
        'audioPaths': audioPaths,
        'subtasks': subtasks.map((Subtask s) => s.toJson()).toList(),
        'parentTaskId': parentTaskId,
        'isGroup': isGroup,
        'taskType': taskType.name,
        'progressMode': progressMode.name,
        'progressValue': progressValue,
        'progressTarget': progressTarget,
        'progressUnit': progressUnit,
        'difficultyScore': difficultyScore,
        'sortOrder': sortOrder,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  String toJsonString() => jsonEncode(toJson());

  factory Task.fromJson(Map<String, dynamic> json) {
    final DateTime now = DateTime.now();
    List<String> strings(Object? raw) => raw is List ? raw.whereType<String>().toList() : <String>[];
    final Object? rawSubtasks = json['subtasks'];
    final List<Subtask> subtasks = rawSubtasks is List
        ? rawSubtasks.whereType<Map>().map((Map e) => Subtask.fromJson(Map<String, dynamic>.from(e))).toList()
        : <Subtask>[];
    TaskPriority parsePriority(Object? raw) => TaskPriority.values.where((TaskPriority p) => p.name == raw).firstOrNull ?? TaskPriority.medium;
    TaskRepeat parseRepeat(Object? raw) => TaskRepeat.values.where((TaskRepeat r) => r.name == raw).firstOrNull ?? TaskRepeat.none;
    TaskType parseType(Object? raw) => TaskType.values.where((TaskType t) => t.name == raw).firstOrNull ?? TaskType.standard;
    TaskProgressMode parseMode(Object? raw) => TaskProgressMode.values.where((TaskProgressMode m) => m.name == raw).firstOrNull ?? TaskProgressMode.percentage;
    return Task(
      id: json['id'] as String,
      title: (json['title'] as String? ?? '').trim(),
      description: (json['description'] as String?) ?? '',
      dueAt: DateTime.tryParse('${json['dueAt'] ?? ''}'),
      reminderAt: DateTime.tryParse('${json['reminderAt'] ?? ''}'),
      scheduledDate: DateTime.tryParse('${json['scheduledDate'] ?? ''}'),
      priority: parsePriority(json['priority']),
      category: (json['category'] as String?) ?? '',
      iconKey: (json['iconKey'] as String?) ?? 'task',
      colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFFA78BFA,
      isCompleted: json['isCompleted'] == true,
      completedAt: DateTime.tryParse('${json['completedAt'] ?? ''}'),
      isPaused: json['isPaused'] == true,
      repeat: parseRepeat(json['repeat']),
      notes: (json['notes'] as String?) ?? '',
      photoPaths: strings(json['photoPaths']),
      audioPaths: strings(json['audioPaths']),
      subtasks: subtasks,
      parentTaskId: json['parentTaskId'] as String?,
      isGroup: json['isGroup'] == true,
      taskType: parseType(json['taskType']),
      progressMode: parseMode(json['progressMode']),
      progressValue: (json['progressValue'] as num?)?.toDouble() ?? 0,
      progressTarget: (json['progressTarget'] as num?)?.toDouble() ?? 100,
      progressUnit: (json['progressUnit'] as String?) ?? '',
      difficultyScore: (json['difficultyScore'] as num?)?.toDouble() ?? 1.0,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}') ?? now,
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}') ?? now,
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
