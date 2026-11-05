import 'package:flutter/foundation.dart';

/// A note, optionally linked to a habit, with local photo, audio and video
/// attachment paths stored in the app's private documents directory.
@immutable
class Note {
  const Note({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.habitId,
    this.logDate,
    this.title = '',
    this.body = '',
    this.photoPaths = const <String>[],
    this.audioPaths = const <String>[],
    this.videoPaths = const <String>[],
  });

  final String id;
  final String? habitId;

  /// Calendar date for a daily journal entry. Habit notes may leave this null.
  final DateTime? logDate;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> photoPaths;
  final List<String> audioPaths;
  final List<String> videoPaths;

  /// A note with no text and no attachments is not worth saving.
  bool get isEmpty =>
      title.trim().isEmpty &&
      body.trim().isEmpty &&
      photoPaths.isEmpty &&
      audioPaths.isEmpty &&
      videoPaths.isEmpty;

  Note copyWith({
    String? habitId,
    bool clearHabit = false,
    DateTime? logDate,
    bool clearLogDate = false,
    String? title,
    String? body,
    DateTime? updatedAt,
    List<String>? photoPaths,
    List<String>? audioPaths,
    List<String>? videoPaths,
  }) {
    return Note(
      id: id,
      habitId: clearHabit ? null : (habitId ?? this.habitId),
      logDate: clearLogDate
          ? null
          : (logDate == null
              ? this.logDate
              : DateTime(logDate.year, logDate.month, logDate.day)),
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      photoPaths: photoPaths ?? this.photoPaths,
      audioPaths: audioPaths ?? this.audioPaths,
      videoPaths: videoPaths ?? this.videoPaths,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'habitId': habitId,
        'logDate': logDate?.toIso8601String(),
        'title': title,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'photoPaths': photoPaths,
        'audioPaths': audioPaths,
        'videoPaths': videoPaths,
      };

  factory Note.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? raw) =>
        raw is List ? raw.whereType<String>().toList() : const <String>[];
    final DateTime epoch = DateTime.fromMillisecondsSinceEpoch(0);
    final DateTime created =
        DateTime.tryParse((json['createdAt'] as String?) ?? '') ?? epoch;
    return Note(
      id: json['id'] as String,
      habitId: json['habitId'] as String?,
      logDate: DateTime.tryParse((json['logDate'] as String?) ?? ''),
      title: (json['title'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      createdAt: created,
      updatedAt:
          DateTime.tryParse((json['updatedAt'] as String?) ?? '') ?? created,
      photoPaths: strings(json['photoPaths']),
      audioPaths: strings(json['audioPaths']),
      videoPaths: strings(json['videoPaths']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Note &&
      other.id == id &&
      other.habitId == habitId &&
      other.logDate == logDate &&
      other.title == title &&
      other.body == body &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      listEquals(other.photoPaths, photoPaths) &&
      listEquals(other.audioPaths, audioPaths) &&
      listEquals(other.videoPaths, videoPaths);

  @override
  int get hashCode => Object.hash(
        id,
        habitId,
        logDate,
        title,
        body,
        createdAt,
        updatedAt,
        Object.hashAll(photoPaths),
        Object.hashAll(audioPaths),
        Object.hashAll(videoPaths),
      );
}
