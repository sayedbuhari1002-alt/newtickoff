import 'dart:convert';

import 'package:flutter/foundation.dart';

enum TaskPriority { low, medium, high }
enum TaskRepeat { none, daily, weekly, monthly }

@immutable
class Subtask {
  const Subtask({
    required this.id,
    required this.title,
    required this.createdAt,
    this.dueAt,
    this.isCompleted = false,
    this.completedAt,
    this.sortOrder = 0,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime? dueAt;
  final bool isCompleted;
  final DateTime? completedAt;
  final int sortOrder;

  Subtask copyWith({
    String? title,
    DateTime? dueAt,
    bool clearDueAt = false,
    bool? isCompleted,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    int? sortOrder,
  }) => Subtask(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        dueAt: clearDueAt ? null : (dueAt ?? this.dueAt),
        isCompleted: isCompleted ?? this.isCompleted,
        completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
        sortOrder: sortOrder ?? this.sortOrder,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'dueAt': dueAt?.toIso8601String(),
        'isCompleted': isCompleted,
        'completedAt': completedAt?.toIso8601String(),
        'sortOrder': sortOrder,
      };

  factory Subtask.fromJson(Map<String, dynamic> json) {
    final DateTime created = DateTime.tryParse('${json['createdAt'] ?? ''}') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return Subtask(
      id: json['id'] as String,
      title: (json['title'] as String? ?? '').trim(),
      createdAt: created,
      dueAt: DateTime.tryParse('${json['dueAt'] ?? ''}'),
      isCompleted: json['isCompleted'] == true,
      completedAt: DateTime.tryParse('${json['completedAt'] ?? ''}'),
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
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
    this.colorValue = 0xFFFFC857,
    this.isCompleted = false,
    this.completedAt,
    this.isPaused = false,
    this.repeat = TaskRepeat.none,
    this.notes = '',
    this.photoPaths = const <String>[],
    this.audioPaths = const <String>[],
    this.subtasks = const <Subtask>[],
  });

  final String id;
  final String title;
  final String description;
  final DateTime? dueAt;
  final DateTime? reminderAt;
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
  final List<Subtask> subtasks;
  final DateTime createdAt;
  final DateTime updatedAt;

  int get completedSubtasks => subtasks.where((Subtask s) => s.isCompleted).length;
  double get subtaskProgress => subtasks.isEmpty ? (isCompleted ? 1 : 0) : completedSubtasks / subtasks.length;
  bool get hasSubtasks => subtasks.isNotEmpty;
  bool get isOverdue {
    if (isCompleted || isPaused || dueAt == null) return false;
    final DateTime due = DateTime(dueAt!.year, dueAt!.month, dueAt!.day);
    final DateTime today = DateTime.now();
    final DateTime day = DateTime(today.year, today.month, today.day);
    if (due.isBefore(day)) return true;
    final bool hasDueTime = dueAt!.hour != 0 || dueAt!.minute != 0;
    return hasDueTime && due.isAtSameMomentAs(day) && today.isAfter(dueAt!);
  }

  String? validate() {
    if (title.trim().isEmpty) return 'Please enter a task title.';
    if (subtasks.any((Subtask s) => s.title.trim().isEmpty)) return 'Subtask names cannot be empty.';
    return null;
  }

  Task copyWith({
    String? title,
    String? description,
    DateTime? dueAt,
    bool clearDueAt = false,
    DateTime? reminderAt,
    bool clearReminderAt = false,
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
    DateTime? updatedAt,
  }) => Task(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        dueAt: clearDueAt ? null : (dueAt ?? this.dueAt),
        reminderAt: clearReminderAt ? null : (reminderAt ?? this.reminderAt),
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
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'description': description,
        'dueAt': dueAt?.toIso8601String(),
        'reminderAt': reminderAt?.toIso8601String(),
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
    return Task(
      id: json['id'] as String,
      title: (json['title'] as String? ?? '').trim(),
      description: (json['description'] as String?) ?? '',
      dueAt: DateTime.tryParse('${json['dueAt'] ?? ''}'),
      reminderAt: DateTime.tryParse('${json['reminderAt'] ?? ''}'),
      priority: parsePriority(json['priority']),
      category: (json['category'] as String?) ?? '',
      iconKey: (json['iconKey'] as String?) ?? 'task',
      colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFFFFC857,
      isCompleted: json['isCompleted'] == true,
      completedAt: DateTime.tryParse('${json['completedAt'] ?? ''}'),
      isPaused: json['isPaused'] == true,
      repeat: parseRepeat(json['repeat']),
      notes: (json['notes'] as String?) ?? '',
      photoPaths: strings(json['photoPaths']),
      audioPaths: strings(json['audioPaths']),
      subtasks: subtasks,
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}') ?? now,
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}') ?? now,
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
