import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusforge/features/assistant/assistant_memory.dart';
import 'package:focusforge/features/assistant/brain/assistant_brain.dart';
import 'package:focusforge/features/assistant/brain/assistant_models.dart';
import 'package:focusforge/features/assistant/brain/study_snapshot.dart';

void main() {
  const brain = AssistantBrain();
  final snapshot = StudySnapshot(
    now: DateTime(2026, 11, 14),
    todayMinutes: 35,
    weekMinutes: 95,
    goalMinutes: 90,
    streak: 3,
    blockMinutes: 25,
    breakMinutes: 5,
    memory: AssistantMemory(examDate: DateTime(2026, 11, 19)),
    subjects: const [
      SubjectTrend(
        id: 'math',
        name: 'Maths',
        color: Colors.blue,
        thisWeek: 20,
        lastWeekSpan: 30,
        today: 10,
        weekTarget: 120,
      ),
    ],
  );
  String answer(String question) => brain
      .respond(brain.parse(question), snapshot)
      .says
      .map((v) => v.copy?.key ?? '')
      .join(' ');
  test('local coaching uses real totals, remaining goal, subject need and exam date', () {
    final text = answer('what next');
    for (final value in ['35', '95', '55', 'Maths', '5 days']) {
      expect(text, contains(value));
    }
  });
  test(
    'a custom time budget includes breaks without exceeding available time',
    () {
      final text = answer('I have 40 minutes');
      expect(text, contains('25 min study → 5 min break → 10 min study'));
      expect(text, contains('2 study blocks'));
    },
  );
  test('recall and practice coaching are useful with no external model', () {
    expect(answer('help me remember'), contains('Review them tomorrow'));
    expect(
      answer('help with mock tests'),
      contains('concept, recall, or rushing'),
    );
    expect(answer('unrecognised message'), contains('I can help locally'));
  });
  test(
    'an explicit exam date in the question takes priority over the saved date',
    () {
      expect(answer('exam tomorrow'), contains('For your exam tomorrow'));
      expect(answer('exam today'), contains('For your exam today'));
      expect(answer('exam tomorrow'), isNot(contains('in 5 days')));
    },
  );
}
