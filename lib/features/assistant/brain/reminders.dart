import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Something the user asked Pip to remind them of: a test, an exam, or any
/// task on a day.
@immutable
class StudyReminder {
  const StudyReminder({
    required this.id,
    required this.title,
    required this.at,
    this.exam = false,
  });

  /// Unique among the user's reminders, so its notifications keep their ids.
  final int id;

  /// What it is about, as the user put it: "Physics exam", "Revise chemistry".
  final String title;

  /// When it is: the day, and the time if the user gave one.
  final DateTime at;

  /// A test or exam gets a countdown; anything else one reminder on the day.
  final bool exam;

  DateTime get day => DateTime(at.year, at.month, at.day);

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'at': at.toIso8601String(),
    'exam': exam,
  };

  static StudyReminder? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final title = json['title'];
    final at = json['at'] is String ? DateTime.tryParse(json['at']) : null;
    if (id is! int || title is! String || title.trim().isEmpty || at == null) {
      return null;
    }
    return StudyReminder(
      id: id,
      title: title,
      at: at,
      exam: json['exam'] == true,
    );
  }
}

/// What a typed reminder asks for: what, and when if the user said.
@immutable
class ReminderRequest {
  const ReminderRequest({
    required this.title,
    required this.exam,
    this.at,
    this.time,
  });

  final String title;
  final bool exam;

  /// The day and time asked for, or null when no date was given.
  final DateTime? at;

  /// The hour and minute the user named, kept even when no date came with
  /// it, so the day picked afterwards still gets this time.
  final (int, int)? time;

  /// Whether the user named a time, rather than Pip picking the evening.
  bool get hasTime => time != null;

  /// Reads [said] as of [now]: "set reminder for nov 25, it's my physics
  /// exam", "remind me to revise chemistry on friday at 6pm", "kal test hai
  /// yaad dilana".
  static ReminderRequest parse(String said, DateTime now) {
    final text = ' ${_clean(said)} ';
    final today = DateTime(now.year, now.month, now.day);
    final used = <String>{};

    final day = _day(text, today, used);
    final time = _time(text, used);
    DateTime? at;
    if (day != null) {
      final (hour, minute) = time ?? (18, 0);
      at = DateTime(day.year, day.month, day.day, hour, minute);
    }

    final words = text
        .trim()
        .split(' ')
        .where(
          (w) =>
              w.isNotEmpty &&
              !used.contains(w) &&
              !_filler.contains(w) &&
              !RegExp(r'^\d+$').hasMatch(w),
        )
        .toList();
    final exam = words.any(_examWords.contains);
    final title = words.isEmpty
        ? ''
        : '${words.first[0].toUpperCase()}${words.first.substring(1)}'
              '${words.length > 1 ? ' ${words.skip(1).join(' ')}' : ''}';
    return ReminderRequest(title: title, exam: exam, at: at, time: time);
  }

  static String _clean(String said) => said
      .toLowerCase()
      .replaceAll(RegExp(r'[’‘`]'), "'")
      .replaceAll(RegExp(r"'s\b"), '')
      .replaceAll("'", '')
      .replaceAll(RegExp(r'[^\p{L}\p{N}:/\-\s]', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static const _months = [
    'january',
    'february',
    'march',
    'april',
    'may',
    'june',
    'july',
    'august',
    'september',
    'october',
    'november',
    'december',
  ];

  /// A month from a word: its name or first three letters, or one slip of
  /// a key from them ("bov" for "nov").
  static int? _month(String word) {
    if (word.length < 3) return null;
    for (var i = 0; i < 12; i++) {
      final name = _months[i];
      if (word == name || word == name.substring(0, 3)) return i + 1;
      if (word == 'sept' && i == 8) return 9;
    }
    if (word.length == 3 && !_notMonths.contains(word)) {
      for (var i = 0; i < 12; i++) {
        final short = _months[i].substring(0, 3);
        var diff = 0;
        for (var j = 0; j < 3; j++) {
          if (word[j] != short[j]) diff++;
        }
        // Only the first letter may slip, so "mar" and "may" stay apart.
        if (diff == 1 && word.substring(1) == short.substring(1)) return i + 1;
      }
    }
    return null;
  }

  /// Everyday words one letter off a month, never read as one.
  static const _notMonths = {
    'can', 'man', 'pan', 'ban', 'fan', 'tan', 'van', 'ran', //
    'day', 'way', 'say', 'pay', 'bay', 'ray', 'lay', //
    'fun', 'run', 'gun', 'bun', 'act', 'gov',
  };

  static const _weekdays = {
    'monday': 1,
    'mon': 1,
    'tuesday': 2,
    'tue': 2,
    'tues': 2,
    'wednesday': 3,
    'wed': 3,
    'thursday': 4,
    'thu': 4,
    'thurs': 4,
    'friday': 5,
    'fri': 5,
    'saturday': 6,
    'sat': 6,
    'sunday': 7,
    'sun': 7,
  };

  static DateTime? _day(String text, DateTime today, Set<String> used) {
    final words = text.trim().split(' ');

    // "25 nov", "25th of november", "nov 25", "november 25th".
    for (var i = 0; i < words.length; i++) {
      final month = _month(words[i]);
      if (month == null) continue;
      int? dayOf(String? w) {
        final m = RegExp(r'^(\d{1,2})(st|nd|rd|th)?$').firstMatch(w ?? '');
        return m == null ? null : int.parse(m.group(1)!);
      }

      final before = i > 0 ? words[i - 1] : null;
      final beforeOf = i > 1 && before == 'of' ? words[i - 2] : null;
      final after = i + 1 < words.length ? words[i + 1] : null;
      final number = dayOf(after) ?? dayOf(before) ?? dayOf(beforeOf);
      if (number == null) continue;
      used.addAll([words[i], ?after, ?before, ?beforeOf]);
      used.remove('of');
      return _future(today, month, number);
    }

    // "25/11", "25-11-2026": day first, as dates are written in India.
    final numeric = RegExp(r'\b(\d{1,2})[/\-](\d{1,2})(?:[/\-](\d{2,4}))?\b')
        .firstMatch(text);
    if (numeric != null) {
      final d = int.parse(numeric.group(1)!);
      final m = int.parse(numeric.group(2)!);
      if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
        used.add(numeric.group(0)!);
        final y = numeric.group(3);
        if (y != null) {
          final year = int.parse(y) < 100 ? 2000 + int.parse(y) : int.parse(y);
          return DateTime(year, m, d);
        }
        return _future(today, m, d);
      }
    }

    final inDays = RegExp(
      r'\b(?:in|after) (\d{1,3}) days?\b|\b(\d{1,3}) (?:din|days?) (?:baad|bad|mein|me|later)\b',
    ).firstMatch(text);
    if (inDays != null) {
      used.addAll(inDays.group(0)!.split(' '));
      final n = int.parse(inDays.group(1) ?? inDays.group(2)!);
      return DateTime(today.year, today.month, today.day + n);
    }
    if (text.contains(' day after tomorrow ') || text.contains(' parso ')) {
      used.addAll(['day', 'after', 'tomorrow', 'parso']);
      return DateTime(today.year, today.month, today.day + 2);
    }
    for (final word in const ['tomorrow', 'tmrw', 'tmr', 'kal']) {
      if (text.contains(' $word ')) {
        used.add(word);
        return DateTime(today.year, today.month, today.day + 1);
      }
    }
    for (final word in const ['today', 'tonight', 'aaj']) {
      if (text.contains(' $word ')) {
        used.add(word);
        return today;
      }
    }
    if (text.contains(' next week ')) {
      used.addAll(['next', 'week']);
      return DateTime(today.year, today.month, today.day + 7);
    }
    for (final MapEntry(key: name, value: weekday) in _weekdays.entries) {
      if (!text.contains(' $name ')) continue;
      used.addAll([name, 'next', 'this', 'coming']);
      final ahead = (weekday - today.weekday + 7) % 7;
      return DateTime(
        today.year,
        today.month,
        today.day + (ahead == 0 ? 7 : ahead),
      );
    }
    return null;
  }

  /// [month]/[day] this year, or next year once this year's has passed.
  static DateTime? _future(DateTime today, int month, int day) {
    if (day < 1 || day > 31) return null;
    var date = DateTime(today.year, month, day);
    if (date.month != month) return null;
    if (date.isBefore(today)) date = DateTime(today.year + 1, month, day);
    return date;
  }

  static (int, int)? _time(String text, Set<String> used) {
    final clock = RegExp(
      r'\b(?:at )?(\d{1,2})(?::(\d{2}))? ?(am|pm|baje)\b|\bat (\d{1,2})(?::(\d{2}))?\b|\b(\d{1,2}):(\d{2})\b',
    ).firstMatch(text);
    if (clock != null) {
      final hourText = clock.group(1) ?? clock.group(4) ?? clock.group(6)!;
      final minuteText = clock.group(2) ?? clock.group(5) ?? clock.group(7);
      final suffix = clock.group(3);
      var hour = int.parse(hourText);
      final minute = minuteText == null ? 0 : int.parse(minuteText);
      if (hour <= 23 && minute <= 59) {
        if (suffix == 'pm' && hour < 12) hour += 12;
        if (suffix == 'am' && hour == 12) hour = 0;
        // "at 6" with no am or pm: a study reminder at 6 is the evening.
        if (suffix != 'am' && suffix != 'pm' && hour >= 1 && hour <= 7) {
          hour += 12;
        }
        used.addAll(clock.group(0)!.split(' '));
        return (hour, minute);
      }
    }
    const parts = {
      'morning': (8, 0),
      'subah': (8, 0),
      'afternoon': (14, 0),
      'dopahar': (14, 0),
      'evening': (18, 0),
      'shaam': (18, 0),
      'sham': (18, 0),
      'night': (20, 0),
      'raat': (20, 0),
    };
    for (final MapEntry(key: word, value: time) in parts.entries) {
      if (text.contains(' $word ')) {
        used.add(word);
        return time;
      }
    }
    return null;
  }

  static const _examWords = {
    'exam',
    'exams',
    'test',
    'tests',
    'paper',
    'quiz',
    'olympiad',
    'boards',
    'pariksha',
    'viva',
    'practical',
    'unit',
  };

  /// Words that frame the request rather than name what it is about.
  static const _filler = {
    'set',
    'add',
    'create',
    'make',
    'a',
    'an',
    'the',
    'me',
    'to',
    'for',
    'on',
    'at',
    'about',
    'my',
    'mine',
    'it',
    'its',
    'is',
    'i',
    'have',
    'has',
    'got',
    'there',
    'will',
    'be',
    'of',
    'that',
    'this',
    'coming',
    'next',
    'please',
    'pls',
    'plz',
    'remind',
    'reminder',
    'reminders',
    'notify',
    'alert',
    'yaad',
    'dilana',
    'dila',
    'dena',
    'do',
    'kar',
    'karna',
    'hai',
    'h',
    'mera',
    'meri',
    'mere',
    'ka',
    'ki',
    'ko',
    'se',
    'pe',
    'par',
    'date',
    'day',
    'and',
  };

  /// The next free id after [taken].
  static int nextId(Iterable<StudyReminder> taken) =>
      taken.fold(0, (top, r) => math.max(top, r.id)) + 1;
}
