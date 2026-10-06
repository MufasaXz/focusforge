import 'package:flutter/material.dart';

import 'icon_registry.dart';

/// A study subject with its weekly target and accumulated time.
@immutable
class Subject {
  const Subject({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    this.minutesToday = 0,
    this.weekDone = 0,
    this.weekTarget = 0,
  });

  final String id;
  final String name;
  final IconData icon;
  final Color color;
  final int minutesToday;
  final double weekDone;
  final double weekTarget;

  /// Legacy alias — the pre-provider model called this `minutes`.
  int get minutes => minutesToday;

  double get weekProgress =>
      weekTarget <= 0 ? 0 : (weekDone / weekTarget).clamp(0.0, 1.0);

  bool get metTarget => weekTarget > 0 && weekDone >= weekTarget;

  Subject copyWith({
    String? id,
    String? name,
    IconData? icon,
    Color? color,
    int? minutesToday,
    double? weekDone,
    double? weekTarget,
  }) => Subject(
    id: id ?? this.id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    color: color ?? this.color,
    minutesToday: minutesToday ?? this.minutesToday,
    weekDone: weekDone ?? this.weekDone,
    weekTarget: weekTarget ?? this.weekTarget,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': AppIcons.nameOfOr(icon, 'book'),
    'color': color.toARGB32(),
    'minutesToday': minutesToday,
    'weekDone': weekDone,
    'weekTarget': weekTarget,
  };

  /// Every field falls back rather than throwing.
  ///
  /// This runs inside bootstrap, before the first frame, so an unguarded cast
  /// on a single malformed entry would abort the whole launch. The counters in
  /// the stored JSON are inert either way: `SubjectsNotifier` derives them from
  /// the session log, so a stale stored value can never leak onto a screen.
  factory Subject.fromJson(Map<String, dynamic> j) => Subject(
    id: _stringOr(j['id'], ''),
    name: _stringOr(j['name'], 'Subject'),
    icon: AppIcons.resolve(_stringOrNull(j['icon'])),
    color: _colorOr(j['color']),
    minutesToday: _intOr(j['minutesToday'], 0),
    weekDone: _doubleOr(j['weekDone'], 0),
    weekTarget: _doubleOr(j['weekTarget'], 0),
  );
}

/// One completed (or abandoned) focus block.
@immutable
class FocusSession {
  const FocusSession({
    required this.id,
    required this.subjectId,
    required this.startedAt,
    required this.minutes,
    this.completed = true,
    this.label = '',
  });

  final String id;
  final String subjectId;
  final DateTime startedAt;
  final int minutes;
  final bool completed;
  final String label;

  Map<String, dynamic> toJson() => {
    'id': id,
    'subjectId': subjectId,
    'startedAt': startedAt.millisecondsSinceEpoch,
    'minutes': minutes,
    'completed': completed,
    'label': label,
  };

  /// Every field falls back rather than throwing — see [Subject.fromJson].
  factory FocusSession.fromJson(Map<String, dynamic> j) {
    // A missing timestamp falls back to the epoch, not to "now": a corrupt
    // entry must not silently inflate today's totals or this week's heatmap.
    final startedAt = _dateOr(j['startedAt'], _epoch);
    return FocusSession(
      id: _stringOr(j['id'], 's-${startedAt.microsecondsSinceEpoch}'),
      subjectId: _stringOr(j['subjectId'], ''),
      startedAt: startedAt,
      minutes: _intOr(j['minutes'], 0),
      // Entries written before the field existed were all completed, so
      // `true` is the compatible default.
      completed: j['completed'] is bool ? j['completed'] as bool : true,
      label: _stringOr(j['label'], ''),
    );
  }
}

/// A named Pomodoro configuration.
@immutable
class PomodoroPreset {
  const PomodoroPreset({
    required this.name,
    required this.icon,
    required this.focus,
    required this.shortBreak,
    required this.longBreak,
    required this.segments,
  });

  final String name;
  final IconData icon;

  /// Minutes.
  final int focus;
  final int shortBreak;
  final int longBreak;

  /// Focus blocks before a long break.
  final int segments;

  Duration get focusDuration => Duration(minutes: focus);
  Duration get shortBreakDuration => Duration(minutes: shortBreak);
  Duration get longBreakDuration => Duration(minutes: longBreak);
}

/// A bundled looping ambience. [asset] is the path inside `assets/audio`.
@immutable
class AmbientSound {
  const AmbientSound({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.asset,
  });

  final String id;
  final String name;
  final IconData icon;
  final Color color;
  final String asset;
}

/// One day in the weekly bar chart.
@immutable
class DayBar {
  const DayBar(this.label, this.hours, {this.isToday = false});

  final String label;
  final double hours;
  final bool isToday;
}

// -- Persisted-JSON readers --------------------------------------------------
//
// The stored log is decoded during bootstrap, before the first frame, so a
// single unguarded cast used to take the whole launch down. These read one
// field without ever throwing, defaulting to a value that cannot be mistaken
// for real data.
//
// `jsonDecode('1e999')` yields infinity rather than throwing, and `toInt`
// throws on a non-finite double, so finiteness is part of "readable".

/// Stand-in for an entry with no readable timestamp.
final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

/// Colour for a subject whose stored ARGB int is missing or malformed.
const Color _unknownSubjectColor = Color(0xFFB0BEC5);

int _intOr(Object? value, int fallback) =>
    value is num && value.isFinite ? value.toInt() : fallback;

double _doubleOr(Object? value, double fallback) =>
    value is num ? value.toDouble() : fallback;

String _stringOr(Object? value, String fallback) =>
    value is String ? value : fallback;

String? _stringOrNull(Object? value) => value is String ? value : null;

Color _colorOr(Object? value) => value is num && value.isFinite
    ? Color(value.toInt())
    : _unknownSubjectColor;

DateTime _dateOr(Object? value, DateTime fallback) {
  if (value is! num || !value.isFinite) return fallback;
  try {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  } on ArgumentError {
    // Outside the range DateTime can represent — treat it as unknown.
    return fallback;
  }
}
