import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/providers/usage_stats_providers.dart';
import '../../../core/services/permission_manager.dart';
import '../../shield/shield_access.dart';
import '../brain/assistant_brain.dart';
import '../brain/assistant_models.dart';
import '../brain/exam_guide.dart';
import '../brain/reminders.dart';
import '../brain/study_snapshot.dart';

/// One reminder from Pip: when it goes out and what it says.
@immutable
class PipNudge {
  const PipNudge({
    required this.at,
    required this.title,
    required this.body,
    this.id = PipReminders.eveningId,
    this.staleAfter = const Duration(hours: 3),
  });

  /// Which reminder this is; a new one with the same id replaces it.
  final int id;
  final DateTime at;

  /// How late it may still go out, if the phone was off at [at].
  final Duration staleAfter;

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
    // A timetable with its own reminder already calls the user to study.
    if (s.memory.timetable?.remind ?? false) return null;
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
      body: quoteFor(day),
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

  static Copy quoteFor(DateTime day) => quotes[_dayNumber(day) % quotes.length];

  static int _dayNumber(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
}

/// Every reminder Pip has pending: the evening nudge, the exam countdown
/// and the timetable's daily call, each with its own id.
abstract final class PipReminders {
  static const eveningId = 1;
  static const _examBase = 10;
  static const _timetableBase = 100;

  /// Days before the exam when the countdown speaks.
  static const examMilestones = [30, 14, 7, 3, 1, 0];

  /// How many days of timetable reminders are set ahead. Opening the app
  /// sets them again, so a phone that stays shut stops being called after
  /// a week.
  static const timetableDays = 7;

  /// How long before the first block its reminder goes out.
  static const timetableLead = Duration(minutes: 5);

  static List<PipNudge> all(StudySnapshot s) => [
    ?PipNudgePlanner.next(s),
    ..._exam(s),
    ..._timetable(s),
    ..._dated(s),
  ];

  /// Days before a dated test or exam when Pip reminds, in the evening.
  static const testMilestones = [7, 3, 1];

  /// The reminders the user set by date: a countdown for a test or exam,
  /// one call on the day for anything else.
  static List<PipNudge> _dated(StudySnapshot s) => [
    for (final r in s.memory.reminders) ..._forReminder(r, s.now),
  ];

  static List<PipNudge> _forReminder(StudyReminder r, DateTime now) {
    final base = 1000 + r.id * 10;
    final title = Copy.raw(r.title);
    if (!r.exam) {
      return [
        if (r.at.isAfter(now))
          PipNudge(
            id: base,
            at: r.at,
            title: Copy('Reminder: {0}', [title]),
            body: const Copy('You asked me to remind you. You’ve got this.'),
            staleAfter: const Duration(hours: 2),
          ),
      ];
    }
    // The morning of the test: 7 AM, or an hour before an early start.
    final early = r.at.hour * 60 + r.at.minute < 8 * 60 && r.at.hour > 0;
    final morning = early
        ? r.at.subtract(const Duration(hours: 1))
        : DateTime(r.at.year, r.at.month, r.at.day, 7);
    return [
      for (final (i, days) in testMilestones.indexed)
        if (DateTime(r.at.year, r.at.month, r.at.day - days, 18) case final at
            when at.isAfter(now))
          PipNudge(
            id: base + i,
            at: at,
            title: examCopy(title, days),
            body: PipNudgePlanner.quoteFor(at),
            staleAfter: const Duration(hours: 6),
          ),
      if (morning.isAfter(now))
        PipNudge(
          id: base + 9,
          at: morning,
          title: examCopy(title, 0),
          body: PipNudgePlanner.quoteFor(morning),
          staleAfter: const Duration(hours: 3),
        ),
    ];
  }

  static List<PipNudge> _exam(StudySnapshot s) {
    final exam = examById(s.memory.examId);
    final date = s.memory.examDate;
    if (!s.memory.examReminders || exam == null || date == null) return [];
    final title = AssistantBrain.examTitle(exam);
    return [
      for (final days in examMilestones)
        if (_examAt(date, days) case final at when at.isAfter(s.now))
          PipNudge(
            id: _examBase + days,
            at: at,
            title: examCopy(title, days),
            body: PipNudgePlanner.quoteFor(at),
            staleAfter: const Duration(hours: 6),
          ),
    ];
  }

  /// The morning of the exam, or the evening of a countdown day.
  static DateTime _examAt(DateTime exam, int days) {
    final day = addDays(DateTime(exam.year, exam.month, exam.day), -days);
    return DateTime(day.year, day.month, day.day, days == 0 ? 7 : 18);
  }

  static Copy examCopy(Copy title, int days) => switch (days) {
    0 => Copy('{0} is today. You’ve got this.', [title]),
    1 => Copy('{0} is tomorrow. A calm revision block tonight helps.', [title]),
    _ => Copy('{0} is in {1} days. Come study now.', [title, Count(days)]),
  };

  static List<PipNudge> _timetable(StudySnapshot s) {
    final timetable = s.memory.timetable;
    if (timetable == null || !timetable.remind) return [];
    final today = DateTime(s.now.year, s.now.month, s.now.day);
    final start = timetable.effectiveStart;
    final first = timetable.slots.firstOrNull;
    final names = {for (final t in s.subjects) t.id: t.name};
    final firstName = first == null || first.subjectId.isEmpty
        ? null
        : names[first.subjectId];
    return [
      for (var i = 0; i < timetableDays; i++)
        if (DateTime(
              today.year,
              today.month,
              today.day + i,
              start ~/ 60,
              start % 60,
            ).subtract(timetableLead)
            case final at
            when at.isAfter(s.now) && !(i == 0 && s.todayMinutes > 0))
          PipNudge(
            id: _timetableBase + i,
            at: at,
            title: Copy('Your timetable starts at {0}.', [Clock(start)]),
            body: firstName == null
                ? Copy('{0} of study today. Tap to begin.', [
                    Minutes(timetable.totalMinutes),
                  ])
                : Copy('First up: {0}. {1} of study today.', [
                    Copy.raw(firstName),
                    Minutes(timetable.totalMinutes),
                  ]),
            staleAfter: const Duration(minutes: 45),
          ),
    ];
  }

  /// A reminder that is due now, for Home when the phone does not let Pip
  /// notify: the timetable from 10 minutes before its start to 30 after,
  /// or an exam countdown day. Null once one was shown today.
  static BuddyPrompt? dueOnHome(StudySnapshot s) {
    final today = DateTime(s.now.year, s.now.month, s.now.day);
    final shown = s.memory.homeReminderOn;
    if (shown != null && !shown.isBefore(today)) return null;
    final timetable = s.memory.timetable;
    if (timetable != null && timetable.remind && s.todayMinutes == 0) {
      final minute = s.now.hour * 60 + s.now.minute;
      final start = timetable.effectiveStart;
      if (minute >= start - 10 && minute <= start + 30) {
        return BuddyPrompt(
          Copy('Your timetable starts at {0}.', [Clock(start)]),
          AssistantAction(
            Act.focusNow,
            arg: timetable.slots.firstOrNull?.subjectId,
          ),
        );
      }
    }
    for (final r in s.memory.reminders) {
      final days = r.day.difference(today).inHours ~/ 24;
      if (r.exam && (days == 0 || testMilestones.contains(days))) {
        return BuddyPrompt(
          examCopy(Copy.raw(r.title), days),
          const AssistantAction(Act.timetable),
        );
      }
      if (!r.exam &&
          days == 0 &&
          s.now.isAfter(r.at.subtract(const Duration(minutes: 30)))) {
        return BuddyPrompt(
          Copy('Reminder: {0}', [Copy.raw(r.title)]),
          const AssistantAction(Act.reminders),
        );
      }
    }
    final exam = examById(s.memory.examId);
    final days = s.daysToExam;
    if (s.memory.examReminders &&
        exam != null &&
        days != null &&
        examMilestones.contains(days)) {
      return BuddyPrompt(
        examCopy(AssistantBrain.examTitle(exam), days),
        AssistantAction(Act.plan, arg: 'exam:${exam.id}'),
      );
    }
    return null;
  }
}

/// Hands Pip's reminders to Android, replacing any pending ones.
abstract final class PipNudges {
  static const _channel = MethodChannel('dev.focusforge/pip');

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Schedules every reminder [PipReminders] picks for [read]'s data, in
  /// [strings]' language.
  static Future<void> sync(Reader read, AppStrings strings) async {
    if (!supported) return;
    final reminders = PipReminders.all(StudySnapshot.capture(read));
    try {
      await _channel.invokeMethod<void>('schedule', {
        'items': [
          for (final nudge in reminders)
            {
              'id': nudge.id,
              'at': nudge.at.millisecondsSinceEpoch,
              'title': nudge.title.resolve(strings),
              'body': nudge.body.resolve(strings),
              'stale': nudge.staleAfter.inMilliseconds,
            },
        ],
      });
    } on MissingPluginException {
      // Tests and builds without the native side.
    } on PlatformException catch (error) {
      debugPrint('Pip reminders not scheduled: ${error.code}');
    }
  }

  /// Cancels every pending reminder, as when the account is deleted.
  static Future<void> clear() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('schedule', {'items': const []});
    } on MissingPluginException {
      // Tests and builds without the native side.
    } on PlatformException catch (error) {
      debugPrint('Pip reminders not cleared: ${error.code}');
    }
  }
}

/// Whether the phone lets Pip post notifications, and asking for it.
class PipNotificationAccess {
  const PipNotificationAccess(this._permissions);

  final PermissionManager _permissions;

  /// Shows the system prompt if needed. False where Pip cannot notify, in
  /// which case its reminders show on Home.
  Future<bool> request() => _ask(_permissions.request);

  /// Asks nothing; reads the current answer.
  Future<bool> check() => _ask(_permissions.check);

  Future<bool> _ask(
    Future<PermissionOutcome> Function(AppPermission) ask,
  ) async {
    if (!PipNudges.supported) return false;
    try {
      return await ask(AppPermission.notifications) ==
          PermissionOutcome.granted;
    } catch (_) {
      return false;
    }
  }
}

/// Pip's notification access. Overridden in tests, where the platform never
/// answers.
final pipNotificationAccessProvider = Provider<PipNotificationAccess>(
  (ref) => PipNotificationAccess(ref.watch(shieldPermissionManagerProvider)),
);
