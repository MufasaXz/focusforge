import 'dart:math' as math;

import 'assistant_models.dart';
import 'offline_text.dart';
import 'study_snapshot.dart';

class OfflinePlanSlot {
  const OfflinePlanSlot(this.minutes, {this.subject});
  final int minutes;
  final SubjectTrend? subject;
}

class OfflineStudyPlan {
  const OfflineStudyPlan({
    required this.minutes,
    required this.slots,
    required this.focusMinutes,
    required this.breakMinutes,
    required this.requestedMinutes,
  });
  final int minutes;
  final int requestedMinutes;
  final int focusMinutes;
  final int breakMinutes;

  /// Even indices are study, odd indices breaks. All lengths are positive,
  /// and their sum equals [minutes], including a short final break if needed.
  final List<OfflinePlanSlot> slots;
  int get blocks => (slots.length + 1) ~/ 2;
  int get studyMinutes => slots.indexed
      .where((e) => e.$1.isEven)
      .fold(0, (sum, e) => sum + e.$2.minutes);
}

abstract final class OfflinePlanner {
  static bool recognizes(String input) {
    final text = OfflineText.normalize(input);
    if (OfflineText.any(text, const [
      'remind',
      'reminder',
      'reminders',
      'notify',
      'cancel',
      'delete',
    ])) {
      return false;
    }
    if (OfflineText.has(text, 'pomodoro')) return true;
    if (budget(input) == null) return false;
    // Exam/timetable cards already have editable, persistent plans. A stated
    // available-time budget is distinct from those daily target requests.
    if (OfflineText.any(text, const ['exam', 'test']) &&
        !OfflineText.any(text, const ['i have', 'only have', 'available'])) {
      return false;
    }
    return OfflineText.any(text, const [
          'pomodoro',
          'only have',
          'i have',
          'minutes free',
          'hour free',
          'hours free',
          'minute plan',
          'min plan',
          'time budget',
          'mere paas',
          'मेरे पास',
        ]) ||
        (RegExp(r'\d').hasMatch(text) &&
            OfflineText.any(text, const [
              'plan',
              'fit',
              'available',
              'study between',
            ]));
  }

  static List<SubjectTrend> ranked(StudySnapshot s, String input) {
    final text = OfflineText.normalize(input);
    final ranked = [...s.subjects]
      ..sort((a, b) {
        double need(SubjectTrend t) =>
            math.max(0, t.weekTarget - t.thisWeek) * 2 +
            math.max(0, t.lastWeekSpan - t.thisWeek) -
            t.today * 0.5;
        final comparison = need(b).compareTo(need(a));
        return comparison != 0 ? comparison : a.name.compareTo(b.name);
      });
    final named = ranked.where((s) => namesSubject(text, s.name)).toList();
    // If the user lists subjects, honour that list rather than silently adding
    // another subject. Saved weekly deficits are priorities, not ability scores.
    return named.isEmpty ? ranked : named;
  }

  static bool namesSubject(String text, String name) {
    final lower = OfflineText.normalize(name);
    if (lower.isEmpty) return false;
    if (OfflineText.has(text, lower)) return true;
    return text
        .split(' ')
        .any(
          (w) =>
              w.length >= 3 &&
              lower
                  .split(' ')
                  .any((part) => part.length >= 4 && part.startsWith(w)),
        );
  }

  static String _numberWords(String input) {
    var text = input.toLowerCase();
    const replacements = {
      'one and a half hours': '1.5 hours',
      'an hour and a half': '1.5 hours',
      'a quarter of an hour': '15 minutes',
      'quarter hour': '15 minutes',
      'half an hour': '30 minutes',
      'half hour': '30 minutes',
      'an hour': '1 hour',
      'forty five': '45',
      'twenty five': '25',
      'ninety': '90',
      'sixty': '60',
      'forty': '40',
      'thirty': '30',
      'twenty': '20',
      'fifteen': '15',
      'twelve': '12',
      'eleven': '11',
      'ten': '10',
      'nine': '9',
      'eight': '8',
      'seven': '7',
      'six': '6',
      'five': '5',
      'four': '4',
      'three': '3',
      'two': '2',
      'one': '1',
      'ek': '1',
      'do': '2',
      'teen': '3',
      'aadha ghanta': '30 minutes',
    };
    for (final entry in replacements.entries) {
      text = text.replaceAll(RegExp('\\b${entry.key}\\b'), entry.value);
    }
    const digits = '०१२३४५६७८९';
    for (var i = 0; i < digits.length; i++) {
      text = text.replaceAll(digits[i], '$i');
    }
    return text;
  }

  static final _duration = RegExp(
    r'(-?\d+(?:\.\d+)?)\s*(hours?|hrs?|h|ghante?|घंटे|घंटा|minutes?|mins?|m|minat|मिनट)(?=\s|[,.;!?]|$)',
    unicode: true,
  );

  /// Combines compound durations, retaining decimal hours. A stated break or
  /// focus-block length is an option, not extra available time.
  static int? budget(String input) {
    final text = _numberWords(input);
    final window = RegExp(
      r'\bfrom\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)\s+to\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b',
    ).firstMatch(text);
    if (window != null) {
      int? clock(String h, String? m, String meridian) {
        final hour = int.parse(h);
        final minute = int.parse(m ?? '0');
        if (hour < 1 || hour > 12 || minute > 59) return null;
        return hour % 12 * 60 + (meridian == 'pm' ? 720 : 0) + minute;
      }

      final start = clock(window[1]!, window[2], window[3]!);
      final end = clock(window[4]!, window[5], window[6]!);
      if (start == null || end == null) return -1;
      return end >= start ? end - start : end + 1440 - start;
    }
    var found = false;
    var total = 0.0;
    for (final m in _duration.allMatches(text)) {
      final before = text.substring(math.max(0, m.start - 12), m.start);
      final after = text.substring(m.end).trimLeft();
      if (RegExp(
            r'^(?:long\s+)?(?:breaks?|rests?|pauses?|blocks?|focus blocks?)\b',
          ).hasMatch(after) ||
          RegExp(r'(?:break|rest|block)\s*(?:of|=|:)??\s*$').hasMatch(before)) {
        continue;
      }
      final number = double.tryParse(m[1]!);
      if (number == null || !number.isFinite || number.abs() > 10000) return -1;
      if (number < 0) return -1;
      final hour = RegExp(r'^(h|gh|घ)').hasMatch(m[2]!);
      total += number * (hour ? 60 : 1);
      found = true;
    }
    return found ? total.round() : null;
  }

  static OfflineStudyPlan build(StudySnapshot s, String input, {int? minutes}) {
    final requested =
        minutes ??
        budget(input) ??
        (s.remainingToGoal > 0 ? s.remainingToGoal : 60);
    final total = requested.clamp(0, 480);
    final text = _numberWords(input);
    var focus = s.blockMinutes.clamp(5, 50);
    var rest = s.breakMinutes.clamp(1, 15);
    final split = RegExp(
      r'\b(\d{1,2})\s*/\s*(\d{1,2})\s*(?:pomodoro|blocks?|split)?',
    ).firstMatch(text);
    if (split != null) {
      focus = int.parse(split[1]!).clamp(5, 50);
      rest = int.parse(split[2]!).clamp(1, 15);
    }
    for (final m in _duration.allMatches(text)) {
      final after = text.substring(m.end).trimLeft();
      final n = double.tryParse(m[1]!);
      if (n == null || !n.isFinite || n <= 0 || n > 1000) continue;
      final value = (n * (RegExp(r'^(h|gh|घ)').hasMatch(m[2]!) ? 60 : 1))
          .round();
      if (RegExp(r'^(break|rest|pause)').hasMatch(after)) {
        rest = value.clamp(1, 15);
      }
      if (RegExp(r'^(?:focus )?block').hasMatch(after)) {
        focus = value.clamp(5, 50);
      }
    }
    if (OfflineText.any(OfflineText.normalize(input), const [
      'tired',
      'exhausted',
      'low energy',
      'overwhelmed',
    ])) {
      focus = math.min(focus, 15);
    }
    final subjects = ranked(s, input).take(4).toList();
    final slots = <OfflinePlanSlot>[];
    var remaining = total;
    var index = 0;
    while (remaining > 0) {
      final duration = math.min(focus, remaining);
      final subject = subjects.isEmpty
          ? null
          : subjects[index % subjects.length];
      slots.add(OfflinePlanSlot(duration, subject: subject));
      remaining -= duration;
      index++;
      if (remaining > 0) {
        final duration = math.min(rest, remaining);
        slots.add(OfflinePlanSlot(duration));
        remaining -= duration;
      }
    }
    return OfflineStudyPlan(
      minutes: total,
      requestedMinutes: requested,
      slots: List.unmodifiable(slots),
      focusMinutes: focus,
      breakMinutes: rest,
    );
  }
}
