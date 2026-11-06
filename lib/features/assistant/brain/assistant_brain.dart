import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/services/ai_backend_service.dart';
import '../mascot/mascot.dart' show kBuddyName;
import 'assistant_models.dart';
import 'exam_guide.dart';
import 'reminders.dart';
import 'study_snapshot.dart';
import 'timetable.dart';

/// Pip's reasoning: what a message means, and what to say back.
///
/// Everything here is a pure function of the [StudySnapshot], so every answer
/// can be tested without a device, and nothing a user types leaves the phone.
/// Typed messages are matched against words in English and romanised Hindi,
/// with room for a typo; the suggestion chips carry their request directly,
/// so they work in every language the app speaks.
class AssistantBrain {
  const AssistantBrain();

  // -- Understanding ----------------------------------------------------------

  AssistantAction parse(String input) {
    final text = normalize(input);
    if (text.isEmpty) return const AssistantAction(Act.help);
    final tokens = text.split(' ');

    final starts = _score(text, tokens, _keywords[Act.focusNow]!);
    final locks = _score(text, tokens, _lockWords);
    if (locks > 0 && locks >= starts) {
      final query = tokens
          .where((t) => !_lockFiller.contains(t) && !_lockWords.contains(t))
          .join(' ')
          .trim();
      return AssistantAction(
        Act.lock,
        arg: query.isEmpty ? null : query,
        said: input,
      );
    }

    final exam = detectExam(text);
    final off = _score(text, tokens, _offWords) > 0;
    if (_score(text, tokens, _timetableWords) > 0) {
      return AssistantAction(
        off ? Act.timetableOff : Act.timetable,
        said: input,
      );
    }
    if (_score(text, tokens, _boardWords) > 0) {
      return AssistantAction(Act.leaderboard, said: input);
    }
    if (_score(text, tokens, _remindWords) > 0) {
      final request = ReminderRequest.parse(input, DateTime.now());
      final generic =
          request.title.isEmpty ||
          const {'Exam', 'Exams', 'Exam date'}.contains(request.title);
      if (_score(text, tokens, _listWords) > 0 && request.at == null) {
        return AssistantAction(Act.reminders, said: input);
      }
      if (off) {
        // What is left once the "stop", "turn off" and such are taken out.
        final about = request.title
            .toLowerCase()
            .split(' ')
            .where(
              (w) =>
                  w.isNotEmpty &&
                  !_offWords.any((o) => o.split(' ').contains(w)),
            )
            .toSet();
        final examOnly = about.isNotEmpty && about.every(_examWord.contains);
        return AssistantAction(
          exam != null || examOnly ? Act.examReminderOff : Act.reminderOff,
          said: input,
        );
      }
      // A named exam from the guide ("reminder for NEET") or just "my exam",
      // with no date: the exam countdown, which knows or asks the date.
      if (request.at == null &&
          (exam != null ||
              (generic && _score(text, tokens, _keywords[Act.examAsk]!) > 0))) {
        return AssistantAction(Act.examReminder, arg: exam, said: input);
      }
      return AssistantAction(Act.reminder, said: input);
    }
    final scores = <Act, double>{
      for (final entry in _keywords.entries)
        entry.key: _score(text, tokens, entry.value),
    };
    if (exam != null) {
      if ((scores[Act.plan] ?? 0) > 0) {
        return AssistantAction(Act.plan, arg: 'exam:$exam', said: input);
      }
      return AssistantAction(Act.exam, arg: exam, said: input);
    }

    Act? best;
    var top = 0.0;
    for (final act in _priority) {
      final score = scores[act] ?? 0;
      if (score > top) {
        top = score;
        best = act;
      }
    }
    return AssistantAction(best ?? Act.unknown, said: input);
  }

  static String normalize(String input) => input
      .toLowerCase()
      .replaceAll(RegExp(r'[’‘`]'), "'")
      .replaceAll("'", '')
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static double _score(String text, List<String> tokens, List<String> words) {
    var score = 0.0;
    for (final word in words) {
      if (word.contains(' ')) {
        if (' $text '.contains(' $word ')) score += 2;
        continue;
      }
      for (final token in tokens) {
        if (token == word) {
          score += 1.2;
        } else if (word.length >= 5 && token.startsWith(word)) {
          score += 1;
        } else if (word.length >= 5 &&
            token.length >= 4 &&
            distance(token, word) <= (word.length >= 8 ? 2 : 1)) {
          score += 0.8;
        }
      }
    }
    return score;
  }

  /// Edit distance between two short words, counting a swap as one edit.
  static int distance(String a, String b) {
    if ((a.length - b.length).abs() > 2) return 3;
    final d = List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0));
    for (var i = 0; i <= a.length; i++) {
      d[i][0] = i;
    }
    for (var j = 0; j <= b.length; j++) {
      d[0][j] = j;
    }
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        d[i][j] = math.min(
          math.min(d[i - 1][j] + 1, d[i][j - 1] + 1),
          d[i - 1][j - 1] + cost,
        );
        if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
          d[i][j] = math.min(d[i][j], d[i - 2][j - 2] + 1);
        }
      }
    }
    return d[a.length][b.length];
  }

  static const _priority = [
    Act.focusNow,
    Act.plan,
    Act.report,
    Act.distractions,
    Act.goal,
    Act.streak,
    Act.tip,
    Act.motivate,
    Act.examAsk,
    Act.intro,
    Act.help,
    Act.thanks,
    Act.bye,
    Act.greet,
  ];

  static const _lockWords = [
    'lock',
    'block',
    'ban',
    'restrict',
    'band karo',
    'band kar',
    'stop opening',
  ];

  static const _lockFiller = {
    'a',
    'an',
    'the',
    'my',
    'me',
    'i',
    'please',
    'pls',
    'plz',
    'can',
    'could',
    'you',
    'while',
    'when',
    'during',
    'study',
    'studying',
    'focus',
    'focusing',
    'and',
    'or',
    'for',
    'app',
    'apps',
    'all',
    'every',
    'them',
    'it',
    'this',
    'that',
    'these',
    'down',
    'up',
    'stop',
    'opening',
    'karo',
    'kar',
    'do',
    'de',
    'band',
    'distracting',
    'social',
    'media',
    'now',
    'today',
    'from',
    'to',
    'on',
    'off',
    'mujhe',
    'mera',
    'meri',
    'ko',
  };

  static const _timetableWords = [
    'timetable',
    'time table',
    'timetables',
    'schedule',
    'routine',
    'hours a day',
    'hours per day',
    'hours daily',
    'hrs a day',
    'ghante roz',
    'roz ghante',
  ];

  static const _remindWords = [
    'remind',
    'reminder',
    'reminders',
    'notify',
    'notification',
    'notifications',
    'alert',
    'yaad',
  ];

  static const _boardWords = [
    'leaderboard',
    'leader board',
    'leaderboards',
    'rank',
    'ranking',
    'rankings',
    'position',
    'standing',
  ];

  static const _examWord = {'exam', 'exams', 'pariksha'};

  static const _listWords = [
    'show',
    'list',
    'all',
    'my reminders',
    'which reminders',
    'what reminders',
  ];

  static const _offWords = [
    'stop',
    'cancel',
    'delete',
    'remove',
    'disable',
    'turn off',
    'switch off',
    'no more',
    'band',
    'hatao',
  ];

  static const _keywords = <Act, List<String>>{
    Act.greet: [
      'hi',
      'hii',
      'hiii',
      'hello',
      'hey',
      'heyy',
      'yo',
      'namaste',
      'namaskar',
      'hola',
      'sup',
      'pip',
      'good morning',
      'good evening',
      'good afternoon',
    ],
    Act.intro: [
      'who are you',
      'your name',
      'what are you',
      'are you ai',
      'are you a bot',
      'are you real',
      'tum kaun',
      'kaun ho',
    ],
    Act.help: [
      'help',
      'what can you do',
      'features',
      'options',
      'menu',
      'commands',
      'kya kar sakte',
    ],
    Act.plan: [
      'plan',
      'planner',
      'schedule',
      'timetable',
      'time table',
      'routine',
      'what should i study',
      'what to study',
      'what do i study',
      'organise',
      'organize',
      'agenda',
      'yojana',
      'plan bana',
      'kya padhu',
      'kya padhna',
      'session',
    ],
    Act.report: [
      'report',
      'progress',
      'performance',
      'stats',
      'statistics',
      'how am i doing',
      'how did i do',
      'how was my',
      'summary',
      'analysis',
      'analyse',
      'analyze',
      'overview',
      'kitna padha',
      'insights',
      'week',
      'subject',
      'subjects',
      'weak',
      'weakest',
      'behind',
    ],
    Act.distractions: [
      'distract',
      'distraction',
      'distracted',
      'distracting',
      'screen time',
      'screentime',
      'phone time',
      'wasted',
      'waste',
      'time waste',
      'lost time',
      'scroll',
      'scrolling',
      'reels',
      'addicted',
      'addiction',
      'social media',
      'usage',
      'instagram',
      'youtube',
    ],
    Act.focusNow: [
      'start a block',
      'start block',
      'start focus',
      'start a session',
      'start session',
      'start studying',
      'start timer',
      'start the timer',
      'focus now',
      'study now',
      'lets study',
      'lets go',
      'begin',
      'padhai shuru',
      'shuru karo',
      'start',
    ],
    Act.examAsk: [
      'exam',
      'exams',
      'entrance',
      'competitive',
      'pattern',
      'syllabus',
      'marking',
      'pariksha',
    ],
    Act.motivate: [
      'motivate',
      'motivation',
      'demotivated',
      'lazy',
      'tired',
      'bored',
      'boring',
      'sad',
      'stress',
      'stressed',
      'anxious',
      'anxiety',
      'cant focus',
      'cannot focus',
      'give up',
      'giving up',
      'overwhelmed',
      'burnout',
      'burnt out',
      'sleepy',
      'procrastinate',
      'procrastinating',
      'procrastination',
      'thak',
      'thaka',
      'mood nahi',
      'man nahi',
      'unmotivated',
      'hopeless',
      'fail',
      'failing',
      'scared',
      'nervous',
    ],
    Act.tip: [
      'tip',
      'tips',
      'technique',
      'method',
      'how to study',
      'study better',
      'remember',
      'memorise',
      'memorize',
      'revise',
      'revision',
      'concentrate',
      'concentration',
      'trick',
      'hack',
      'advice',
      'pomodoro',
      'notes',
    ],
    Act.goal: [
      'goal',
      'target',
      'daily goal',
      'hours a day',
      'how many hours',
      'lakshya',
    ],
    Act.streak: ['streak', 'days in a row', 'consistency', 'consistent'],
    Act.thanks: [
      'thanks',
      'thank you',
      'thx',
      'thankyou',
      'dhanyavad',
      'shukriya',
      'great',
      'awesome',
      'nice',
      'cool',
      'perfect',
      'love you',
    ],
    Act.bye: ['bye', 'goodbye', 'see you', 'good night', 'later', 'tata', 'gn'],
  };

  // -- Answering --------------------------------------------------------------

  AssistantReply respond(
    AssistantAction action,
    StudySnapshot s, {
    int turn = 0,
  }) => switch (action.act) {
    Act.greet => _greet(s),
    Act.intro => _intro(s),
    Act.help => AssistantReply(const [
      Say(Copy('Here’s what I can do:')),
    ], suggestions: defaults(s)),
    Act.plan => _plan(s, action.arg, action.value ?? 0),
    Act.report => _report(s),
    Act.distractions => _distractions(s),
    Act.lock => _lock(s, action.arg),
    Act.focusNow => _focusNow(s, action.arg),
    Act.examAsk => _examAsk(s),
    Act.exam => _exam(s, action.arg),
    Act.examPick => _examPicked(s),
    Act.examDate => _examDated(s),
    Act.motivate => _motivate(s, action.said, turn),
    Act.tip => _tip(turn),
    Act.goal => _goal(s),
    Act.goalSet => AssistantReply(
      [
        Say(
          Copy('Done. Today’s goal is now {0}.', [Minutes(action.value ?? 0)]),
        ),
      ],
      suggestions: [_planChip],
    ),
    Act.streak => _streak(s),
    Act.thanks => AssistantReply(
      const [Say(Copy('Anytime. You do the work — I just keep count.'))],
      suggestions: [_planChip, _reportChip],
    ),
    Act.bye => const AssistantReply([
      Say(Copy('See you soon. Your plan will be here.')),
    ]),
    Act.unknown => AssistantReply(const [
      Say(Copy('I didn’t quite get that. Here’s what I can help with:')),
    ], suggestions: defaults(s)),
    Act.timetable => timetableReply(s, action.said),
    Act.timetableOff => AssistantReply(
      const [Say(Copy('Timetable removed. I won’t remind you about it.'))],
      suggestions: [_timetableChip, _planChip],
    ),
    Act.examReminder => _examReminder(s, notifications: action.value != 0),
    Act.leaderboard => _leaderboard(s),
    Act.reminders => remindersReply(s),
    Act.reminder || Act.reminderOff => remindersReply(s),
    Act.examReminderOff => AssistantReply(const [
      Say(Copy('Okay, no more exam reminders.')),
    ], suggestions: defaults(s)),
    Act.aiAllow ||
    Act.aiDecline ||
    Act.usageAccess ||
    Act.appList ||
    Act.openShield ||
    Act.openFocus ||
    Act.openLeaderboard ||
    Act.reminderDate => const AssistantReply([]),
  };

  /// What to show while working a request out. Empty for small talk.
  List<Copy> thinkingFor(Act act) => switch (act) {
    Act.plan => const [
      Copy('Reading your sessions…'),
      Copy('Building your plan…'),
    ],
    Act.report => const [
      Copy('Reading your sessions…'),
      Copy('Comparing with last week…'),
    ],
    Act.distractions || Act.lock => const [Copy('Checking screen time…')],
    Act.exam || Act.examPick => const [Copy('Looking up the exam…')],
    _ => const [],
  };

  static const _planChip = Suggestion(
    Copy('Plan my study'),
    Icons.event_note_rounded,
    AssistantAction(Act.plan),
  );
  static const _reportChip = Suggestion(
    Copy('My report'),
    Icons.insights_rounded,
    AssistantAction(Act.report),
  );
  static const _startChip = Suggestion(
    Copy('Start a block'),
    Icons.play_arrow_rounded,
    AssistantAction(Act.focusNow),
  );
  static const _tipChip = Suggestion(
    Copy('Study tip'),
    Icons.lightbulb_outline_rounded,
    AssistantAction(Act.tip),
  );
  static const _timetableChip = Suggestion(
    Copy('Make a timetable'),
    Icons.view_timeline_outlined,
    AssistantAction(Act.timetable),
  );
  static const _examReminderChip = Suggestion(
    Copy('Remind me before my exam'),
    Icons.notifications_active_outlined,
    AssistantAction(Act.examReminder),
  );
  static const _distractionChip = Suggestion(
    Copy('What’s distracting me?'),
    Icons.phone_android_rounded,
    AssistantAction(Act.distractions),
  );
  static const _lockChip = Suggestion(
    Copy('Lock distracting apps'),
    Icons.lock_outline_rounded,
    AssistantAction(Act.lock),
  );
  static const _shieldChip = Suggestion(
    Copy('Open Shield'),
    Icons.shield_outlined,
    AssistantAction(Act.openShield),
  );

  /// The everyday chips, adjusted to what this user has set up.
  List<Suggestion> defaults(StudySnapshot s) => [
    _planChip,
    _timetableChip,
    _reportChip,
    _distractionChip,
    Suggestion(
      const Copy('Exam info'),
      Icons.school_outlined,
      s.memory.examId == null
          ? const AssistantAction(Act.examAsk)
          : AssistantAction(Act.exam, arg: s.memory.examId),
    ),
    _tipChip,
    const Suggestion(
      Copy('Motivate me'),
      Icons.bolt_rounded,
      AssistantAction(Act.motivate),
    ),
  ];

  static Copy examTitle(ExamInfo exam) =>
      exam.id == 'boards' ? const Copy('Board exams') : Copy.raw(exam.name);

  Copy _hello(StudySnapshot s) =>
      s.name.isEmpty ? const Copy('Hi!') : Copy('Hi {0}!', [Copy.raw(s.name)]);

  AssistantReply _greet(StudySnapshot s) {
    final tips = homeTips(s);
    return AssistantReply(
      [
        Say(_hello(s)),
        Say(
          tips.isEmpty
              ? const Copy('What shall we do today?')
              : tips.first.copy,
        ),
      ],
      suggestions: [
        if (tips.isNotEmpty)
          Suggestion(
            const Copy('Yes, let’s do it'),
            Icons.check_rounded,
            tips.first.action,
          ),
        ...defaults(s)
            .where((c) => tips.isEmpty || c.action != tips.first.action),
      ],
    );
  }

  AssistantReply _intro(StudySnapshot s) => AssistantReply(
    [
      Say(Copy('Hi, I’m {0}, your study buddy.', [const Copy.raw(kBuddyName)])),
      const Say(
        Copy(
          'I read your study log and screen time on this phone, so I can plan your day, spot distractions and keep you on track.',
        ),
      ),
      if (s.memory.examId == null)
        const Say(Copy('Which exam are you preparing for?')),
    ],
    suggestions: s.memory.examId == null
        ? [
            for (final exam in examGuide)
              Suggestion(
                examTitle(exam),
                Icons.school_outlined,
                AssistantAction(Act.examPick, arg: exam.id),
              ),
            const Suggestion(
              Copy('Skip for now'),
              Icons.arrow_forward_rounded,
              AssistantAction(Act.help),
            ),
          ]
        : defaults(s),
  );

  // -- Plans ------------------------------------------------------------------

  /// Builds today's plan, or null when there is no subject to plan around.
  ///
  /// The length is what is left of today's goal, or the daily-goal setting
  /// when no goal is set. Subjects are ranked by need: hours short of a weekly
  /// target, time behind the same days last week, and a nudge for the
  /// user's exam. The neediest subject gets every other block.
  PlanCard? buildPlan(
    StudySnapshot s, {
    String? subjectId,
    String? examId,
    int adjust = 0,
  }) {
    if (s.subjects.isEmpty) return null;
    final block = s.blockMinutes;
    int target;
    if (s.goalMinutes > 0) {
      target = s.remainingToGoal < 10
          ? 2 * math.min(block, 25)
          : s.remainingToGoal;
    } else {
      target = s.defaultGoalMinutes - s.todayMinutes;
      if (target < 25) target = s.defaultGoalMinutes > 0 ? 60 : 120;
    }
    target = ((target + adjust).clamp(15, 480) / 5).round() * 5;

    final exam = examById(examId ?? s.memory.examId);
    double need(SubjectTrend t) {
      var score = 0.0;
      if (t.weekTarget > 0) {
        score += math.max(0, t.weekTarget - t.thisWeek) / 60 * 2;
      }
      score += math.max(0, t.lastWeekSpan - t.thisWeek) / 60;
      final name = t.name.toLowerCase();
      if (exam != null && exam.subjects.any(name.contains)) score += 1.5;
      score -= t.today / 60;
      score -= t.thisWeek / 600;
      return score;
    }

    final ranked = [...s.subjects]
      ..sort((a, b) {
        final byNeed = need(b).compareTo(need(a));
        return byNeed != 0 ? byNeed : a.name.compareTo(b.name);
      });
    if (subjectId != null) {
      final chosen = ranked.indexWhere((t) => t.id == subjectId);
      if (chosen > 0) ranked.insert(0, ranked.removeAt(chosen));
    }
    final picks = ranked.take(3).toList();
    const pattern3 = [0, 1, 0, 2, 0, 1, 0, 2];
    const pattern2 = [0, 1];

    final blocks = <PlanBlock>[];
    var left = target;
    for (var i = 0; left > 0 && i < 8; i++) {
      final index = switch (picks.length) {
        1 => 0,
        2 => pattern2[i % 2],
        _ => pattern3[i % pattern3.length],
      };
      final t = picks[index];
      final minutes = math.min(block, left);
      if (minutes < 10 && blocks.isNotEmpty) {
        final last = blocks.removeLast();
        blocks.add(
          PlanBlock(
            subjectId: last.subjectId,
            name: last.name,
            color: last.color,
            minutes: last.minutes + minutes,
          ),
        );
        break;
      }
      blocks.add(
        PlanBlock(
          subjectId: t.id,
          name: t.name,
          color: t.color,
          minutes: minutes,
        ),
      );
      left -= minutes;
    }
    return PlanCard(
      blocks: blocks,
      breakMinutes: s.breakMinutes,
      todayBySubject: s.todayBySubject,
      doneToday: s.todayBySubject.values.fold(0, (sum, m) => sum + m),
    );
  }

  AssistantReply _plan(StudySnapshot s, String? arg, int adjust) {
    final examId = arg != null && arg.startsWith('exam:')
        ? arg.substring(5)
        : null;
    final subjectId = examId == null ? arg : null;
    final plan = buildPlan(
      s,
      subjectId: subjectId,
      examId: examId,
      adjust: adjust,
    );
    if (plan == null) {
      return const AssistantReply(
        [Say(Copy('Add a subject first, and I’ll plan around it.'))],
        suggestions: [
          Suggestion(
            Copy('Add a subject'),
            Icons.add_rounded,
            AssistantAction(Act.openFocus),
          ),
        ],
      );
    }
    final total = plan.totalMinutes;
    final intro = s.goalMinutes > 0 && s.remainingToGoal < 10
        ? const Copy('You’ve hit today’s goal. Here’s a light review plan.')
        : s.goalMinutes > 0 && adjust == 0
        ? Copy('Here’s a plan for the {0} left today.', [Minutes(total)])
        : Copy('Here’s a {0} plan for today.', [Minutes(total)]);
    return AssistantReply(
      [Say(intro), Say.card(plan)],
      suggestions: [
        if (total > 30)
          Suggestion(
            const Copy('Make it shorter'),
            Icons.remove_rounded,
            AssistantAction(Act.plan, arg: arg, value: adjust - 30),
          ),
        if (total < 480)
          Suggestion(
            const Copy('Make it longer'),
            Icons.add_rounded,
            AssistantAction(Act.plan, arg: arg, value: adjust + 30),
          ),
        _reportChip,
      ],
      thinking: thinkingFor(Act.plan),
    );
  }

  /// The subject a "start now" should use: the plan's first.
  String? subjectForNow(StudySnapshot s) =>
      buildPlan(s)?.blocks.firstOrNull?.subjectId;

  AssistantReply _focusNow(StudySnapshot s, String? subjectId) {
    if (s.timerRunning) {
      return const AssistantReply([
        Say(Copy('A block is already running. I’ll be here when it ends.')),
      ]);
    }
    final subject = s.subjects.where((t) => t.id == subjectId).firstOrNull;
    return AssistantReply([
      Say(
        subject == null
            ? Copy('Starting a {0} block. I’ll keep watch.', [
                Minutes(s.blockMinutes),
              ])
            : Copy('Starting {0} on {1}. I’ll keep watch.', [
                Minutes(s.blockMinutes),
                Copy.raw(subject.name),
              ]),
      ),
    ]);
  }

  // -- Reports ----------------------------------------------------------------

  /// The subject furthest behind the same days last week, if any is
  /// meaningfully behind.
  SubjectTrend? weakest(StudySnapshot s) {
    final behind =
        s.subjects.where((t) => t.lastWeekSpan >= 30 && t.delta <= -20).toList()
          ..sort((a, b) => a.delta.compareTo(b.delta));
    return behind.firstOrNull;
  }

  AssistantReply _report(StudySnapshot s) {
    if (s.weekMinutes == 0 && s.lastWeekMinutes == 0) {
      return AssistantReply(
        const [
          Say(
            Copy(
              'No study logged this week yet. A 25-minute block is a good start.',
            ),
          ),
        ],
        suggestions: [_startChip, _planChip],
      );
    }
    final lines = <Copy>[];
    final diff = s.weekMinutes - s.lastWeekSpanMinutes;
    if (s.lastWeekSpanMinutes > 0 && diff.abs() >= 15) {
      lines.add(
        diff > 0
            ? Copy('You’re {0} ahead of last week at this point.', [
                Minutes(diff),
              ])
            : Copy('You’re {0} behind last week at this point.', [
                Minutes(-diff),
              ]),
      );
    }
    final weak = weakest(s);
    if (weak != null) {
      lines.add(
        Copy('{0} is down {1} from last week.', [
          Copy.raw(weak.name),
          Minutes(-weak.delta),
        ]),
      );
    }
    final strong = s.subjects.where((t) => t.thisWeek > 0).toList()
      ..sort((a, b) => b.thisWeek.compareTo(a.thisWeek));
    if (strong.isNotEmpty && strong.first.id != weak?.id && lines.length < 2) {
      lines.add(
        Copy('{0} is your strongest subject this week.', [
          Copy.raw(strong.first.name),
        ]),
      );
    }
    final daypart = _bestDaypart(s);
    if (daypart != null && lines.length < 3) lines.add(daypart);
    if (s.reached > 0 && lines.length < 3) {
      lines.add(
        Copy(
          'You reached for blocked apps {0} times today and walked away {1} times.',
          [Count(s.reached), Count(s.walkedAway)],
        ),
      );
    }

    return AssistantReply(
      [
        const Say(Copy('Here’s how your week is going.')),
        Say.card(
          ReportCard(
            todayMinutes: s.todayMinutes,
            goalMinutes: s.goalMinutes,
            weekMinutes: s.weekMinutes,
            lastWeekSpanMinutes: s.lastWeekSpanMinutes,
            streak: s.streak,
            subjects: [
              ...s.subjects.where((t) => t.thisWeek > 0 || t.lastWeekSpan > 0),
            ]..sort((a, b) => b.thisWeek.compareTo(a.thisWeek)),
            usageReady: s.usageReady,
            distractingMinutes: s.distractingMinutes,
            topApps: s.distracting.take(3).toList(),
          ),
        ),
        for (final line in lines) Say(line),
      ],
      suggestions: [
        if (weak != null)
          Suggestion(
            Copy('Plan for {0}', [Copy.raw(weak.name)]),
            Icons.event_note_rounded,
            AssistantAction(Act.plan, arg: weak.id),
          )
        else
          _planChip,
        if (s.distractingMinutes > 0) _lockChip else _distractionChip,
        _tipChip,
      ],
      thinking: thinkingFor(Act.report),
    );
  }

  Copy? _bestDaypart(StudySnapshot s) {
    final total = s.dayparts.fold(0, (sum, m) => sum + m);
    if (total < 120) return null;
    var best = 0;
    for (var i = 1; i < s.dayparts.length; i++) {
      if (s.dayparts[i] > s.dayparts[best]) best = i;
    }
    if (s.dayparts[best] < total * 0.4) return null;
    return const [
      Copy('You focus most in the morning.'),
      Copy('You focus most in the afternoon.'),
      Copy('You focus most in the evening.'),
      Copy('You focus most at night.'),
    ][best];
  }

  AssistantReply _streak(StudySnapshot s) => AssistantReply(
    [
      if (s.streak > 0) ...[
        Say(Copy('You’re on a {0}-day streak.', [Count(s.streak)])),
        if (s.todayMinutes == 0)
          const Say(Copy('One block today keeps it going.')),
      ] else
        const Say(Copy('No streak yet. One block today starts it.')),
    ],
    suggestions: [_startChip, _reportChip],
  );

  // -- Distractions and locks -------------------------------------------------

  AssistantReply _usageNeeded(StudySnapshot s) {
    if (!s.android) {
      return const AssistantReply([
        Say(Copy('Screen time and app blocking work on Android phones.')),
      ]);
    }
    return const AssistantReply([
      Say(
        Copy(
          'I can’t see your screen time yet. Allow app usage, and I’ll show where your time goes.',
        ),
      ),
      Say.card(
        ActionCard([
          Suggestion(
            Copy('Allow app usage'),
            Icons.timelapse_rounded,
            AssistantAction(Act.usageAccess),
          ),
        ]),
      ),
    ]);
  }

  AssistantReply _distractions(StudySnapshot s) {
    if (!s.usageReady) return _usageNeeded(s);
    if (s.distracting.isEmpty) {
      return AssistantReply(
        const [Say(Copy('No time on distracting apps today. Nice work.'))],
        suggestions: [_planChip, _reportChip],
        thinking: thinkingFor(Act.distractions),
      );
    }
    final total = s.distractingMinutes;
    final open = s.distracting
        .where((a) => !s.lockedPackages.contains(a.packageId))
        .take(5)
        .toList();
    final blocks = total ~/ math.max(s.blockMinutes, 1);
    return AssistantReply(
      [
        Say(Copy('Distracting apps took {0} today.', [Minutes(total)])),
        if (blocks >= 1)
          Say(Copy('That’s about {0} focus blocks.', [Count(blocks)])),
        if (open.isNotEmpty) ...[
          const Say(Copy('Want me to lock them while you focus?')),
          Say.card(
            LockCard(
              apps: open,
              preselected: {for (final a in open.take(3)) a.packageId},
            ),
          ),
        ] else
          const Say(Copy('They’re already locked during focus.')),
      ],
      suggestions: [_planChip, _reportChip],
      thinking: thinkingFor(Act.distractions),
    );
  }

  static const _aliases = {
    'insta': 'instagram',
    'ig': 'instagram',
    'yt': 'youtube',
    'fb': 'facebook',
    'snap': 'snapchat',
    'wa': 'whatsapp',
    'tg': 'telegram',
    'netflix': 'netflix',
    'shorts': 'youtube',
    'reels': 'instagram',
  };

  /// Installed apps whose names match the words in [query].
  List<AppMinutes> findApps(String query, StudySnapshot s) {
    final words = query
        .split(' ')
        .map((w) => _aliases[w] ?? w)
        .where((w) => w.length >= 3)
        .toSet();
    final minutes = {for (final a in s.distracting) a.packageId: a.minutes};
    final found = <AppMinutes>[];
    for (final app in s.installed) {
      final name = normalize(app.name);
      final compact = name.replaceAll(' ', '');
      final parts = name.split(' ');
      final hit = words.any(
        (w) =>
            compact == w ||
            parts.contains(w) ||
            (w.length >= 4 && compact.contains(w)) ||
            (w.length >= 5 &&
                parts.any((p) => p.length >= 4 && distance(p, w) <= 1)),
      );
      if (hit) {
        found.add(
          AppMinutes(app.packageId, app.name, minutes[app.packageId] ?? 0),
        );
      }
    }
    found.sort((a, b) => b.minutes.compareTo(a.minutes));
    return found.take(6).toList();
  }

  AssistantReply _lock(StudySnapshot s, String? query) {
    if (!s.android) {
      return const AssistantReply([
        Say(Copy('Screen time and app blocking work on Android phones.')),
      ]);
    }
    if (!s.appListConsent) {
      return const AssistantReply([
        Say(Copy('I need to see your app list before I can lock anything.')),
        Say.card(
          ActionCard([
            Suggestion(
              Copy('Show my apps'),
              Icons.apps_rounded,
              AssistantAction(Act.appList),
            ),
          ]),
        ),
      ]);
    }
    if (query != null && query.isNotEmpty) {
      final matches = findApps(query, s);
      if (matches.isEmpty) {
        return AssistantReply(
          [
            Say(
              Copy('I couldn’t find “{0}” on this phone.', [Copy.raw(query)]),
            ),
          ],
          suggestions: [_lockChip, _shieldChip],
        );
      }
      return AssistantReply([
        const Say(Copy('Here’s what I found. Pick what to lock.')),
        Say.card(
          LockCard(
            apps: matches,
            preselected: {for (final a in matches) a.packageId},
          ),
        ),
      ], thinking: thinkingFor(Act.lock));
    }
    final pool = s.distracting.isNotEmpty
        ? s.distracting
        : s.distractingInstalled;
    final open = pool
        .where((a) => !s.lockedPackages.contains(a.packageId))
        .take(6)
        .toList();
    if (open.isEmpty) {
      return AssistantReply(
        const [
          Say(
            Copy(
              'Nothing obvious to lock right now. You can pick any app in Shield.',
            ),
          ),
        ],
        suggestions: [_shieldChip],
      );
    }
    return AssistantReply([
      const Say(Copy('These pull you away the most. Pick what to lock.')),
      Say.card(
        LockCard(
          apps: open,
          preselected: {
            for (final a in open.take(open.first.minutes > 0 ? 3 : 2))
              a.packageId,
          },
        ),
      ),
    ], thinking: thinkingFor(Act.lock));
  }

  /// What Pip says after apps are locked.
  AssistantReply locked(
    List<String> names, {
    required bool allDay,
    required bool shieldReady,
  }) {
    final list = Copy.raw(names.join(', '));
    return AssistantReply(
      [
        Say(
          allDay
              ? Copy(
                  'Blocked. {0} stays closed until you change it in Shield.',
                  [list],
                )
              : Copy('Locked. {0} will close during focus blocks.', [list]),
        ),
        if (!shieldReady) ...[
          const Say(
            Copy('Shield needs a couple of permissions before locks work.'),
          ),
          const Say.card(ActionCard([_shieldChip])),
        ],
      ],
      suggestions: [_startChip, _planChip],
    );
  }

  // -- Exams ------------------------------------------------------------------

  AssistantReply _examAsk(StudySnapshot s) {
    final saving = s.memory.examId == null;
    return AssistantReply(
      [
        Say(
          saving
              ? const Copy('Which exam are you preparing for?')
              : const Copy('Which exam do you want to know about?'),
        ),
      ],
      suggestions: [
        for (final exam in examGuide)
          Suggestion(
            examTitle(exam),
            Icons.school_outlined,
            AssistantAction(saving ? Act.examPick : Act.exam, arg: exam.id),
          ),
      ],
    );
  }

  AssistantReply _exam(StudySnapshot s, String? id) {
    final exam = examById(id);
    if (exam == null) return _examAsk(s);
    final mine = s.memory.examId == exam.id;
    return AssistantReply(
      [Say.card(ExamCard(examId: exam.id, isMine: mine))],
      suggestions: [
        if (!mine)
          Suggestion(
            const Copy('Set as my exam'),
            Icons.flag_outlined,
            AssistantAction(Act.examPick, arg: exam.id),
          ),
        Suggestion(
          const Copy('Plan for this exam'),
          Icons.event_note_rounded,
          AssistantAction(Act.plan, arg: 'exam:${exam.id}'),
        ),
        const Suggestion(
          Copy('Another exam'),
          Icons.school_outlined,
          AssistantAction(Act.examAsk),
        ),
      ],
      thinking: thinkingFor(Act.exam),
    );
  }

  AssistantReply _examPicked(StudySnapshot s) {
    final exam = examById(s.memory.examId);
    if (exam == null) return _examAsk(s);
    return AssistantReply(
      [
        Say(Copy('Saved. I’ll plan around {0}.', [examTitle(exam)])),
        Say.card(ExamCard(examId: exam.id, isMine: true)),
      ],
      suggestions: [
        const Suggestion(
          Copy('Set my exam date'),
          Icons.event_rounded,
          AssistantAction(Act.examDate),
        ),
        Suggestion(
          const Copy('Plan for this exam'),
          Icons.event_note_rounded,
          AssistantAction(Act.plan, arg: 'exam:${exam.id}'),
        ),
      ],
      thinking: thinkingFor(Act.examPick),
    );
  }

  AssistantReply _examDated(StudySnapshot s) {
    final exam = examById(s.memory.examId);
    final days = s.daysToExam;
    if (exam == null || days == null) return _examAsk(s);
    return AssistantReply(
      [
        Say(
          days == 0
              ? Copy('{0} is today. You’ve got this.', [examTitle(exam)])
              : Copy('Exam date saved. {0} days to go.', [Count(days)]),
        ),
      ],
      suggestions: [
        if (!s.memory.examReminders && days > 0) _examReminderChip,
        Suggestion(
          const Copy('Plan for this exam'),
          Icons.event_note_rounded,
          AssistantAction(Act.plan, arg: 'exam:${exam.id}'),
        ),
        _tipChip,
      ],
    );
  }

  /// The reply to "remind me about my exam": first the exam and its date if
  /// Pip lacks them, then the countdown it set. [notifications] says whether
  /// the phone lets Pip notify; without it the reminders show on Home.
  AssistantReply _examReminder(StudySnapshot s, {required bool notifications}) {
    final exam = examById(s.memory.examId);
    if (exam == null) {
      final ask = _examAsk(s);
      return AssistantReply(const [
        Say(Copy('Which exam should I remind you about?')),
      ], suggestions: ask.suggestions);
    }
    final days = s.daysToExam;
    if (days == null || days < 0) {
      return AssistantReply(
        [
          Say(
            Copy('When is {0}? Pick the date and I’ll remind you before it.', [
              examTitle(exam),
            ]),
          ),
        ],
        suggestions: const [
          Suggestion(
            Copy('Set my exam date'),
            Icons.event_rounded,
            AssistantAction(Act.examDate),
          ),
        ],
      );
    }
    return AssistantReply(
      [
        Say(
          Copy(
            'Done. I’ll remind you a month, two weeks, a week, three days and a day before {0}, and on the day.',
            [examTitle(exam)],
          ),
        ),
        if (!notifications)
          const Say(
            Copy(
              'Notifications are off for FocusForge, so I’ll show these reminders on Home instead.',
            ),
          ),
      ],
      suggestions: [
        Suggestion(
          const Copy('Plan for this exam'),
          Icons.event_note_rounded,
          AssistantAction(Act.plan, arg: 'exam:${exam.id}'),
        ),
        _timetableChip,
      ],
    );
  }

  /// A timetable to adjust: the one saved, or a new one from the hours in
  /// [said] ("6 hours a day", "physics 2 hours, maths 1 hour").
  AssistantReply timetableReply(StudySnapshot s, String? said) {
    final names = {for (final t in s.subjects) t.id: t.name};
    final parsed = Timetable.parseHours(said ?? '', names);
    final saved = s.memory.timetable;
    final asked = parsed.total != null || parsed.asked.isNotEmpty;
    final Timetable timetable;
    if (saved != null && !asked) {
      timetable = saved;
    } else {
      // Subjects falling behind last week come first, then the least studied.
      final order = [...s.subjects]
        ..sort((a, b) {
          final byDelta = a.delta.compareTo(b.delta);
          return byDelta != 0 ? byDelta : a.thisWeek.compareTo(b.thisWeek);
        });
      timetable = Timetable.plan(
        totalMinutes:
            parsed.total ??
            saved?.totalMinutes ??
            (s.defaultGoalMinutes >= 60 ? s.defaultGoalMinutes : 180),
        subjects: [for (final t in order) t.id],
        asked: parsed.asked,
        startMinute: saved?.startMinute ?? defaultTimetableStart(s.now),
        blockMinutes: s.blockMinutes.clamp(25, 90),
        breakMinutes: s.breakMinutes.clamp(5, 20),
      );
    }
    return AssistantReply([
      Say(
        saved != null && !asked
            ? const Copy('Here’s your timetable. Change anything, then save.')
            : Copy(
                'Here’s a timetable for {0} a day. Change the hours or the start time, then save it.',
                [Minutes(timetable.totalMinutes)],
              ),
      ),
      Say.card(
        TimetableCard(
          timetable: timetable,
          names: names,
          colors: {for (final t in s.subjects) t.id: t.color},
        ),
      ),
    ], thinking: thinkingFor(Act.plan));
  }

  static const _openBoardChip = Suggestion(
    Copy('Open leaderboard'),
    Icons.leaderboard_outlined,
    AssistantAction(Act.openLeaderboard),
  );

  static const _remindersChip = Suggestion(
    Copy('My reminders'),
    Icons.notifications_none_rounded,
    AssistantAction(Act.reminders),
  );

  /// Where the user stands on this week's leaderboard.
  AssistantReply _leaderboard(StudySnapshot s) {
    final rank = s.boardRank;
    if (!s.boardJoined) {
      return const AssistantReply(
        [
          Say(
            Copy(
              'You’re not on the leaderboard yet. Join it from the Leaderboard page to see where you stand each week.',
            ),
          ),
        ],
        suggestions: [_openBoardChip],
      );
    }
    if (rank == null) {
      return const AssistantReply(
        [
          Say(
            Copy(
              'You’re on the leaderboard, but this week’s places haven’t loaded yet. Open it to check.',
            ),
          ),
        ],
        suggestions: [_openBoardChip, _startChip],
      );
    }
    final behind = s.boardBehind;
    return AssistantReply(
      [
        Say(
          Copy('You’re #{0} of {1} on this week’s leaderboard, with {2}.', [
            Count(rank),
            Count(s.boardSize),
            Minutes(s.boardMinutes),
          ]),
        ),
        Say(
          rank == 1
              ? const Copy('You’re on top. Keep the lead with a block today.')
              : Copy('{0} more and you pass #{1}.', [
                  Minutes(behind ?? 1),
                  Count(rank - 1),
                ]),
        ),
      ],
      suggestions: [_startChip, _openBoardChip],
    );
  }

  /// The reminders the user has set, to look over or remove.
  AssistantReply remindersReply(StudySnapshot s) {
    final today = DateTime(s.now.year, s.now.month, s.now.day);
    final live = [
      for (final r in s.memory.reminders)
        if (!r.day.isBefore(today)) r,
    ];
    if (live.isEmpty) {
      return const AssistantReply(
        [
          Say(
            Copy(
              'No reminders yet. Try “remind me about my physics test on 25 Nov”.',
            ),
          ),
        ],
        suggestions: [_timetableChip],
      );
    }
    return AssistantReply([
      const Say(Copy('Here are your reminders. Tap the bin to remove one.')),
      Say.card(RemindersCard(live)),
    ]);
  }

  /// The reply once a reminder is set. [notifications] says whether the
  /// phone lets Pip notify; without it the reminder shows on Home.
  AssistantReply reminderSet(
    StudyReminder reminder, {
    required bool notifications,
    required bool hasTime,
  }) {
    final title = Copy.raw(reminder.title);
    final day = Day(reminder.day);
    return AssistantReply(
      [
        Say(
          reminder.exam
              ? Copy(
                  'Done. I’ll remind you about {0} on {1}: a week, three days and a day before, and that morning.',
                  [title, day],
                )
              : hasTime
              ? Copy('Done. I’ll remind you about {0} on {1} at {2}.', [
                  title,
                  day,
                  Clock(reminder.at.hour * 60 + reminder.at.minute),
                ])
              : Copy('Done. I’ll remind you about {0} on {1} in the evening.', [
                  title,
                  day,
                ]),
        ),
        if (!notifications)
          const Say(
            Copy(
              'Notifications are off for FocusForge, so I’ll show these reminders on Home instead.',
            ),
          ),
      ],
      suggestions: [if (reminder.exam) _timetableChip, _remindersChip],
    );
  }

  /// Asks for the day of a reminder the user named without one.
  AssistantReply reminderNeedsDate(String title, {bool passed = false}) =>
      AssistantReply(
        [
          Say(
            passed
                ? const Copy('That date has already passed. Pick another one?')
                : title.isEmpty
                ? const Copy('When should I remind you? Pick a date.')
                : Copy('When is {0}? Pick the date and I’ll remind you.', [
                    Copy.raw(title),
                  ]),
          ),
        ],
        suggestions: const [
          Suggestion(
            Copy('Pick a date'),
            Icons.event_rounded,
            AssistantAction(Act.reminderDate),
          ),
        ],
      );

  /// When a new timetable starts: 5 PM, after school, or soon after now if
  /// the evening has already begun.
  static int defaultTimetableStart(DateTime now) {
    final minute = now.hour * 60 + now.minute;
    if (minute < 16 * 60) return 17 * 60;
    final soon = ((minute + 15) / 30).ceil() * 30;
    return soon.clamp(17 * 60, 21 * 60);
  }

  // -- Encouragement ----------------------------------------------------------

  static const tips = [
    Copy(
      'Active recall: close the book, write down what you remember, then check.',
    ),
    Copy(
      'Spaced repetition: revise after one day, three days, a week and a month.',
    ),
    Copy(
      'Pomodoro: 25 minutes of focus, then 5 of rest. Take a longer break every fourth round.',
    ),
    Copy(
      'Explain it simply, as if to a friend. Where you get stuck is what to study next.',
    ),
    Copy(
      'Mix problem types in one session. It feels harder and sticks better.',
    ),
    Copy('Solve past papers under exam conditions, then study every mistake.'),
    Copy(
      'Sleep 7 to 9 hours. Your memory files the day’s work while you sleep.',
    ),
  ];

  AssistantReply _tip(int turn) => AssistantReply(
    [Say(tips[turn % tips.length])],
    suggestions: [
      const Suggestion(
        Copy('Another tip'),
        Icons.lightbulb_outline_rounded,
        AssistantAction(Act.tip),
      ),
      _startChip,
    ],
  );

  AssistantReply _motivate(StudySnapshot s, String? said, int turn) {
    final text = normalize(said ?? '');
    bool any(List<String> words) => words.any(text.contains);
    final Copy line;
    if (any(['tired', 'sleepy', 'thak', 'exhausted', 'burn'])) {
      line = const Copy(
        'Tired is a signal, not a failure. Try one 15-minute block, or rest properly and come back.',
      );
    } else if (any([
      'stress',
      'anxi',
      'overwhelm',
      'panic',
      'scared',
      'nervous',
    ])) {
      line = const Copy(
        'Breathe in for 4, hold for 7, out for 8. Then pick the smallest next step.',
      );
    } else if (any([
      'bored',
      'boring',
      'focus',
      'procrastin',
      'lazy',
      'distract',
    ])) {
      line = const Copy(
        'Make it smaller: one topic, one 25-minute block, phone in another room.',
      );
    } else {
      line = const [
        Copy('Small blocks add up. Ten minutes still counts.'),
        Copy('You don’t need motivation to start. Starting creates it.'),
        Copy('Compare yourself with last week, not with anyone else.'),
      ][turn % 3];
    }
    return AssistantReply(
      [
        Say(line),
        if (s.streak >= 2)
          Say(Copy('You’re on a {0}-day streak.', [Count(s.streak)])),
      ],
      suggestions: [_startChip, _tipChip, _planChip],
    );
  }

  AssistantReply _goal(StudySnapshot s) => AssistantReply([
    Say(
      s.goalMinutes > 0
          ? Copy('Today’s goal is {0}. Pick a new one:', [
              Minutes(s.goalMinutes),
            ])
          : const Copy('You haven’t set a goal for today. Pick one:'),
    ),
    Say.card(GoalCard(currentMinutes: s.goalMinutes)),
  ]);

  // -- Online answers ---------------------------------------------------------

  /// Whether a typed message is better answered by the online model.
  ///
  /// Things Pip does — lock, start, set a goal — and small talk always stay on
  /// the phone, so they work offline and instantly. A short request for a
  /// report, a plan or an exam card is answered here too. Anything Pip does
  /// not recognise, and any longer, more nuanced question, goes online.
  bool wantsOnline(String text, AssistantAction local) {
    switch (local.act) {
      case Act.unknown:
        return true;
      case Act.lock ||
          Act.leaderboard ||
          Act.reminder ||
          Act.reminders ||
          Act.reminderOff ||
          Act.timetable ||
          Act.timetableOff ||
          Act.examReminder ||
          Act.examReminderOff ||
          Act.focusNow ||
          Act.goal ||
          Act.goalSet ||
          Act.greet ||
          Act.thanks ||
          Act.bye ||
          Act.help ||
          Act.intro:
        return false;
      default:
        final words = normalize(text).split(' ').where((w) => w.isNotEmpty);
        return words.length >= 7;
    }
  }

  /// The one-time question before anything is sent online.
  AssistantReply aiConsentAsk() => const AssistantReply([
    Say(
      Copy(
        'When you’re online, I can give you smarter answers using an AI service. I’d share only your question, our last few messages and a short study summary. Never your name or email. Is that okay?',
      ),
    ),
    Say.card(
      ActionCard([
        Suggestion(
          Copy('Allow'),
          Icons.check_rounded,
          AssistantAction(Act.aiAllow),
        ),
        Suggestion(
          Copy('Keep it on this phone'),
          Icons.phone_android_rounded,
          AssistantAction(Act.aiDecline),
        ),
      ]),
    ),
  ]);

  /// What Pip says when an online answer fails.
  Copy aiNote(AiFailure failure) => switch (failure) {
    AiFailure.signedOut => const Copy(
      'Sign in with your account and I can answer your study questions when you’re online. Here’s what I can do on this phone.',
    ),
    AiFailure.rateLimited => const Copy(
      'That’s a lot of questions in a minute. Give me a moment, then ask again.',
    ),
    AiFailure.dailyLimit => const Copy(
      'I’ve answered a lot today. Let’s pick this up tomorrow.',
    ),
    AiFailure.blocked => const Copy(
      'I can’t help with that one. Let’s get back to your studies.',
    ),
    AiFailure.invalid => const Copy(
      'I couldn’t read that. Try saying it another way.',
    ),
    AiFailure.unavailable ||
    AiFailure.timeout ||
    AiFailure.notReady => const Copy(
      'I can’t reach my online brain right now, so here’s what I can do on this phone.',
    ),
  };

  /// Whether the phone should still answer after an online failure.
  bool fallsBackLocally(AiFailure failure) => switch (failure) {
    AiFailure.unavailable ||
    AiFailure.timeout ||
    AiFailure.notReady ||
    AiFailure.signedOut => true,
    _ => false,
  };

  /// The study summary sent with an online question: numbers and names of
  /// subjects, never the user's name or email.
  Map<String, dynamic> aiContext(StudySnapshot s) {
    final exam = examById(s.memory.examId);
    final days = s.daysToExam;
    return {
      'exam': ?exam?.name,
      'daysToExam': ?days,
      'todayMinutes': s.todayMinutes,
      'goalMinutes': s.goalMinutes,
      'weekMinutes': s.weekMinutes,
      'lastWeekSameDaysMinutes': s.lastWeekSpanMinutes,
      'streak': s.streak,
      'localHour': s.now.hour,
      'subjects': [
        for (final t in s.subjects.take(8))
          {
            'name': t.name,
            'thisWeekMinutes': t.thisWeek,
            'lastWeekSameDaysMinutes': t.lastWeekSpan,
          },
      ],
      if (s.usageReady) 'distractingMinutesToday': s.distractingMinutes,
      if (s.usageReady)
        'topDistractingApps': [for (final a in s.distracting.take(3)) a.name],
    };
  }

  // -- Home -------------------------------------------------------------------

  /// Pip's hello when the home screen opens, once per launch.
  BuddyPrompt greeting(StudySnapshot s) {
    final seen = s.memory.lastSeen;
    if (seen == null && !s.hasHistory) {
      return BuddyPrompt(
        Copy('Hi! I’m {0}, your study buddy. Tap me anytime.', [
          const Copy.raw(kBuddyName),
        ]),
        const AssistantAction(Act.intro),
      );
    }
    final away = seen == null
        ? const Duration(days: 1)
        : s.now.difference(seen);
    if (away >= const Duration(hours: 3)) {
      return BuddyPrompt(
        s.name.isEmpty
            ? const Copy('Welcome back!')
            : Copy('Welcome back, {0}!', [Copy.raw(s.name)]),
        const AssistantAction(Act.greet),
      );
    }
    return BuddyPrompt(
      s.name.isEmpty
          ? const Copy('Hi again. Ready for another round?')
          : Copy('Hi again, {0}. Ready for another round?', [Copy.raw(s.name)]),
      const AssistantAction(Act.greet),
    );
  }

  /// Useful things Pip could say on the home screen, most useful first.
  ///
  /// Whether [tip] cheers a climb up the leaderboard.
  static bool isClimb(BuddyPrompt tip) => tip.copy.key.contains('leaderboard');

  /// Only real observations make the list; there is no filler tip. The home
  /// screen shows at most one of these, and rarely — see the dock.
  List<BuddyPrompt> homeTips(StudySnapshot s) {
    final tips = <BuddyPrompt>[];
    final exam = examById(s.memory.examId);
    final days = s.daysToExam;
    if (exam != null && days != null) {
      final title = examTitle(exam);
      if (days == 0) {
        tips.add(
          BuddyPrompt(
            Copy('{0} is today. You’ve got this.', [title]),
            const AssistantAction(Act.motivate),
          ),
        );
      } else if (days == 1) {
        tips.add(
          BuddyPrompt(
            Copy('{0} is tomorrow. Light revision, then an early night.', [
              title,
            ]),
            const AssistantAction(Act.tip),
          ),
        );
      } else if (days <= 120) {
        tips.add(
          BuddyPrompt(
            Copy('{0} days to {1}. Let’s make today count.', [
              Count(days),
              title,
            ]),
            AssistantAction(Act.plan, arg: 'exam:${exam.id}'),
          ),
        );
      }
    }
    final rank = s.boardRank;
    final lastRank = s.memory.lastRank;
    if (rank != null && lastRank != null && rank < lastRank) {
      tips.add(
        BuddyPrompt(
          rank == 1
              ? const Copy('Wow, you’re now first on the leaderboard!')
              : Copy('Wow, you climbed to #{0} on the leaderboard!', [
                  Count(rank),
                ]),
          const AssistantAction(Act.report),
          happy: true,
        ),
      );
    }
    if (s.timerRunning) return tips;
    if (s.todayMinutes >= 60 && s.remainingToGoal > 0) {
      tips.add(
        BuddyPrompt(
          Copy('You’re doing great: {0} of focus today.', [
            Minutes(s.todayMinutes),
          ]),
          const AssistantAction(Act.report),
          happy: true,
        ),
      );
    }
    if (s.lastWeekSpanMinutes >= 60) {
      final change = s.weekMinutes - s.lastWeekSpanMinutes;
      if (change >= 30) {
        tips.add(
          BuddyPrompt(
            Copy('This week is {0} ahead of last week. Nice work!', [
              Minutes(change),
            ]),
            const AssistantAction(Act.report),
            happy: true,
          ),
        );
      } else if (change <= -30) {
        tips.add(
          BuddyPrompt(
            Copy('This week is {0} behind last week. One block today helps.', [
              Minutes(-change),
            ]),
            const AssistantAction(Act.focusNow),
          ),
        );
      }
    }
    if (s.streak >= 3 && s.todayMinutes > 0) {
      tips.add(
        BuddyPrompt(
          Copy('{0} days in a row. Keep it up!', [Count(s.streak)]),
          const AssistantAction(Act.report),
          happy: true,
        ),
      );
    }
    if (s.distractingMinutes >= 120) {
      tips.add(
        BuddyPrompt(
          Copy('Distracting apps took {0} today. Time for a phone break?', [
            Minutes(s.distractingMinutes),
          ]),
          const AssistantAction(Act.distractions),
        ),
      );
    }
    if (s.goalMinutes == 0) {
      tips.add(
        const BuddyPrompt(
          Copy('Want me to plan today’s study?'),
          AssistantAction(Act.plan),
        ),
      );
    } else if (s.remainingToGoal == 0) {
      tips.add(
        const BuddyPrompt(
          Copy('Goal done for today. Want to see your week?'),
          AssistantAction(Act.report),
          happy: true,
        ),
      );
    } else if (s.now.hour >= 11) {
      tips.add(
        BuddyPrompt(
          Copy('{0} left for today’s goal. Shall we start?', [
            Minutes(s.remainingToGoal),
          ]),
          const AssistantAction(Act.focusNow),
        ),
      );
    }
    final top = s.distracting
        .where((a) => !s.lockedPackages.contains(a.packageId))
        .firstOrNull;
    if (top != null && top.minutes >= 30) {
      tips.add(
        BuddyPrompt(
          Copy('{0} on {1} today. Lock it while you study?', [
            Minutes(top.minutes),
            Copy.raw(top.name),
          ]),
          AssistantAction(Act.lock, arg: AssistantBrain.normalize(top.name)),
        ),
      );
    }
    final weak = weakest(s);
    if (weak != null && weak.lastWeekSpan >= 60) {
      tips.add(
        BuddyPrompt(
          Copy('{0} is behind last week. Plan a session for it?', [
            Copy.raw(weak.name),
          ]),
          AssistantAction(Act.plan, arg: weak.id),
        ),
      );
    }
    if (s.streak >= 2 && s.todayMinutes == 0) {
      tips.add(
        BuddyPrompt(
          Copy('{0}-day streak. One block today keeps it going.', [
            Count(s.streak),
          ]),
          const AssistantAction(Act.focusNow),
        ),
      );
    }
    if (exam != null &&
        days != null &&
        days >= 1 &&
        days <= 120 &&
        !s.memory.examReminders) {
      tips.add(
        BuddyPrompt(
          Copy('Want a reminder before {0}?', [examTitle(exam)]),
          const AssistantAction(Act.examReminder),
        ),
      );
    }
    if (s.memory.timetable == null && s.hasHistory) {
      tips.add(
        const BuddyPrompt(
          Copy('Want a study timetable for your day?'),
          AssistantAction(Act.timetable),
        ),
      );
    }
    if (s.memory.examId == null && s.memory.introduced) {
      tips.add(
        const BuddyPrompt(
          Copy('Preparing for an exam? Tell me which one.'),
          AssistantAction(Act.examAsk),
        ),
      );
    }
    if (s.now.hour >= 23 || s.now.hour < 4) {
      tips.add(
        const BuddyPrompt(
          Copy('Studying late? Keep it short, then get some sleep.'),
          AssistantAction(Act.tip),
        ),
      );
    }
    return tips;
  }
}
