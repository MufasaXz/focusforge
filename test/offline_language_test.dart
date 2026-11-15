import 'package:flutter_test/flutter_test.dart';
import 'package:focusforge/features/assistant/brain/assistant_brain.dart';
import 'package:focusforge/features/assistant/brain/assistant_models.dart';
import 'package:focusforge/features/assistant/brain/offline_language.dart';
import 'package:focusforge/features/assistant/brain/offline_tutor.dart';
import 'package:focusforge/features/assistant/brain/study_snapshot.dart';

void main() {
  const brain = AssistantBrain();
  final snapshot = StudySnapshot(
    now: DateTime(2026, 11, 15),
    todayMinutes: 35,
    weekMinutes: 140,
    goalMinutes: 90,
    streak: 4,
  );
  String words(AssistantReply reply) =>
      reply.says.map((s) => s.copy?.key ?? '').join('\n');
  test(
    'Hindi and Hinglish commands preserve original text and numeric budget',
    () {
      expect(brain.parse('आज क्या पढ़ूं').act, Act.plan);
      expect(brain.parse('टाइमर शुरू करो').act, Act.focusNow);
      expect(brain.parse('धन्यवाद').act, Act.thanks);
      const question = 'मेरे पास ३० मिनट हैं';
      expect(brain.parse(question).act, Act.coach);
      expect(brain.parse(question).said, question);
      expect(
        words(OfflineTutor.converse(question, snapshot).reply),
        contains('30'),
      );
      expect(
        OfflineLanguage.understand('i have half an hour'),
        'i have 30 minutes',
      );
    },
  );
  test(
    'negation, hypotheticals and how-to questions never mutate app state',
    () {
      for (final input in [
        "don't start timer",
        'do not remove my reminders',
        'never block instagram',
        'timer shuru mat karo',
        'टाइमर शुरू मत करो',
        'how do i stop reminders',
        'what happens if i start a block',
        'if i finish my homework start timer',
        'how to start timer',
        'can you explain how to delete a timetable',
      ]) {
        final action = brain.parse(input);
        expect(action.act, Act.unknown, reason: input);
        expect(action.arg, startsWith('guard:'), reason: input);
        expect(words(brain.respond(action, snapshot)), isNotEmpty);
      }
      expect(brain.parse('start timer').act, Act.focusNow);
      expect(brain.parse('stop reminders').act, Act.reminderOff);
    },
  );
  test('typos and natural follow-ups retain the current lesson', () {
    var response = OfflineTutor.converse('exaplain fractions', snapshot);
    expect(response.context?.lessonId, 'fractions');
    for (final follow in [
      'samajh nhi aaya',
      'समझ नहीं आया',
      'break it down',
      'ek aur example',
      'what do you mean',
    ]) {
      expect(
        OfflineTutor.isFollowUp(follow, response.context, snapshot.now),
        isTrue,
        reason: follow,
      );
      response = OfflineTutor.converse(
        follow,
        snapshot,
        context: response.context,
      );
      expect(response.context?.lessonId, 'fractions', reason: follow);
      expect(words(response.reply), contains('Fraction'));
    }
  });
  test(
    'Hindi and Hinglish coaching responds to the concern using real totals',
    () {
      expect(
        words(OfflineTutor.converse('आज कितना पढ़ा', snapshot).reply),
        contains('35'),
      );
      expect(
        words(OfflineTutor.converse('आज कितना पढ़ा', snapshot).reply),
        contains('55'),
      );
      final focus = words(
        OfflineTutor.converse('padhne ka mann nahi', snapshot).reply,
      );
      expect(focus, contains('5 minute'));
      expect(focus, contains('35'));
      expect(
        words(OfflineTutor.converse('याद नहीं रहता', snapshot).reply),
        contains('नोट्स बंद'),
      );
      expect(
        words(OfflineTutor.converse('kal exam hai', snapshot).reply),
        contains('Kal ke paper'),
      );
    },
  );
  test(
    'safety and bounded inputs still precede language and command handling',
    () {
      final action = brain.parse('start timer and I want to die');
      expect(action.act, Act.coach);
      expect(words(brain.respond(action, snapshot)), contains('trusted'));
      expect(brain.parse('start timer ${'x' * 3000}').act, Act.coach);
      expect(
        OfflineLanguage.understand('sample mathematics'),
        'sample mathematics',
      );
    },
  );
}
