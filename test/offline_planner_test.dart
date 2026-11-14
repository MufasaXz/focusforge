import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusforge/features/assistant/brain/assistant_models.dart';
import 'package:focusforge/features/assistant/brain/offline_planner.dart';
import 'package:focusforge/features/assistant/brain/study_snapshot.dart';

void main() {
  final snapshot = StudySnapshot(
    now: DateTime(2026, 11, 14),
    blockMinutes: 25,
    breakMinutes: 5,
    subjects: const [
      SubjectTrend(
        id: 'maths',
        name: 'Maths',
        color: Colors.blue,
        thisWeek: 20,
        lastWeekSpan: 60,
        today: 10,
        weekTarget: 120,
      ),
      SubjectTrend(
        id: 'chem',
        name: 'Chemistry',
        color: Colors.green,
        thisWeek: 90,
        lastWeekSpan: 30,
        today: 0,
        weekTarget: 90,
      ),
    ],
  );
  const budgets = {
    'I have 40 minutes': 40,
    'I have 1 hour 30 minutes': 90,
    'I have 1.5 hours': 90,
    'I have an hour and a half': 90,
    'I have half an hour': 30,
    'I have a quarter of an hour': 15,
    'I have forty five minutes': 45,
    'mere paas 2 ghante hain': 120,
    'मेरे पास २ घंटे हैं': 120,
    'plan from 6:30 pm to 8 pm': 90,
    'plan from 11 pm to 1 am': 120,
    'plan from 6 pm to 6 pm': 0,
    'I have 90 minutes with 10 min breaks': 90,
    'I have 90 minutes, 20 min blocks and 5 min breaks': 90,
    'I have -30 minutes': -1,
    'I have 0 minutes': 0,
  };
  for (final entry in budgets.entries) {
    test(entry.key, () {
      expect(OfflinePlanner.recognizes(entry.key), isTrue);
      expect(OfflinePlanner.budget(entry.key), entry.value);
    });
  }

  test(
    'every budget 0–480 includes breaks and stays within the exact budget',
    () {
      for (var minutes = 0; minutes <= 480; minutes++) {
        final plan = OfflinePlanner.build(snapshot, 'I have $minutes minutes');
        expect(plan.minutes, minutes);
        expect(plan.slots.fold(0, (sum, s) => sum + s.minutes), minutes);
        expect(plan.slots.every((s) => s.minutes > 0), isTrue);
        for (final (i, slot) in plan.slots.indexed) {
          expect(slot.minutes, lessThanOrEqualTo(i.isEven ? 25 : 5));
        }
      }
    },
  );
  test('compound durations, custom blocks and tiredness adjust correctly', () {
    final custom = OfflinePlanner.build(
      snapshot,
      'I have 90 minutes, 20/5 pomodoro',
    );
    expect(custom.focusMinutes, 20);
    expect(custom.slots.first.minutes, 20);
    expect(
      OfflinePlanner.build(
        snapshot,
        'I am tired and have 40 minutes',
      ).focusMinutes,
      15,
    );
    expect(OfflinePlanner.build(snapshot, 'I have 99 hours').minutes, 480);
  });
  test('subject selection uses deficits and honours named subjects', () {
    expect(OfflinePlanner.ranked(snapshot, '').first.id, 'maths');
    final named = OfflinePlanner.build(snapshot, 'I have 40 minutes for chem');
    expect(
      named.slots.indexed
          .where((s) => s.$1.isEven)
          .every((s) => s.$2.subject?.id == 'chem'),
      isTrue,
    );
    expect(OfflinePlanner.namesSubject('start', 'Art'), isFalse);
  });
  test(
    'existing exam, reminder and ambiguous statements keep their routes',
    () {
      for (final text in [
        'make custom plan for my exam 4 hours',
        'remind me in 20 minutes',
        'I have not studied this week, what should I do tonight?',
      ]) {
        expect(OfflinePlanner.recognizes(text), isFalse, reason: text);
      }
    },
  );
}
