// Pip's timetable, reminders and new thoughts.
//
// WHAT INVARIANT: a timetable keeps the hours the user asked for, shares the
// rest of the day in half-hour steps, lays its blocks out back to back with
// breaks and never past midnight, and survives storage. Typed hours ("physics
// 2 hours, 90 min chem, 5 ghante roz") are read into it. Reminders are only
// the ones the user asked for: exam countdown days still ahead, and one call
// before the timetable each day for a week, never on a day already started.
// When the phone cannot notify, a due reminder shows once on Home. New
// thoughts cheer a climb up the leaderboard, a better week and a streak, and
// flag a heavy screen-time day.
//
// WHY IT MATTERS: a timetable that quietly drops an hour, or a reminder about
// a block the user already did, is the kind of mistake that gets an app's
// notifications switched off.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:focusforge/core/localization/app_strings.dart';
import 'package:focusforge/core/utils/format.dart';
import 'package:focusforge/features/assistant/assistant_memory.dart';
import 'package:focusforge/features/assistant/brain/assistant_brain.dart';
import 'package:focusforge/features/assistant/brain/assistant_models.dart';
import 'package:focusforge/features/assistant/brain/study_snapshot.dart';
import 'package:focusforge/features/assistant/brain/timetable.dart';
import 'package:focusforge/features/assistant/nudges/pip_nudges.dart';

void main() {
  const brain = AssistantBrain();
  final strings = AppStrings(const Locale('en'));
  // Written the way intl writes it, with its narrow space before "PM".
  final fivePm = formatTimeOfDay(17 * 60, locale: const Locale('en'));
  // Thursday 6 November 2026.
  DateTime at(int hour, [int day = 6, int minute = 0]) =>
      DateTime(2026, 11, day, hour, minute);

  group('timetable', () {
    test('asked hours stay, the rest is shared in half hours', () {
      final t = Timetable.plan(
        totalMinutes: 300,
        subjects: const ['math', 'bio', 'chem', 'eng', 'hist'],
        asked: const {'physics': 120},
        startMinute: 17 * 60,
      );
      expect(t.subjectMinutes, {
        'physics': 120,
        'math': 60,
        'bio': 60,
        'chem': 60,
      });
      expect(t.totalMinutes, 300);
    });

    test('hours beyond the subjects there are stay as untagged study', () {
      final t = Timetable.plan(
        totalMinutes: 240,
        subjects: const ['physics'],
        asked: const {'physics': 120},
        startMinute: 17 * 60,
      );
      expect(t.subjectMinutes, {'physics': 120, '': 120});
      final none = Timetable.plan(
        totalMinutes: 90,
        subjects: const [],
        startMinute: 17 * 60,
      );
      expect(none.subjectMinutes, {'': 90});
    });

    test('blocks run back to back with breaks, cut evenly', () {
      final t = Timetable(
        startMinute: 17 * 60,
        blockMinutes: 50,
        breakMinutes: 10,
        subjectMinutes: const {'physics': 120, 'math': 30},
      );
      expect(t.slots, const [
        TimetableSlot('physics', 1020, 40),
        TimetableSlot('physics', 1070, 40),
        TimetableSlot('physics', 1120, 40),
        TimetableSlot('math', 1170, 30),
      ]);
      expect(t.spanMinutes, 150 + 30);
    });

    test('a day that would run past midnight starts earlier', () {
      final t = Timetable(
        startMinute: 22 * 60,
        blockMinutes: 60,
        breakMinutes: 0,
        subjectMinutes: const {'physics': 180},
      );
      expect(t.effectiveStart, 21 * 60);
      expect(t.slots.last.end, 24 * 60);
    });

    test('a tap moves a subject half an hour; zero takes it off', () {
      final t = Timetable(
        startMinute: 17 * 60,
        blockMinutes: 50,
        breakMinutes: 10,
        subjectMinutes: const {'physics': 60, 'math': 30},
      );
      expect(t.adjust('physics', Timetable.step).subjectMinutes['physics'], 90);
      expect(t.adjust('math', -Timetable.step).subjectMinutes, {'physics': 60});
      expect(t.adjust('bio', 60).subjectMinutes['bio'], 60);
      final only = Timetable(
        startMinute: 0,
        blockMinutes: 50,
        breakMinutes: 10,
        subjectMinutes: const {'physics': 30},
      );
      expect(only.adjust('physics', -30).subjectMinutes, {'physics': 30});
    });

    test('a timetable survives storage, and junk reads as none', () {
      final t = Timetable(
        startMinute: 6 * 60 + 30,
        blockMinutes: 45,
        breakMinutes: 15,
        subjectMinutes: const {'physics': 90, '': 30},
        remind: false,
      );
      final back = Timetable.fromJson(t.toJson())!;
      expect(back.toJson(), t.toJson());
      expect(back.subjectMinutes.keys, ['physics', '']);
      expect(Timetable.fromJson('nope'), isNull);
      expect(Timetable.fromJson({'start': 1}), isNull);
      final memory = AssistantMemory.fromJson(
        AssistantMemory(timetable: t, examReminders: true).toJson(),
      );
      expect(memory.timetable!.totalMinutes, 120);
      expect(memory.examReminders, isTrue);
    });

    test('typed hours are read for subjects and for the day', () {
      const names = {
        'physics': 'Physics',
        'chem': 'Chemistry',
        'math': 'Maths',
      };
      final a = Timetable.parseHours(
        'physics 2 hours, 90 min chem and maths 1.5 hrs',
        names,
      );
      expect(a.asked, {'physics': 120, 'chem': 90, 'math': 90});
      expect(a.total, isNull);
      final b = Timetable.parseHours(
        'make a timetable for 5 ghante roz',
        names,
      );
      expect(b.total, 300);
      expect(b.asked, isEmpty);
      final rest = Timetable.parseHours(
        'physics 2 hours and a 15 min break between sessions',
        names,
      );
      expect(rest.asked, {'physics': 120});
      expect(rest.breakMinutes, 15);
      expect(rest.total, isNull);
      final c = Timetable.parseHours('timetable please', names);
      expect(c.total, isNull);
      expect(c.asked, isEmpty);
    });
  });

  group('chat words', () {
    test('timetables and reminders are understood, and so is “stop”', () {
      expect(brain.parse('make a timetable for 6 hours').act, Act.timetable);
      expect(brain.parse('mera time table bana do').act, Act.timetable);
      expect(brain.parse('delete my timetable').act, Act.timetableOff);
      expect(brain.parse('remind me about my exam').act, Act.examReminder);
      expect(brain.parse('set a reminder for neet').act, Act.examReminder);
      expect(brain.parse('stop exam reminders').act, Act.examReminderOff);
      for (final said in ['make a timetable', 'remind me about my exam']) {
        expect(brain.wantsOnline(said, brain.parse(said)), isFalse);
      }
    });

    test('a timetable reply carries the hours the user typed', () {
      final reply = brain.timetableReply(
        StudySnapshot(
          now: at(10),
          subjects: const [
            SubjectTrend(
              id: 'physics',
              name: 'Physics',
              color: Color(0xFF6750A4),
              thisWeek: 0,
              lastWeekSpan: 0,
              today: 0,
            ),
          ],
        ),
        'physics 2 hours, 4 hours a day',
      );
      final card = reply.says.last.card! as TimetableCard;
      expect(card.timetable.subjectMinutes, {'physics': 120, '': 120});
      expect(card.timetable.startMinute, 17 * 60);
    });
  });

  group('reminders', () {
    final exam = AssistantMemory(
      examId: 'neet-ug',
      examDate: DateTime(2026, 11, 13),
      examReminders: true,
    );

    test('the exam countdown keeps only the days still ahead', () {
      final all = PipReminders.all(
        StudySnapshot(now: at(19), weekMinutes: 60, memory: exam),
      );
      final countdown = [
        for (final r in all)
          if (r.id >= 10 && r.id < 100) r,
      ];
      expect(
        [for (final r in countdown) r.at],
        [at(18, 10), at(18, 12), at(7, 13)],
      );
      expect(
        countdown.first.title.resolve(strings),
        'NEET-UG is in 3 days. Come study now.',
      );
      expect(
        countdown.last.title.resolve(strings),
        'NEET-UG is today. You’ve got this.',
      );
      expect(
        PipReminders.all(
          StudySnapshot(
            now: at(19),
            weekMinutes: 60,
            memory: AssistantMemory(
              examId: 'neet-ug',
              examDate: DateTime(2026, 11, 13),
            ),
          ),
        ).where((r) => r.id >= 10 && r.id < 100),
        isEmpty,
      );
    });

    final timetable = Timetable(
      startMinute: 17 * 60,
      blockMinutes: 50,
      breakMinutes: 10,
      subjectMinutes: const {'physics': 120},
    );

    test('the timetable calls five minutes before, for a week', () {
      final all = PipReminders.all(
        StudySnapshot(
          now: at(10),
          memory: AssistantMemory(timetable: timetable),
          subjects: const [
            SubjectTrend(
              id: 'physics',
              name: 'Physics',
              color: Color(0xFF6750A4),
              thisWeek: 0,
              lastWeekSpan: 0,
              today: 0,
            ),
          ],
        ),
      );
      expect(all, hasLength(PipReminders.timetableDays));
      expect(all.first.at, at(16, 6, 55));
      expect(
        all.first.title.resolve(strings),
        'Your timetable starts at $fivePm.',
      );
      expect(
        all.first.body.resolve(strings),
        'First up: Physics. 2h of study today.',
      );
      // The evening nudge steps aside for the timetable's own call.
      expect(all.any((r) => r.id == PipReminders.eveningId), isFalse);
    });

    test(
      'a day already started, or a timetable without reminders, is quiet',
      () {
        final started = PipReminders.all(
          StudySnapshot(
            now: at(10),
            todayMinutes: 30,
            memory: AssistantMemory(timetable: timetable),
          ),
        );
        expect(started.first.at, at(16, 7, 55));
        final silent = PipReminders.all(
          StudySnapshot(
            now: at(10),
            weekMinutes: 60,
            memory: AssistantMemory(
              timetable: timetable.copyWith(remind: false),
            ),
          ),
        );
        expect([for (final r in silent) r.id], [PipReminders.eveningId]);
      },
    );

    test('without notifications a due reminder shows on Home once', () {
      final due = PipReminders.dueOnHome(
        StudySnapshot(
          now: at(16, 6, 55),
          memory: AssistantMemory(timetable: timetable),
        ),
      );
      expect(due!.copy.resolve(strings), 'Your timetable starts at $fivePm.');
      expect(
        PipReminders.dueOnHome(
          StudySnapshot(
            now: at(16, 6, 55),
            memory: AssistantMemory(
              timetable: timetable,
              homeReminderOn: DateTime(2026, 11, 6),
            ),
          ),
        ),
        isNull,
      );
      expect(
        PipReminders.dueOnHome(
          StudySnapshot(
            now: at(14),
            memory: AssistantMemory(timetable: timetable),
          ),
        ),
        isNull,
      );
      final countdown = PipReminders.dueOnHome(
        StudySnapshot(now: at(9, 10), memory: exam),
      );
      expect(
        countdown!.copy.resolve(strings),
        'NEET-UG is in 3 days. Come study now.',
      );
    });
  });

  group('thoughts', () {
    List<String> thoughts(StudySnapshot s) => [
      for (final tip in brain.homeTips(s)) tip.copy.resolve(strings),
    ];

    test('a climb up the leaderboard is cheered once it happens', () {
      expect(
        thoughts(
          StudySnapshot(
            now: at(10),
            boardRank: 7,
            memory: const AssistantMemory(lastRank: 9),
          ),
        ),
        contains('Wow, you climbed to #7 on the leaderboard!'),
      );
      expect(
        thoughts(
          StudySnapshot(
            now: at(10),
            boardRank: 1,
            memory: const AssistantMemory(lastRank: 2),
          ),
        ),
        contains('Wow, you’re now first on the leaderboard!'),
      );
      expect(
        thoughts(
          StudySnapshot(
            now: at(10),
            boardRank: 9,
            memory: const AssistantMemory(lastRank: 7),
          ),
        ).where((t) => t.contains('leaderboard')),
        isEmpty,
      );
    });

    test('the week against last week, streaks and screen time', () {
      expect(
        thoughts(
          StudySnapshot(
            now: at(10),
            weekMinutes: 300,
            lastWeekSpanMinutes: 200,
          ),
        ),
        contains('This week is 1h 40m ahead of last week. Nice work!'),
      );
      expect(
        thoughts(
          StudySnapshot(now: at(10), weekMinutes: 60, lastWeekSpanMinutes: 200),
        ),
        contains(
          'This week is 2h 20m behind last week. One block today helps.',
        ),
      );
      expect(
        thoughts(StudySnapshot(now: at(10), todayMinutes: 20, streak: 4)),
        contains('4 days in a row. Keep it up!'),
      );
    });
  });

  test('a timetable never goes past the day\'s limit', () {
    final asked = Timetable.plan(
      totalMinutes: 16 * 60,
      subjects: const ['physics', 'chemistry'],
      asked: const {'physics': 8 * 60, 'chemistry': 8 * 60},
      startMinute: 8 * 60,
    );
    expect(asked.totalMinutes, lessThanOrEqualTo(Timetable.maxTotal));
    expect(asked.subjectMinutes['physics'], 8 * 60);

    final full = Timetable(
      startMinute: 8 * 60,
      blockMinutes: 50,
      breakMinutes: 10,
      subjectMinutes: const {'physics': Timetable.maxTotal},
    );
    final added = full.adjust('maths', 60);
    expect(added.totalMinutes, Timetable.maxTotal);
    expect(added.subjectMinutes.containsKey('maths'), isFalse);
  });
}
