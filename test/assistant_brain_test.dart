// Pip's reasoning, without a device.
//
// WHAT INVARIANT: typed messages reach the right request — through typos and
// romanised Hindi — and every answer is built from the user's own numbers: a
// plan covers what is left of today's goal and starts with the subject that
// has fallen furthest behind; a report names the subject that slipped; the
// home screen only ever offers real observations, most urgent first.
//
// WHY IT MATTERS: an assistant that plans the wrong subject, or praises a
// week that went badly, teaches people to ignore it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:focusforge/features/assistant/assistant_memory.dart';
import 'package:focusforge/features/assistant/brain/assistant_brain.dart';
import 'package:focusforge/features/assistant/brain/assistant_models.dart';
import 'package:focusforge/features/assistant/brain/study_snapshot.dart';

const brain = AssistantBrain();

SubjectTrend subject(
  String id, {
  int thisWeek = 0,
  int lastWeekSpan = 0,
  int today = 0,
  int weekTarget = 0,
}) => SubjectTrend(
  id: id,
  name: id[0].toUpperCase() + id.substring(1),
  color: Colors.blue,
  thisWeek: thisWeek,
  lastWeekSpan: lastWeekSpan,
  today: today,
  weekTarget: weekTarget,
);

StudySnapshot snapshot({
  int todayMinutes = 0,
  int goalMinutes = 0,
  int defaultGoalMinutes = 0,
  List<SubjectTrend> subjects = const [],
  int weekMinutes = 0,
  int lastWeekSpanMinutes = 0,
  int lastWeekMinutes = 0,
  List<AppMinutes> distracting = const [],
  List<AppMinutes> installed = const [],
  Set<String> locked = const {},
  AssistantMemory memory = const AssistantMemory(),
  int streak = 0,
  DateTime? now,
  bool hasHistory = true,
}) => StudySnapshot(
  now: now ?? DateTime(2026, 11, 5, 15),
  name: 'Sam',
  todayMinutes: todayMinutes,
  goalMinutes: goalMinutes,
  defaultGoalMinutes: defaultGoalMinutes,
  blockMinutes: 50,
  subjects: subjects,
  weekMinutes: weekMinutes,
  lastWeekSpanMinutes: lastWeekSpanMinutes,
  lastWeekMinutes: lastWeekMinutes,
  android: true,
  appListConsent: true,
  usageAccess: true,
  distracting: distracting,
  installed: installed,
  lockedPackages: locked,
  memory: memory,
  streak: streak,
  hasHistory: hasHistory,
);

void main() {
  group('understanding', () {
    Act actOf(String text) => brain.parse(text).act;

    test('plans, reports and starts read from plain English', () {
      expect(actOf('Plan my day please'), Act.plan);
      expect(actOf('what should I study today?'), Act.plan);
      expect(actOf('How am I doing this week?'), Act.report);
      expect(actOf('start a block'), Act.focusNow);
      expect(actOf('What’s distracting me'), Act.distractions);
      expect(actOf('give me a study tip'), Act.tip);
      expect(actOf('thanks!'), Act.thanks);
    });

    test('typos and romanised Hindi still land', () {
      expect(actOf('show my repot'), Act.report);
      expect(actOf('distractoins today'), Act.distractions);
      expect(actOf('aaj kya padhu'), Act.plan);
      expect(actOf('padhai shuru karo'), Act.focusNow);
      expect(actOf('bahut thak gaya, mood nahi'), Act.motivate);
    });

    test('a focus block is not mistaken for blocking an app', () {
      expect(actOf('start a block for physics'), Act.focusNow);
      final lock = brain.parse('please block instagram while I study');
      expect(lock.act, Act.lock);
      expect(lock.arg, 'instagram');
      expect(brain.parse('lock distracting apps').arg, isNull);
    });

    test('an exam by name opens its guide, or plans for it', () {
      expect(brain.parse('tell me about NEET').arg, 'neet-ug');
      expect(brain.parse('jee advanced pattern?').arg, 'jee-advanced');
      expect(brain.parse('JEE mains marking').arg, 'jee-main');
      final plan = brain.parse('make a plan for UPSC');
      expect(plan.act, Act.plan);
      expect(plan.arg, 'exam:upsc-cse');
    });

    test('nonsense asks for help instead of guessing', () {
      expect(actOf('qwzx vbnm'), Act.unknown);
      expect(actOf(''), Act.help);
    });

    test('edit distance counts a swapped pair as one edit', () {
      expect(AssistantBrain.distance('report', 'repot'), 1);
      expect(AssistantBrain.distance('distraction', 'distractoin'), 1);
      expect(AssistantBrain.distance('plan', 'focus'), greaterThan(2));
    });
  });

  group('plans', () {
    test('a plan covers what is left of the goal, neediest subject first', () {
      final s = snapshot(
        todayMinutes: 60,
        goalMinutes: 240,
        subjects: [
          subject('math', thisWeek: 300, lastWeekSpan: 240),
          subject('chemistry', thisWeek: 40, lastWeekSpan: 240),
          subject('physics', thisWeek: 200, lastWeekSpan: 220),
        ],
      );
      final plan = brain.buildPlan(s)!;
      expect(plan.totalMinutes, 180);
      expect(plan.blocks.first.subjectId, 'chemistry');
      expect(
        plan.blocks.every((b) => b.minutes <= 50 && b.minutes >= 10),
        isTrue,
      );
      // The neediest subject gets every other block.
      expect(
        plan.blocks.where((b) => b.subjectId == 'chemistry').length,
        greaterThanOrEqualTo(plan.blocks.length ~/ 2),
      );
    });

    test('a chosen subject leads, and the exam pulls its subjects forward', () {
      final subjects = [
        subject('history', thisWeek: 10),
        subject('physics', thisWeek: 10),
      ];
      expect(
        brain
            .buildPlan(snapshot(subjects: subjects), subjectId: 'physics')!
            .blocks
            .first
            .subjectId,
        'physics',
      );
      expect(
        brain
            .buildPlan(
              snapshot(
                subjects: subjects,
                memory: const AssistantMemory(examId: 'jee-main'),
              ),
            )!
            .blocks
            .first
            .subjectId,
        'physics',
      );
    });

    test('a met goal gets a light review, and length changes in steps', () {
      final s = snapshot(
        todayMinutes: 120,
        goalMinutes: 120,
        subjects: [subject('math')],
      );
      expect(brain.buildPlan(s)!.totalMinutes, 50);
      final longer = brain.buildPlan(
        snapshot(defaultGoalMinutes: 120, subjects: [subject('math')]),
        adjust: 30,
      )!;
      expect(longer.totalMinutes, 150);
    });

    test('with no subject there is no plan, only a way to add one', () {
      expect(brain.buildPlan(snapshot()), isNull);
      final reply = brain.respond(const AssistantAction(Act.plan), snapshot());
      expect(reply.says.single.copy!.key, contains('Add a subject first'));
      expect(reply.suggestions.single.action.act, Act.openFocus);
    });
  });

  group('reports', () {
    test('the report says how the week compares and what slipped', () {
      final s = snapshot(
        weekMinutes: 300,
        lastWeekSpanMinutes: 420,
        lastWeekMinutes: 600,
        subjects: [
          subject('math', thisWeek: 240, lastWeekSpan: 200),
          subject('chemistry', thisWeek: 60, lastWeekSpan: 220),
        ],
      );
      final reply = brain.respond(const AssistantAction(Act.report), s);
      final keys = [for (final say in reply.says) say.copy?.key];
      expect(keys, contains('You’re {0} behind last week at this point.'));
      expect(keys, contains('{0} is down {1} from last week.'));
      expect(
        reply.says.whereType<Say>().any((s) => s.card is ReportCard),
        isTrue,
      );
      expect(
        reply.suggestions.first.action,
        const AssistantAction(Act.plan, arg: 'chemistry'),
      );
      expect(reply.thinking, isNotEmpty);
    });

    test('an empty week asks for one small block instead of a report', () {
      final reply = brain.respond(
        const AssistantAction(Act.report),
        snapshot(),
      );
      expect(
        reply.says.single.copy!.key,
        contains('No study logged this week'),
      );
    });
  });

  group('distractions and locks', () {
    const instagram = AppMinutes('com.instagram.android', 'Instagram', 52);
    const youtube = AppMinutes('com.google.android.youtube', 'YouTube', 34);

    test('apps are found by alias, by name and through a typo', () {
      final s = snapshot(
        installed: const [instagram, youtube],
        distracting: const [instagram],
      );
      expect(brain.findApps('insta', s).single.name, 'Instagram');
      expect(brain.findApps('youtub', s).single.name, 'YouTube');
      expect(brain.findApps('instagram youtube', s).length, 2);
      expect(brain.findApps('spotify', s), isEmpty);
    });

    test('the lock card offers only apps that are not locked yet', () {
      final s = snapshot(
        distracting: const [instagram, youtube],
        locked: {'com.instagram.android'},
      );
      final reply = brain.respond(const AssistantAction(Act.lock), s);
      final card = reply.says.map((s) => s.card).whereType<LockCard>().single;
      expect(card.apps.map((a) => a.name), ['YouTube']);
      expect(card.preselected, {'com.google.android.youtube'});
    });

    test('screen time asks for access before it guesses', () {
      final s = StudySnapshot(now: DateTime(2026, 11, 5), android: true);
      final reply = brain.respond(const AssistantAction(Act.distractions), s);
      final card = reply.says.map((s) => s.card).whereType<ActionCard>().single;
      expect(card.actions.single.action.act, Act.usageAccess);
    });
  });

  group('home', () {
    test('a first meeting is an introduction; a return is a welcome back', () {
      final first = brain.greeting(snapshot(hasHistory: false));
      expect(first.action.act, Act.intro);
      final back = brain.greeting(
        snapshot(memory: AssistantMemory(lastSeen: DateTime(2026, 11, 4))),
      );
      expect(back.copy.key, 'Welcome back, {0}!');
      final soon = brain.greeting(
        snapshot(memory: AssistantMemory(lastSeen: DateTime(2026, 11, 5, 14))),
      );
      expect(soon.copy.key, 'Hi again, {0}. Ready for another round?');
    });

    test('hellos take turns with what Pip noticed, never one line twice', () {
      // Eight launches in a row, each remembering what the last one said.
      var memory = AssistantMemory(lastSeen: DateTime(2026, 11, 5, 14));
      final said = <String>[];
      for (var launch = 0; launch < 8; launch++) {
        final hello = brain.greeting(snapshot(memory: memory));
        said.add(hello.copy.key);
        memory = memory.copyWith(
          helloTurn: memory.helloTurn + 1,
          lastSaid: hello.copy.key,
        );
      }
      expect(said.first, 'Hi again, {0}. Ready for another round?');
      // A greeting, then an observation, then the next greeting.
      expect(said[1], 'Want me to plan today’s study?');
      expect(said[2], 'Good to see you, {0}. What shall we study today?');
      for (var i = 1; i < said.length; i++) {
        expect(said[i], isNot(said[i - 1]), reason: 'launch $i repeats');
      }
      expect(said.toSet().length, greaterThanOrEqualTo(5));
    });

    test(
      'a line whose turn comes round right after it was said is skipped',
      () {
        BuddyPrompt line(String text) =>
            BuddyPrompt(Copy(text), const AssistantAction(Act.greet));
        final lines = [line('a'), line('b'), line('c')];
        expect(AssistantBrain.inTurn(lines, 4, 'a').copy.key, 'b');
        expect(AssistantBrain.inTurn(lines, 4, 'b').copy.key, 'c');
        expect(AssistantBrain.inTurn(lines, 5, 'c').copy.key, 'a');
        // With one line there is nothing else to say.
        expect(AssistantBrain.inTurn([line('a')], 3, 'a').copy.key, 'a');
      },
    );

    test('the memory of what Pip said survives a restart', () {
      final memory = AssistantMemory.fromJson(
        const AssistantMemory(helloTurn: 3, lastSaid: 'Welcome back!').toJson(),
      );
      expect(memory.helloTurn, 3);
      expect(memory.lastSaid, 'Welcome back!');
    });

    test('tips are real observations, the exam countdown first', () {
      final tips = brain.homeTips(
        snapshot(
          memory: AssistantMemory(
            examId: 'neet-ug',
            examDate: DateTime(2026, 12, 5),
          ),
          distracting: const [
            AppMinutes('com.instagram.android', 'Instagram', 45),
          ],
        ),
      );
      expect(tips.first.copy.key, '{0} days to {1}. Let’s make today count.');
      expect(
        tips.map((t) => t.copy.key),
        contains('{0} on {1} today. Lock it while you study?'),
      );
      expect(
        tips.map((t) => t.copy.key),
        contains('Want me to plan today’s study?'),
      );
    });

    test('a quiet day with the goal in hand brings praise, not nagging', () {
      final tips = brain.homeTips(
        snapshot(
          todayMinutes: 60,
          goalMinutes: 120,
          now: DateTime(2026, 11, 5, 9),
          memory: const AssistantMemory(examId: 'cat'),
        ),
      );
      expect([for (final tip in tips) tip.copy.key], [
        'You’re doing great: {0} of focus today.',
        'Want a study timetable for your day?',
      ]);
    });
  });
}
