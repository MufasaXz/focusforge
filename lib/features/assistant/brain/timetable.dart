import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// One focus block on a timetable.
@immutable
class TimetableSlot {
  const TimetableSlot(this.subjectId, this.start, this.minutes);

  /// The subject's id; empty for study not tied to a subject.
  final String subjectId;

  /// Minutes after midnight.
  final int start;
  final int minutes;

  int get end => start + minutes;

  @override
  bool operator ==(Object other) =>
      other is TimetableSlot &&
      other.subjectId == subjectId &&
      other.start == start &&
      other.minutes == minutes;

  @override
  int get hashCode => Object.hash(subjectId, start, minutes);

  @override
  String toString() => 'Slot($subjectId, $start, $minutes)';
}

/// A daily study timetable: how long each subject gets, from what time, in
/// blocks of what length.
///
/// The slots are worked out from those few numbers, so changing a subject's
/// hours or the start time lays the whole day out again. Each subject's
/// blocks run back to back, the way a timetable on paper reads, with a short
/// break after every block.
@immutable
class Timetable {
  Timetable({
    required this.startMinute,
    required this.blockMinutes,
    required this.breakMinutes,
    required Map<String, int> subjectMinutes,
    this.remind = true,
  }) : subjectMinutes = Map.unmodifiable(subjectMinutes);

  /// What one tap on a subject's − or + changes.
  static const step = 30;

  /// The longest day a timetable plans.
  static const maxTotal = 12 * 60;

  /// When the first block begins, in minutes after midnight.
  final int startMinute;
  final int blockMinutes;
  final int breakMinutes;

  /// Minutes per subject id, in the order the day takes them.
  final Map<String, int> subjectMinutes;

  /// Whether Pip reminds the user when the timetable starts each day.
  final bool remind;

  int get totalMinutes => subjectMinutes.values.fold(0, (a, b) => a + b);

  /// Each subject's time cut into even blocks no longer than [blockMinutes].
  List<(String, int)> get _blocks => [
    for (final MapEntry(key: id, value: minutes) in subjectMinutes.entries)
      if (minutes > 0) ..._split(id, minutes),
  ];

  List<(String, int)> _split(String id, int minutes) {
    final count = (minutes / blockMinutes).ceil();
    final even = (minutes / count / 5).round() * 5;
    return [
      for (var i = 0; i < count; i++)
        (id, i == count - 1 ? minutes - even * (count - 1) : even),
    ];
  }

  /// Study and breaks from the first block to the end of the last.
  int get spanMinutes {
    final blocks = _blocks;
    return totalMinutes + breakMinutes * math.max(0, blocks.length - 1);
  }

  /// The start actually used: moved earlier when the day would otherwise
  /// run past midnight.
  int get effectiveStart =>
      math.min(startMinute, math.max(0, 24 * 60 - spanMinutes));

  List<TimetableSlot> get slots {
    final slots = <TimetableSlot>[];
    var at = effectiveStart;
    for (final (id, minutes) in _blocks) {
      slots.add(TimetableSlot(id, at, minutes));
      at += minutes + breakMinutes;
    }
    return slots;
  }

  Timetable copyWith({
    int? startMinute,
    int? blockMinutes,
    int? breakMinutes,
    Map<String, int>? subjectMinutes,
    bool? remind,
  }) => Timetable(
    startMinute: startMinute ?? this.startMinute,
    blockMinutes: blockMinutes ?? this.blockMinutes,
    breakMinutes: breakMinutes ?? this.breakMinutes,
    subjectMinutes: subjectMinutes ?? this.subjectMinutes,
    remind: remind ?? this.remind,
  );

  /// [subjectId]'s time changed by [delta] minutes, within the day's limit.
  /// A subject taken down to nothing leaves the timetable.
  Timetable adjust(String subjectId, int delta) {
    final current = subjectMinutes[subjectId] ?? 0;
    final room = maxTotal - (totalMinutes - current);
    final next = (current + delta).clamp(0, room);
    final minutes = {...subjectMinutes};
    if (next == 0 && minutes.length > 1) {
      minutes.remove(subjectId);
    } else {
      minutes[subjectId] = math.max(next, step);
    }
    return copyWith(subjectMinutes: minutes);
  }

  Map<String, dynamic> toJson() => {
    'start': startMinute,
    'block': blockMinutes,
    'break': breakMinutes,
    'remind': remind,
    'subjects': [
      for (final MapEntry(key: id, value: minutes) in subjectMinutes.entries)
        [id, minutes],
    ],
  };

  /// Reads a stored timetable, or null when it is unusable.
  static Timetable? fromJson(Object? json) {
    if (json is! Map) return null;
    final start = json['start'];
    final block = json['block'];
    final rest = json['break'];
    final subjects = json['subjects'];
    if (start is! int || block is! int || rest is! int || subjects is! List) {
      return null;
    }
    final minutes = <String, int>{};
    for (final entry in subjects) {
      if (entry is List &&
          entry.length == 2 &&
          entry[0] is String &&
          entry[1] is int &&
          (entry[1] as int) > 0) {
        minutes[entry[0] as String] = entry[1] as int;
      }
    }
    if (minutes.isEmpty) return null;
    return Timetable(
      startMinute: start.clamp(0, 24 * 60 - 1),
      blockMinutes: block.clamp(15, 120),
      breakMinutes: rest.clamp(0, 30),
      subjectMinutes: minutes,
      remind: json['remind'] != false,
    );
  }

  /// A timetable for [totalMinutes] a day.
  ///
  /// Subjects the user named keep the time they asked for. The rest of the
  /// day goes to [subjects] in order (the ones falling behind come first),
  /// in half-hour steps, at most four subjects in all. With no subjects at
  /// all, the day is one untagged stretch of study.
  static Timetable plan({
    required int totalMinutes,
    required List<String> subjects,
    Map<String, int> asked = const {},
    required int startMinute,
    int blockMinutes = 50,
    int breakMinutes = 10,
  }) {
    final askedTotal = asked.values.fold(0, (a, b) => a + b);
    final int total = _round(math.max(totalMinutes, askedTotal))
        .clamp(step, maxTotal)
        .toInt();
    final minutes = <String, int>{
      for (final MapEntry(key: id, value: m) in asked.entries)
        if (m > 0) id: _round(m).clamp(step, maxTotal).toInt(),
    };
    int rest = total - minutes.values.fold(0, (a, b) => a + b);
    final others = subjects
        .where((id) => !minutes.containsKey(id))
        .take(math.max(0, 4 - minutes.length))
        .toList();
    if (rest >= step && others.isNotEmpty) {
      final units = rest ~/ step;
      final share = units ~/ others.length;
      final extra = units % others.length;
      for (var i = 0; i < others.length; i++) {
        final m = (share + (i < extra ? 1 : 0)) * step;
        if (m > 0) minutes[others[i]] = m;
      }
      rest = 0;
    }
    // Time the user asked for beyond the subjects there are is study all
    // the same, just not tied to one subject.
    if (rest >= step) minutes[''] = rest;
    return Timetable(
      startMinute: startMinute,
      blockMinutes: blockMinutes.clamp(15, 120),
      breakMinutes: breakMinutes.clamp(0, 30),
      subjectMinutes: minutes,
    );
  }

  static int _round(int minutes) => ((minutes / step).round() * step);

  /// Hours the user typed: a daily total, or hours for named subjects, as in
  /// "6 hours a day", "physics 2 hours, maths 1.5 hrs" or "chem 90 min".
  ///
  /// [names] maps each subject id to its name. A duration in the same part of
  /// the sentence as a subject's name is that subject's; one alone is the
  /// day's total.
  static ({int? total, Map<String, int> asked}) parseHours(
    String said,
    Map<String, String> names,
  ) {
    final text = said.toLowerCase();
    final parts = text.split(RegExp(r'[,;/&\n]|\band\b|\baur\b|\bthen\b'));
    final asked = <String, int>{};
    int? total;
    for (final part in parts) {
      final minutes = _duration(part);
      if (minutes == null) continue;
      final id = _subjectIn(part, names);
      if (id != null) {
        asked[id] = (asked[id] ?? 0) + minutes;
      } else {
        total ??= minutes;
      }
    }
    return (total: total, asked: asked);
  }

  static final _hours = RegExp(
    r'(\d+(?:[.,]\d+)?)\s*(?:h|hr|hrs|hour|hours|ghanta|ghante|ghanton)\b',
  );
  static final _minutes = RegExp(
    r'(\d+)\s*(?:m|min|mins|minute|minutes|minat)\b',
  );

  static int? _duration(String part) {
    var minutes = 0;
    var found = false;
    for (final match in _hours.allMatches(part)) {
      final value = double.tryParse(match.group(1)!.replaceAll(',', '.'));
      if (value == null) continue;
      minutes += (value * 60).round();
      found = true;
    }
    for (final match in _minutes.allMatches(part)) {
      minutes += int.parse(match.group(1)!);
      found = true;
    }
    return found && minutes > 0 ? minutes : null;
  }

  static String? _subjectIn(String part, Map<String, String> names) {
    final words = part.split(RegExp(r'[^\p{L}\p{N}]+', unicode: true));
    String? best;
    var bestLength = 0;
    for (final MapEntry(key: id, value: name) in names.entries) {
      final lower = name.toLowerCase().trim();
      if (lower.isEmpty) continue;
      // The whole name, or a word of it at least four letters long that the
      // user typed the start of: "chem" for Chemistry, "bio" for Biology.
      final hit =
          part.contains(lower) ||
          words.any(
            (w) =>
                w.length >= 3 &&
                lower
                    .split(RegExp(r'\s+'))
                    .any((n) => n.length >= 4 && n.startsWith(w)),
          );
      if (hit && lower.length > bestLength) {
        best = id;
        bestLength = lower.length;
      }
    }
    return best;
  }
}
