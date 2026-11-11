// Questions about the user's own study.
//
// WHAT INVARIANT: the many ways of asking "what's my top subject", "which
// subject did I neglect", "how did I do this month" and "make a plan for my
// exam" each reach the right answer for the right period (today, this week,
// this month, overall), and the answers quote the user's real minutes.
//
// WHY IT MATTERS: these are the first things a student asks a study buddy.
// Answering "this week" to a question about the month, or a generic plan to
// "plan for my physics exam", makes the whole assistant feel deaf.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:focusforge/core/localization/app_strings.dart';
import 'package:focusforge/features/assistant/assistant_memory.dart';
import 'package:focusforge/features/assistant/brain/assistant_brain.dart';
import 'package:focusforge/features/assistant/brain/assistant_models.dart';
import 'package:focusforge/features/assistant/brain/reminders.dart';
import 'package:focusforge/features/assistant/brain/study_snapshot.dart';

void main() {
  const brain = AssistantBrain();
  final strings = AppStrings(const Locale('en'));
  final now = DateTime(2026, 11, 6, 10);

  const subjects = [
    SubjectTrend(
      id: 'physics',
      name: 'Physics',
      color: Color(0xFF6750A4),
      thisWeek: 120,
      lastWeekSpan: 90,
      today: 30,
      month: 600,
      total: 3000,
    ),
    SubjectTrend(
      id: 'chem',
      name: 'Chemistry',
      color: Color(0xFF00897B),
      thisWeek: 60,
      lastWeekSpan: 60,
      today: 0,
      month: 300,
      total: 2000,
    ),
    SubjectTrend(
      id: 'bio',
      name: 'Biology',
      color: Color(0xFF43A047),
      thisWeek: 0,
      lastWeekSpan: 30,
      today: 0,
      month: 100,
      total: 4000,
    ),
  ];

  final snapshot = StudySnapshot(
    now: now,
    subjects: subjects,
    todayMinutes: 30,
    sessionsToday: 1,
    goalMinutes: 120,
    weekMinutes: 180,
    lastWeekSpanMinutes: 180,
    monthMinutes: 1000,
    lastMonthSpanMinutes: 700,
    monthDays: 5,
    totalMinutes: 9000,
  );

  String answer(String said, [StudySnapshot? s]) => [
    for (final line in brain.respond(brain.parse(said), s ?? snapshot).says)
      if (line.copy != null) line.copy!.resolve(strings),
  ].join(' ');

  test('the top subject, asked many ways, for the right period', () {
    for (final said in [
      'whats my top subject',
      'which subject did i study the most',
      'my best subject this week',
      'sabse zyada kaunsa subject padha',
    ]) {
      expect(brain.parse(said).act, Act.subjectStats, reason: said);
      expect(answer(said), startsWith('Your top subject this week is Physics'));
    }
    expect(
      answer('top subject this month'),
      // The chart under it ranks the rest.
      'Your top subject this month is Physics: 10h, 60% of your study.',
    );
    expect(
      answer('what is my favourite subject overall'),
      startsWith('Your top subject overall is Biology: 66h 40m'),
    );
  });

  test('the least studied subject, including one not touched at all', () {
    for (final said in [
      'which subject did i neglected this week',
      'weakest subject',
      'kis subject ko kam padha',
    ]) {
      expect(brain.parse(said).act, Act.subjectStats, reason: said);
    }
    expect(answer('weakest subject'), 'Biology got no time this week.');
    expect(
      answer('least studied subject this month'),
      'Biology got the least time this month: 1h 40m.',
    );
  });

  test('performance for a day, a month and all time', () {
    expect(brain.parse('monthly performance').act, Act.periodStats);
    expect(brain.parse('how much did i study today').act, Act.periodStats);
    expect(brain.parse('total study time overall').act, Act.periodStats);
    // The week keeps its full report.
    expect(brain.parse('week performance').act, Act.report);

    expect(
      answer('how did i do this month'),
      startsWith(
        'This month: 16h 40m over 5 days, about 3h 20m on each. '
        'That’s 5h more than this point last month.',
      ),
    );
    expect(
      answer('how much did i study today'),
      // The goal is the ring on the card, not another line.
      'Today: 30m in 1 sessions.',
    );
    expect(
      answer('total study time overall'),
      startsWith('In all, you’ve studied 150h.'),
    );
  });

  test('a plan for a dated exam gives its subject the most time', () {
    final s = StudySnapshot(
      now: now,
      subjects: subjects,
      memory: AssistantMemory(
        reminders: [
          StudyReminder(
            id: 1,
            title: 'Physics exam',
            at: DateTime(2026, 11, 25, 18),
            exam: true,
          ),
        ],
      ),
    );
    for (final said in [
      'make custom plan for my exam',
      'plan for my physics exam',
      'how should i prepare for my test',
    ]) {
      expect(brain.parse(said).act, Act.examPlan, reason: said);
    }
    final reply = brain.respond(
      brain.parse('make custom plan for my exam 4 hours'),
      s,
    );
    expect(
      reply.says.first.copy!.resolve(strings),
      'Physics exam is in 19 days. Here’s a daily plan that gives Physics '
      'the most time. Change it, then save.',
    );
    final card = reply.says.last.card! as TimetableCard;
    expect(card.timetable.totalMinutes, 240);
    expect(card.timetable.subjectMinutes['physics'], 120);
    expect(
      answer('make custom plan for my exam'),
      startsWith('Tell me the exam and its date first'),
    );
  });
}
