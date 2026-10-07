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

/// A plan the user set by hand.
///
/// Only two numbers are asked for — how long they mean to study, and how long
/// one block runs — and the rest is derived. That is the point: a break length
/// is not something anyone has an opinion about, it is a fraction of the
/// block, and the number of blocks is what the goal divides into. Asking for
/// all five would be asking the user to do arithmetic the app can do, and
/// getting it wrong would mean a plan that quietly misses the goal.
@immutable
class CustomPlan {
  const CustomPlan({required this.goalMinutes, required this.focusMinutes});

  /// The focus time the session is aiming at.
  final int goalMinutes;

  /// How long one focus block runs.
  final int focusMinutes;

  /// Blocks the goal divides into, rounded up: a plan that stops short of the
  /// goal is not the plan that was asked for. The cap keeps a 5-minute block
  /// against an 8-hour goal from becoming a hundred-block marathon.
  int get blocks => (goalMinutes / focusMinutes).ceil().clamp(1, 24);

  /// The break after each block. A fifth of the block is the classic ratio;
  /// the bounds keep a very short block from getting a break too short to
  /// stand up in, and a very long one from getting half an hour.
  int get shortBreak => (focusMinutes / 5).round().clamp(3, 20);

  /// The break at the end of a cycle — roughly three short ones, which is the
  /// ratio every shipped preset uses.
  int get longBreak => (focusMinutes * 0.6).round().clamp(10, 45);

  /// Blocks before a long break. Shorter blocks run in longer sets, so a long
  /// break still lands about every two hours whatever the block length is.
  int get cadence => (90 / focusMinutes).round().clamp(2, 6);

  /// The focus time the plan actually reaches: the goal rounded up to whole
  /// blocks, which is what the user will really have studied.
  int get plannedMinutes => blocks * focusMinutes;

  PomodoroPreset toPreset() => PomodoroPreset(
    name: 'Custom',
    icon: Icons.tune_rounded,
    focus: focusMinutes,
    shortBreak: shortBreak,
    longBreak: longBreak,
    segments: cadence,
  );

  Map<String, dynamic> toJson() => {
    'goalMinutes': goalMinutes,
    'focusMinutes': focusMinutes,
  };

  /// Reads a stored plan, or null when there is nothing usable there.
  ///
  /// Both numbers are required and both are clamped into the range the sliders
  /// offer: a stored plan outside it would open the sheet with its controls
  /// pinned at an end that does not describe it.
  static CustomPlan? fromJson(Map<String, dynamic> j) {
    final goal = _intOr(j['goalMinutes'], 0);
    final focus = _intOr(j['focusMinutes'], 0);
    if (goal <= 0 || focus <= 0) return null;
    return CustomPlan(
      goalMinutes: goal.clamp(minGoal, maxGoal),
      focusMinutes: focus.clamp(minFocus, maxFocus),
    );
  }

  /// The range the sheet's sliders span, named here so the stored value and
  /// the controls can never disagree about it.
  static const int minGoal = 30;
  static const int maxGoal = 8 * 60;
  static const int minFocus = 10;
  static const int maxFocus = 120;
}

/// The focus goal for each day of the week.
///
/// One number for the whole week was the old shape and it is the wrong one for
/// anyone whose days differ: a Sunday with nothing on it and a Monday with
/// school in it are not the same target, and a single number makes the user
/// choose which of the two days to be wrong about. [defaultMinutes] is the
/// number onboarding sets; a weekday only appears in [byWeekday] once it has
/// been given a value of its own, so "the same every day" stays the state that
/// needs no explaining.
@immutable
class DailyGoals {
  const DailyGoals({required this.defaultMinutes, this.byWeekday = const {}});

  final int defaultMinutes;

  /// Keyed by `DateTime.weekday` — Monday (1) through Sunday (7).
  final Map<int, int> byWeekday;

  /// The range the goal editor's sliders span, named here so a stored value
  /// and the control that edits it can never disagree about it.
  static const int minMinutes = 30;
  static const int maxMinutes = 8 * 60;

  int forWeekday(int weekday) => byWeekday[weekday] ?? defaultMinutes;

  /// True once any day carries a target of its own.
  bool get isPerDay => byWeekday.isNotEmpty;

  DailyGoals copyWith({int? defaultMinutes, Map<int, int>? byWeekday}) =>
      DailyGoals(
        defaultMinutes: defaultMinutes ?? this.defaultMinutes,
        byWeekday: byWeekday ?? this.byWeekday,
      );

  /// The overrides as they are written to the store.
  Map<String, dynamic> toJson() => {
    for (final entry in byWeekday.entries) '${entry.key}': entry.value,
  };

  /// Reads stored overrides, dropping anything unreadable.
  ///
  /// Runs inside bootstrap, so a malformed entry degrades to "no override"
  /// rather than aborting the launch, and the range is clamped because a value
  /// outside it would open the editor with its slider pinned at an end that
  /// does not describe the day.
  static Map<int, int> readOverrides(Map<String, dynamic>? stored) {
    if (stored == null) return const {};
    final out = <int, int>{};
    for (final entry in stored.entries) {
      final day = int.tryParse(entry.key);
      final minutes = _intOr(entry.value, 0);
      if (day == null || day < DateTime.monday || day > DateTime.sunday) {
        continue;
      }
      if (minutes <= 0) continue;
      out[day] = minutes.clamp(minMinutes, maxMinutes);
    }
    return out;
  }
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
  const DayBar(this.label, this.hours, {this.isToday = false, this.date});

  final String label;
  final double hours;
  final bool isToday;

  /// The calendar day this bar describes, when it stands for a real one.
  ///
  /// The chart needs it to open the right day's summary, and it is carried
  /// here rather than recomputed from the index so a bar can never describe a
  /// different day than the one it is drawn for.
  final DateTime? date;
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
