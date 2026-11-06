import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/providers/usage_stats_providers.dart';
import '../brain/assistant_models.dart';
import '../brain/exam_guide.dart';
import '../brain/study_snapshot.dart';

/// One reminder from Pip: when it goes out and what it says.
@immutable
class PipNudge {
  const PipNudge({required this.at, required this.title, required this.body});

  final DateTime at;

  /// The reminder itself, about the user's own study.
  final Copy title;

  /// A short line to lift the mood.
  final Copy body;
}

/// Decides Pip's next reminder.
///
/// At most one a day, in the early evening, and only on a day the user has
/// not studied yet: a reminder after a good day would be nagging. The words
/// follow what matters most that day — a near exam, an empty week, a streak.
abstract final class PipNudgePlanner {
  /// When students usually sit down to study after school or coaching.
  static const hour = 19;

  /// Exams further away than this are not counted down.
  static const examWindowDays = 60;

  static const quotes = [
    Copy('Small steps, taken daily, become big leaps.'),
    Copy('You don’t need more time. You need to begin.'),
    Copy('Today’s focus is tomorrow’s confidence.'),
    Copy('Slow progress is still progress.'),
    Copy('The exam rewards the days nobody saw.'),
    Copy('Start where you are. Use the time you have.'),
    Copy('One page today is one less worry tomorrow.'),
    Copy('Discipline is remembering what you want most.'),
  ];

  /// The next reminder from [s], or null when the user turned them off.
  static PipNudge? next(StudySnapshot s) {
    if (s.memory.remindersOff) return null;
    final now = s.now;
    final today = DateTime(now.year, now.month, now.day);
    final studiedToday = s.todayMinutes > 0 || s.timerRunning;
    final tonight = DateTime(today.year, today.month, today.day, hour);
    final fireToday =
        !studiedToday &&
        now.isBefore(tonight.subtract(const Duration(minutes: 10)));
    final day = fireToday ? today : addDays(today, 1);
    return PipNudge(
      at: DateTime(day.year, day.month, day.day, hour),
      title: _title(s, today: today, day: day, fireToday: fireToday),
      body: quotes[_dayNumber(day) % quotes.length],
    );
  }

  static Copy _title(
    StudySnapshot s, {
    required DateTime today,
    required DateTime day,
    required bool fireToday,
  }) {
    final exam = examById(s.memory.examId);
    final date = s.memory.examDate;
    if (exam != null && date != null) {
      final examDay = DateTime(date.year, date.month, date.day);
      final days = (examDay.difference(day).inHours / 24).round();
      if (days == 1) {
        return Copy('{0} is tomorrow. A calm revision block tonight helps.', [
          exam.name,
        ]);
      }
      if (days > 1 && days <= examWindowDays) {
        return Copy('{0} is in {1} days. Come study now.', [
          exam.name,
          Count(days),
        ]);
      }
    }
    final sameWeek = weekStart(day) == weekStart(today);
    if (sameWeek && s.weekMinutes == 0 && day.weekday >= DateTime.wednesday) {
      return const Copy(
        'You haven’t studied this week. One short block tonight gets you going.',
      );
    }
    // A day without study ends the streak at midnight, so tomorrow's
    // reminder only mentions one the user kept alive today.
    final streak = fireToday || s.todayMinutes > 0 ? s.streak : 0;
    if (streak >= 2) {
      return Copy(
        'Keep your {0}-day streak going. One block tonight is enough.',
        [Count(streak)],
      );
    }
    return const Copy('Time for a short study block. I’m ready when you are.');
  }

  static int _dayNumber(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
}

/// Hands Pip's next reminder to Android, or cancels it.
abstract final class PipNudges {
  static const _channel = MethodChannel('dev.focusforge/pip');

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Schedules the reminder [PipNudgePlanner] picks for [read]'s data, in
  /// [strings]' language, replacing any pending one.
  static Future<void> sync(Reader read, AppStrings strings) async {
    if (!supported) return;
    final nudge = PipNudgePlanner.next(StudySnapshot.capture(read));
    try {
      if (nudge == null) {
        await _channel.invokeMethod<void>('cancel');
        return;
      }
      await _channel.invokeMethod<void>('schedule', {
        'at': nudge.at.millisecondsSinceEpoch,
        'title': nudge.title.resolve(strings),
        'body': nudge.body.resolve(strings),
      });
    } on MissingPluginException {
      // Tests and builds without the native side.
    } on PlatformException catch (error) {
      debugPrint('Pip reminder not scheduled: ${error.code}');
    }
  }
}
