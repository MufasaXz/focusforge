// Reminders by date, and the leaderboard question.
//
// WHAT INVARIANT: a typed reminder is read for its day ("nov 25", "25th
// november", "bov 25", "25/11", "tomorrow", "kal", "friday", "in 3 days"),
// its time ("at 6pm", "18:30", "shaam") and what it is about ("Physics
// exam"); a day already gone this year means next year; a test gets a
// countdown and anything else one call on its day; and "check my leaderboard
// position" is answered with the user's place, or how to join.
//
// WHY IT MATTERS: these are the plain requests a student types first. A
// reminder that silently lands on the wrong day is worse than none.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:focusforge/core/localization/app_strings.dart';
import 'package:focusforge/features/assistant/assistant_memory.dart';
import 'package:focusforge/features/assistant/brain/assistant_brain.dart';
import 'package:focusforge/features/assistant/brain/assistant_models.dart';
import 'package:focusforge/features/assistant/brain/reminders.dart';
import 'package:focusforge/features/assistant/brain/study_snapshot.dart';
import 'package:focusforge/features/assistant/nudges/pip_nudges.dart';

void main() {
  const brain = AssistantBrain();
  final strings = AppStrings(const Locale('en'));
  // Thursday 6 November 2026, 10 AM.
  final now = DateTime(2026, 11, 6, 10);

  ReminderRequest read(String said) => ReminderRequest.parse(said, now);

  group('reading a reminder', () {
    test('the request that failed: a typo for November and a physics exam', () {
      final r = read('set reminder for bov 25 its my physics exam');
      expect(r.at, DateTime(2026, 11, 25, 18));
      expect(r.title, 'Physics exam');
      expect(r.exam, isTrue);
    });

    test('dates in the ways people write them', () {
      expect(read('remind me on 25th november').at, DateTime(2026, 11, 25, 18));
      expect(read('remind me nov 25').at, DateTime(2026, 11, 25, 18));
      expect(read('remind me 25 of nov').at, DateTime(2026, 11, 25, 18));
      expect(read('test on 25/11').at, DateTime(2026, 11, 25, 18));
      expect(read('test on 3/1/2027').at, DateTime(2027, 1, 3, 18));
      expect(read('remind me tomorrow').at, DateTime(2026, 11, 7, 18));
      expect(read('kal test hai yaad dilana').at, DateTime(2026, 11, 7, 18));
      expect(read('parso chemistry test').at, DateTime(2026, 11, 8, 18));
      expect(read('remind me in 3 days').at, DateTime(2026, 11, 9, 18));
      expect(read('remind me on friday').at, DateTime(2026, 11, 13, 18));
      expect(read('remind me on saturday').at, DateTime(2026, 11, 7, 18));
      // A date already gone this year is next year's.
      expect(read('remind me on 2 jan').at, DateTime(2027, 1, 2, 18));
      expect(read('remind me about the test').at, isNull);
    });

    test('times, and what the reminder is about', () {
      final r = read('remind me to revise chemistry on friday at 6:30 pm');
      expect(r.at, DateTime(2026, 11, 13, 18, 30));
      expect(r.hasTime, isTrue);
      expect(r.title, 'Revise chemistry');
      expect(r.exam, isFalse);
      expect(read('maths test tomorrow at 9am').at, DateTime(2026, 11, 7, 9));
      expect(read('maths test tomorrow at 6').at, DateTime(2026, 11, 7, 18));
      expect(read('biology quiz kal subah').at, DateTime(2026, 11, 7, 8));
      expect(read('biology quiz kal subah').exam, isTrue);
    });

    test('everyday words are not read as months', () {
      expect(read('can you remind me 5 times').at, isNull);
      expect(read('remind me day 2 of revision').at, isNull);
    });
  });

  group('understanding', () {
    test('leaderboard questions and reminder kinds are told apart', () {
      expect(brain.parse('check my leaderboard position').act, Act.leaderboard);
      expect(brain.parse('what is my rank').act, Act.leaderboard);
      expect(
        brain.parse('set reminder for bov 25 its my physics exam').act,
        Act.reminder,
      );
      expect(brain.parse('remind me to call sir tomorrow').act, Act.reminder);
      expect(brain.parse('show my reminders').act, Act.reminders);
      expect(brain.parse('remove physics reminder').act, Act.reminderOff);
      // The countdown to the exam from the guide stays as it was.
      expect(brain.parse('remind me about my exam').act, Act.examReminder);
      expect(brain.parse('stop exam reminders').act, Act.examReminderOff);
    });
  });

  group('the leaderboard answer', () {
    String said(StudySnapshot s) => [
      for (final line
          in brain.respond(const AssistantAction(Act.leaderboard), s).says)
        line.copy!.resolve(strings),
    ].join(' ');

    test('a place, a total and the gap to the next one up', () {
      expect(
        said(
          StudySnapshot(
            now: now,
            boardJoined: true,
            boardRank: 7,
            boardSize: 20,
            boardMinutes: 310,
            boardBehind: 25,
          ),
        ),
        'You’re #7 of 20 on this week’s leaderboard, with 5h 10m. '
        '25m more and you pass #6.',
      );
    });

    test('someone not on the board is told how to join', () {
      expect(
        said(StudySnapshot(now: now)),
        startsWith('You’re not on the leaderboard yet.'),
      );
    });
  });

  group('notifications', () {
    test('a dated test counts down; a task is called on its day', () {
      final memory = AssistantMemory(
        reminders: [
          StudyReminder(
            id: 1,
            title: 'Physics exam',
            at: DateTime(2026, 11, 25, 18),
            exam: true,
          ),
          StudyReminder(
            id: 2,
            title: 'Revise chemistry',
            at: DateTime(2026, 11, 13, 18, 30),
          ),
        ],
      );
      final all = PipReminders.all(
        StudySnapshot(now: now, weekMinutes: 60, memory: memory),
      );
      final exam = [
        for (final r in all)
          if (r.id >= 1010 && r.id < 1020) r,
      ];
      expect(
        [for (final r in exam) r.at],
        [
          DateTime(2026, 11, 18, 18),
          DateTime(2026, 11, 22, 18),
          DateTime(2026, 11, 24, 18),
          DateTime(2026, 11, 25, 7),
        ],
      );
      expect(
        exam.first.title.resolve(strings),
        'Physics exam is in 7 days. Come study now.',
      );
      final task = all.singleWhere((r) => r.id == 1020);
      expect(task.at, DateTime(2026, 11, 13, 18, 30));
      expect(task.title.resolve(strings), 'Reminder: Revise chemistry');
    });

    test('reminders survive storage', () {
      final memory = AssistantMemory.fromJson(
        AssistantMemory(
          reminders: [
            StudyReminder(
              id: 4,
              title: 'Physics exam',
              at: DateTime(2026, 11, 25, 18),
              exam: true,
            ),
          ],
        ).toJson(),
      );
      expect(memory.reminders.single.title, 'Physics exam');
      expect(memory.reminders.single.exam, isTrue);
      expect(ReminderRequest.nextId(memory.reminders), 5);
    });
  });
}
