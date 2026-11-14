// How Pip routes the messages students actually send: app questions, study
// habits, school topics, and the actions that must not turn into advice.
// Each expectation is a prefix of a short route label built below.
import 'package:flutter_test/flutter_test.dart';
import 'package:focusforge/features/assistant/brain/assistant_brain.dart';
import 'package:focusforge/features/assistant/brain/assistant_models.dart';
import 'package:focusforge/features/assistant/brain/offline_guide.dart';
import 'package:focusforge/features/assistant/brain/offline_tutor.dart';
import 'package:focusforge/features/assistant/brain/study_snapshot.dart';

const brain = AssistantBrain();
final snap = StudySnapshot(now: DateTime(2026, 11, 14, 12));

String route(String m) {
  final a = brain.parse(m);
  if (a.act == Act.coach) {
    final g = OfflineGuide.app(m);
    if (g != null) return 'coach:guide ${g.id}';
    final t = OfflineTutor.converse(m, snap);
    if (t.context != null) return 'lesson:${t.context!.lessonId}';
    final w = t.reply.says.map((s) => s.copy?.key ?? '').join(' ');
    if (w.startsWith('Choose a topic first')) return 'coach:notopic';
    return 'coach:${w.substring(0, w.length.clamp(0, 60))}';
  }
  final r = brain.respond(a, snap);
  final w = r.says.map((s) => s.copy?.key ?? '').join(' ');
  if (a.act == Act.unknown) {
    return w.startsWith('I can help locally') || w.startsWith('I didn')
        ? 'unknown'
        : 'coach:${w.substring(0, w.length.clamp(0, 60))}';
  }
  if (a.act == Act.tip || a.act == Act.motivate || a.act == Act.plan) {
    return '${a.act.name}:${w.substring(0, w.length.clamp(0, 50))}';
  }
  return a.act.name;
}

// expected: prefix that route() must start with.
const cases = <(String, String)>[
  // app questions
  ("what's my streak", 'streak'),
  ('whats my streak', 'streak'),
  ('mera streak kitna hai', 'streak'),
  ('how much did i study yesterday', 'periodStats'),
  ('how much did i study today', 'periodStats'),
  ('aaj kitna padha', 'periodStats'),
  ('how many hours did i study this week', 'report'),
  ('block instagram', 'lock'),
  ('lock youtube while i study', 'lock'),
  ('instagram band karo', 'lock'),
  ('start 25 min timer', 'focusNow'),
  ('start a 25 minute focus session', 'focusNow'),
  ('timer shuru karo', 'focusNow'),
  ('start studying physics', 'focusNow'),
  ('how do i use strict mode', 'appHelp:strict'),
  ('what is strict mode', 'appHelp:strict'),
  ('what is the breath gate', 'appHelp:breath'),
  ('breath gate kya hai', 'appHelp:breath'),
  ('how does the shield work', 'appHelp:shield'),
  ('how do i block shorts', 'appHelp:shorts'),
  ('how to add a subject', 'appHelp:subject'),
  ('how do i change my daily goal', 'goal'),
  ('set my goal to 3 hours', 'goal'),
  ('how do i join a study group', 'appHelp:group'),
  ('how do i change the clock face', 'appHelp:clock'),
  ('how do i change theme', 'appHelp:theme'),
  ('dark mode', 'appHelp:theme'),
  ('how do achievements work', 'appHelp:badge'),
  ('how do i earn xp', 'appHelp:xp'),
  ('how do i level up', 'appHelp:xp'),
  ('is my data private', 'appHelp:privacy'),
  ('delete my account', 'appHelp:account'),
  ('how do i backup my data', 'appHelp:account'),
  ('ambient sounds', 'appHelp:sound'),
  ('play rain sound', 'appHelp:sound'),
  ('how does the leaderboard work', 'appHelp:leaderboard'),
  ('my rank', 'leaderboard'),
  ('show my reminders', 'reminders'),
  ('remind me to study maths at 6 pm', 'reminder'),
  ('make me a timetable for 6 hours a day', 'timetable'),
  ('what should i study now', 'plan'),
  ('plan my day', 'plan'),
  ('aaj kya padhu', 'plan'),
  ('my report', 'report'),
  ('weekly report', 'report'),
  ('which subject did i study least this month', 'subjectStats'),
  ('top subject this week', 'subjectStats'),
  ('how much time on instagram today', 'distractions'),
  ('my screen time', 'distractions'),
  ('days left for my exam', 'exam'),
  ('when is neet', 'exam'),
  ('jee mains pattern', 'exam'),
  ('who are you', 'intro'),
  ('what can you do', 'help'),
  ('thanks pip', 'thanks'),
  ('good night', 'bye'),
  ('hello', 'greet'),
  // study skills
  ('how to stop procrastinating', 'lesson:procrastination'),
  ('i keep procrastinating', 'lesson:procrastination'),
  ('how to focus better', 'lesson:distraction-habits'),
  ('i cant focus', 'coachx:'),
  ('how to concentrate while studying', 'lesson:distraction-habits'),
  ('padhai me mann nahi lagta', 'coachx:'),
  ('how to make notes', 'lesson:notes'),
  ('how to make good notes', 'lesson:notes'),
  ('active recall kya hai', 'lesson:active-recall'),
  ('what is active recall', 'lesson:active-recall'),
  ('what is spaced repetition', 'lesson:spaced-repetition'),
  ('how to revise before exam', 'coachx:'),
  ('how to revise for exams', 'coachx:'),
  ('revision kaise kare', 'coachx:'),
  ('i feel stressed about exams', 'coachx:'),
  ('exam ka darr lag raha hai', 'coachx:'),
  ('i am so anxious about my results', 'coachx:'),
  ('motivate me', 'motivate'),
  ('i dont feel like studying', 'coachx:'),
  ('i am feeling lazy', 'motivate'),
  ('i failed my test', 'coachx:'),
  ('i got low marks', 'coachx:'),
  ('how to remember what i study', 'coachx:'),
  ('i forget everything i read', 'coachx:'),
  ('how to study for long hours', 'coachx:'),
  ('how many hours should i study', 'coachx:'),
  ('is it okay to study at night', 'coachx:'),
  ('how much sleep do i need', 'coachx:'),
  ('how to manage time', 'coachx:'),
  ('time management tips', 'coachx:'),
  ('give me a study tip', 'tip'),
  ('pomodoro technique kya hai', 'coachx:'),
  ('what is the pomodoro technique', 'coachx:'),
  ('how to study maths', 'coachx:'),
  ('how to study physics', 'coachx:'),
  ('how to read faster', 'coachx:'),
  ('how to write a good essay', 'lesson:essays'),
  ('how to stop using my phone', 'coachx:'),
  ('phone addiction', 'distractions'),
  ('i am bored of studying', 'motivate'),
  ('i am burnt out', 'lesson:burnout'),
  ('i am tired', 'motivate'),
  ('how to wake up early', 'coachx:'),
  ('how to be consistent', 'coachx:'),
  ('study kaise kare', 'coachx:'),
  ('padhai kaise kare', 'coachx:'),
  // school concepts
  ('explain photosynthesis', 'lesson:photosynthesis'),
  ('newtons laws of motion', 'lesson:newton'),
  ('what is ohms law', 'lesson:ohm'),
  ('periodic table', 'lesson:periodic-table'),
  ('trigonometry ratios', 'lesson:trigonometry'),
  ('explain probability', 'lesson:probability'),
  ('organic chemistry basics', 'lesson:organic'),
  ('cell structure', 'lesson:cells'),
  ('reflection of light', 'lesson:optics'),
  ('refraction of light', 'lesson:optics'),
  ('acids and bases', 'lesson:acids-bases'),
  ('what is electric current', 'lesson:electricity'),
  ('explain electricity', 'lesson:electricity'),
  ('what is gravitation', 'lesson:gravitation'),
  ('universal law of gravitation', 'lesson:gravitation'),
  ('explain magnetism', 'lesson:magnetism'),
  ('electromagnetic induction', 'lesson:magnetism'),
  ('what is sound', 'lesson:sound'),
  ('heat transfer', 'lesson:heat'),
  ('conduction convection radiation', 'lesson:heat'),
  ('human digestive system', 'lesson:digestion'),
  ('explain digestion', 'lesson:digestion'),
  ('circulatory system', 'lesson:circulation'),
  ('how does the heart work', 'lesson:circulation'),
  ('nervous system', 'lesson:nervous-system'),
  ('what is dna', 'lesson:dna'),
  ('explain dna replication', 'lesson:dna'),
  ('types of chemical reactions', 'lesson:reactions'),
  ('metals and non metals', 'lesson:metals'),
  ('states of matter', 'lesson:matter'),
  ('area and volume formulas', 'lesson:mensuration'),
  ('explain mensuration', 'lesson:mensuration'),
  ('arithmetic progression', 'lesson:arithmetic-progression'),
  ('what is an ap', 'lesson:arithmetic-progression'),
  ('permutations and combinations', 'lesson:permutations'),
  ('simple interest', 'lesson:interest'),
  ('compound interest formula', 'lesson:interest'),
  ('speed distance time', 'lesson:speed'),
  ('coordinate geometry', 'lesson:coordinate-geometry'),
  ('distance formula', 'lesson:coordinate-geometry'),
  ('polynomials', 'lesson:polynomials'),
  ('sets and venn diagrams', 'lesson:sets'),
  ('explain the french revolution', 'lesson:french-revolution'),
  ('french revolution', 'lesson:french-revolution'),
  ('world war 1', 'lesson:world-war-1'),
  ('the water cycle', 'lesson:water-cycle'),
  ('explain plate tectonics', 'lesson:plate-tectonics'),
  ('what is democracy', 'lesson:democracy'),
  ('supply and demand', 'lesson:supply-demand'),
  ('what is an ecosystem', 'lesson:ecosystems'),
  ('chemical bonding kya hai', 'lesson:bonding'),
  ('explain photosythesis', 'lesson:photosynthesis'),
  ('ohm law samjhao', 'lesson:ohm'),
  ('quiz me on electricity', 'lesson:electricity'),
  ('quiz me on the french revolution', 'lesson:french-revolution'),
  // held-out phrasings, written after the fixes
  ('yesterday kitna padha', 'periodStats'),
  ('how many minutes did i study yesterday', 'periodStats'),
  ('can you block snapchat', 'lock'),
  ('turn on strict mode', 'appHelp:strict'),
  ('what does the breath gate do', 'appHelp:breath'),
  ('shorts kaise band kare', 'appHelp:shorts'),
  ('how to change accent colour', 'appHelp:theme'),
  ('where are the ambient sounds', 'appHelp:sounds'),
  ('how to get more xp', 'appHelp:xp'),
  ('what are badges', 'appHelp:badges'),
  ('how do i create a study group', 'appHelp:groups'),
  ('can i use this on a new phone', 'appHelp:account'),
  ('how do widgets work', 'appHelp:widgets'),
  ('tips to stop procrastination', 'lesson:procrastination'),
  ('how can i focus better while studying', 'lesson:distraction-habits'),
  ('i get distracted easily', 'distractions'),
  ('revision tips for boards', 'coach:Revise by testing'),
  ('i am scared about my board exams', 'coachx:'),
  ('i got bad marks in maths', 'coach:One result'),
  ('how to study biology', 'coach:In biology'),
  ('how to score good marks in physics', 'coach:In physics'),
  ('best time to study', 'coach:The best time'),
  ('how can i wake up early', 'coach:Waking early'),
  ('tell me about photosynthesis', 'lesson:photosynthesis'),
  ('what is gravity', 'lesson:gravitation'),
  ('explain newton second law', 'lesson:newton'),
  ('what is the formula of simple interest', 'lesson:interest'),
  ('nth term of ap', 'lesson:arithmetic-progression'),
  ('what is a polynomial', 'lesson:polynomials'),
  ('what causes earthquakes', 'lesson:plate-tectonics'),
  ('why do volcanoes erupt', 'lesson:plate-tectonics'),
  ('causes of world war 1', 'lesson:world-war-1'),
  ('what happened in the french revolution', 'lesson:french-revolution'),
  ('difference between metals and non metals', 'lesson:metals'),
  ('define democracy', 'lesson:democracy'),
  ('quiz me on dna', 'lesson:dna'),
  ('law of demand', 'lesson:supply-demand'),
  ('how does digestion work', 'lesson:digestion'),
  ('industrial revolution', 'unknown'),
  // must stay actions, not advice
  ('block instagram for 2 hours', 'lock'),
  ('start a 50 minute timer', 'focusNow'),
  ('what is my rank', 'leaderboard'),
  ('how am i doing', 'report'),
  ('plan my exam preparation', 'examPlan'),
  ('make a study plan for tomorrow', 'plan'),
  ('remind me to revise chemistry tomorrow at 5', 'reminder'),
  ('set a goal of 2 hours', 'goal'),
  ('i am sad', 'motivate'),
  ('how much did i study this month', 'periodStats'),
  ('show my weekly report', 'report'),
  ('lock youtube shorts', 'lock'),
  ('good morning pip', 'greet'),
  ('thank you so much', 'thanks'),
  ('what is my streak', 'streak'),
  ('bahut thak gaya, mood nahi', 'motivate'),
];

bool matches(String got, String want) {
  if (want.startsWith('appHelp:')) {
    return got.startsWith('coach:guide ') &&
        got.toLowerCase().contains(want.substring(8));
  }
  if (want == 'coachx:') {
    return got.startsWith('coach:') ||
        got.startsWith('motivate') ||
        got.startsWith('tip');
  }
  return got.startsWith(want);
}

void main() {
  for (final (message, want) in cases) {
    test('"$message" → $want', () {
      final got = route(message);
      expect(matches(got, want), isTrue, reason: 'routed to $got');
    });
  }

  test('a correct topic word is never read as a typo of another topic', () {
    expect(route('explain the french revolution'), 'lesson:french-revolution');
    expect(route('industrial revolution'), 'unknown');
    expect(route('explain photosyntheis'), 'lesson:photosynthesis');
  });

  test('worry that is not about exams does not get exam advice', () {
    expect(OfflineGuide.habit('i am worried about my friend'), isNull);
    expect(OfflineGuide.habit('i am worried about my exam')?.id, 'exam-stress');
  });

  test('every written answer leads with one short line', () {
    for (final topic in [
      ...OfflineGuide.appTopics,
      ...OfflineGuide.habitTopics,
    ]) {
      final lead = topic.text.split('\n').first;
      expect(lead.length, lessThan(140), reason: topic.id);
      expect(topic.text, isNot(contains(RegExp(r'#[0-9a-fA-F]{6}'))));
    }
  });

  test('yesterday reads the right day, also across a week boundary', () {
    final monday = StudySnapshot(
      now: DateTime(2026, 11, 16, 9),
      lastWeekDays: const [0, 0, 0, 0, 0, 0, 75],
    );
    final reply = brain.respond(
      const AssistantAction(Act.periodStats, arg: 'yesterday'),
      monday,
    );
    final line = reply.says.first.copy!;
    expect(line.key, '{0} · {1}');
    expect(line.args.last, const Minutes(75));
    final friday = StudySnapshot(
      now: DateTime(2026, 11, 20, 9),
      weekDays: const [10, 20, 30, 40, 0, 0, 0],
    );
    expect(
      brain
          .respond(
            const AssistantAction(Act.periodStats, arg: 'yesterday'),
            friday,
          )
          .says
          .first
          .copy!
          .args
          .last,
      const Minutes(40),
    );
  });
}
