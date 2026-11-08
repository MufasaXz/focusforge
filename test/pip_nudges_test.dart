// Pip's evening reminder.
//
// WHAT INVARIANT: at most one reminder is pending; it goes out at 19:00 on a
// day the user has not studied yet (today if there is still time, else
// tomorrow); it counts down a near exam, names an empty week or a streak the
// user kept alive, and always carries a short motivating line; turning
// reminders off schedules nothing.
//
// WHY IT MATTERS: a reminder after a day of study, or about a streak that
// already broke, teaches users to switch notifications off.

import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:focusforge/core/localization/app_strings.dart';
import 'package:focusforge/core/models/social.dart';
import 'package:focusforge/features/assistant/assistant_memory.dart';
import 'package:focusforge/features/assistant/brain/reminders.dart';
import 'package:focusforge/features/assistant/brain/timetable.dart';
import 'package:focusforge/features/assistant/brain/study_snapshot.dart';
import 'package:focusforge/features/assistant/nudges/pip_nudges.dart';

void main() {
  final strings = AppStrings(const Locale('en'));
  // Thursday 6 November 2026.
  DateTime at(int hour, [int day = 6]) => DateTime(2026, 11, day, hour);

  String title(StudySnapshot s) =>
      PipNudgePlanner.next(s)!.title.resolve(strings);

  test('a day without study gets a reminder at 19:00 the same day', () {
    final nudge = PipNudgePlanner.next(
      StudySnapshot(now: at(10), weekMinutes: 90),
    )!;
    expect(nudge.at, at(19));
    expect(
      nudge.title.resolve(strings),
      'Time for a short study block. I’m ready when you are.',
    );
    expect(PipNudgePlanner.quotes.contains(nudge.body), isTrue);
  });

  test('a day already studied, or one too late, waits for tomorrow', () {
    expect(
      PipNudgePlanner.next(StudySnapshot(now: at(10), todayMinutes: 25))!.at,
      at(19, 7),
    );
    expect(
      PipNudgePlanner.next(StudySnapshot(now: at(10), timerRunning: true))!.at,
      at(19, 7),
    );
    expect(PipNudgePlanner.next(StudySnapshot(now: at(20)))!.at, at(19, 7));
  });

  test('a near exam is counted down from the reminder’s day', () {
    final memory = AssistantMemory(
      examId: 'neet-ug',
      examDate: DateTime(2026, 12, 1),
    );
    expect(
      title(StudySnapshot(now: at(10), memory: memory)),
      'NEET-UG is in 25 days. Come study now.',
    );
    expect(
      title(StudySnapshot(now: at(10), todayMinutes: 30, memory: memory)),
      'NEET-UG is in 24 days. Come study now.',
    );
    final tomorrow = AssistantMemory(
      examId: 'neet-ug',
      examDate: DateTime(2026, 11, 7),
    );
    expect(
      title(StudySnapshot(now: at(10), memory: tomorrow)),
      'NEET-UG is tomorrow. A calm revision block tonight helps.',
    );
    final far = AssistantMemory(
      examId: 'neet-ug',
      examDate: DateTime(2027, 5, 2),
    );
    expect(
      title(StudySnapshot(now: at(10), weekMinutes: 30, memory: far)),
      isNot(contains('NEET-UG')),
    );
  });

  test('an empty week is named from Wednesday on', () {
    expect(
      title(StudySnapshot(now: at(10))),
      'You haven’t studied this week. One short block tonight gets you going.',
    );
    // Monday: the week has barely begun.
    expect(
      title(StudySnapshot(now: at(10, 2))),
      'Time for a short study block. I’m ready when you are.',
    );
  });

  test('only a streak still alive is mentioned', () {
    expect(
      title(StudySnapshot(now: at(10), weekMinutes: 60, streak: 4)),
      'Keep your 4-day streak going. One block tonight is enough.',
    );
    expect(
      title(
        StudySnapshot(
          now: at(18),
          todayMinutes: 20,
          weekMinutes: 60,
          streak: 5,
        ),
      ),
      'Keep your 5-day streak going. One block tonight is enough.',
    );
    // Too late tonight and nothing studied: the streak ends at midnight.
    expect(
      title(StudySnapshot(now: at(21), weekMinutes: 60, streak: 5)),
      'Time for a short study block. I’m ready when you are.',
    );
  });

  test('turning reminders off schedules nothing', () {
    expect(
      PipNudgePlanner.next(
        StudySnapshot(
          now: at(10),
          memory: const AssistantMemory(remindersOff: true),
        ),
      ),
      isNull,
    );
  });

  test('the motivating line changes from day to day', () {
    final lines = {
      for (var day = 1; day <= 8; day++)
        PipNudgePlanner.next(StudySnapshot(now: at(10, day)))!.body,
    };
    expect(lines.length, greaterThan(4));
  });

  group('notification settings', () {
    // A late-night task; a timetable that starts at 06:30 replaces the
    // evening nudge, so it is a second, separate case.
    final task = StudyReminder(
      id: 1,
      title: 'Revise chemistry',
      at: DateTime(2026, 11, 6, 23),
      exam: false,
    );
    final snapshot = StudySnapshot(
      now: at(10),
      memory: AssistantMemory(reminders: [task]),
    );
    final early = StudySnapshot(
      now: at(10),
      memory: AssistantMemory(
        timetable: Timetable(
          startMinute: 6 * 60 + 30,
          blockMinutes: 50,
          breakMinutes: 10,
          subjectMinutes: const {'physics': 60},
        ),
      ),
    );
    List<int> ids(List<PipNudge> nudges) => [for (final n in nudges) n.id];
    const anyHour = NotificationPrefs(quietHoursEnabled: false);

    test('turning streak alerts off drops only the evening nudge', () {
      final off = PipReminders.allowed(
        snapshot,
        const NotificationPrefs(quietHoursEnabled: false, streakAlerts: false),
      );
      expect(ids(off), isNot(contains(PipReminders.eveningId)));
      expect(off, isNotEmpty);
    });

    test('turning session reminders off leaves only the evening nudge', () {
      final off = PipReminders.allowed(
        snapshot,
        const NotificationPrefs(
          quietHoursEnabled: false,
          sessionReminders: false,
        ),
      );
      expect(ids(off), [PipReminders.eveningId]);
      expect(PipReminders.allowed(snapshot, anyHour).length, greaterThan(1));
    });

    test('quiet hours hold a reminder until they end', () {
      final quiet = PipReminders.allowed(snapshot, const NotificationPrefs());
      final task = quiet.singleWhere((n) => n.id == 1000 + 10);
      expect(task.at, DateTime(2026, 11, 7, 7));
    });

    test('quiet hours drop a timetable call rather than send it late', () {
      final all = ids(PipReminders.allowed(early, anyHour));
      final quiet = ids(PipReminders.allowed(early, const NotificationPrefs()));
      expect(all.where((id) => id >= 100 && id < 107), isNotEmpty);
      expect(quiet.where((id) => id >= 100 && id < 107), isEmpty);
    });
  });

  test('clearing removes shown reminders, not only pending ones', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('dev.focusforge/pip');
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await PipNudges.clear();
    expect(calls, ['clear']);
  });
}
