import 'package:flutter/material.dart';

import 'assistant_models.dart';
import 'offline_guide.dart';
import 'offline_knowledge.dart';
import 'offline_math.dart';
import 'offline_planner.dart';
import 'offline_practice.dart';
import 'offline_safety.dart';
import 'offline_text.dart';
import 'study_snapshot.dart';

/// Ephemeral tutoring state, never persisted. The
/// controller clears it on account reset, chat clear, or an unrelated action.
class OfflineContext {
  const OfflineContext({
    required this.lessonId,
    required this.at,
    this.question,
    this.sequence = 0,
    this.attempts = 0,
    this.completed = 0,
    this.correct = 0,
    this.difficulty = 1,
    this.assisted = false,
  });
  final String lessonId;
  final DateTime at;
  final OfflineQuestion? question;
  final int sequence;
  final int attempts;
  final int completed;
  final int correct;
  final int difficulty;
  final bool assisted;
  bool fresh(DateTime now) =>
      !now.isBefore(at) && now.difference(at) <= const Duration(minutes: 20);
}

class OfflineTurn {
  const OfflineTurn(this.reply, [this.context]);
  final AssistantReply reply;
  final OfflineContext? context;
}

/// Authored explanations, keyed practice, bounded calculations and exact time
/// budgets. No model downloads, telemetry, or network dependencies.
abstract final class OfflineTutor {
  static const _followUps = [
    'simpler',
    'make it simpler',
    'in simple words',
    'explain simply',
    'example',
    'another example',
    'worked example',
    'why',
    'explain that',
    'more detail',
    'explain in detail',
    'quiz me',
    'test me',
    'practice',
    'harder',
    'make it harder',
    'hard question',
    'easier',
    'easy question',
    'another question',
    'next question',
    'next',
    'hint',
    'give me a hint',
    'answer',
    'show answer',
    'show the answer',
    'i dont know',
    'skip',
    'samjhao',
    'aur samjhao',
    'समझाओ',
    'और समझाओ',
  ];

  static bool recognizes(String input) {
    if (input.length > OfflineText.maxInputLength ||
        OfflineSafety.reply(input) != null) {
      return true;
    }
    final text = OfflineText.normalize(input);
    if (_followUps.contains(text)) return true;
    // Preserve existing permission, reminder, and timer action flows.
    if (OfflineText.any(text, const [
      'remind',
      'reminder',
      'reminders',
      'notify',
      'timetable',
      'lock',
      'block apps',
      'start timer',
      'start a block',
      'my report',
      'my progress',
      'top subject',
      'weakest subject',
    ])) {
      return false;
    }
    if (OfflineGuide.app(input) != null ||
        OfflinePlanner.recognizes(input) ||
        OfflineMath.recognizes(input)) {
      return true;
    }
    final lessons = OfflineKnowledge.find(input);
    if (lessons.isEmpty || !_asksLesson(text, lessons)) {
      return OfflineGuide.habit(input) != null;
    }
    return true;
  }

  /// Fillers ignored when judging whether a message is just a topic's name.
  static const _filler = {
    'the',
    'a',
    'an',
    'of',
    'on',
    'in',
    'about',
    'me',
    'i',
    'am',
    'please',
    'pls',
    'plz',
    'and',
    'to',
    'my',
  };

  /// Whether a message that names a lesson topic is asking about it: a
  /// question word, the alias alone, or the alias plus a word or two
  /// ("newtons laws of motion", "organic chemistry basics").
  static bool _asksLesson(String text, List<OfflineLesson> lessons) {
    final words = text.split(' ').where((w) => !_filler.contains(w)).length;
    return OfflineText.any(text, const [
          'explain',
          'teach',
          'learn',
          'quiz',
          'test me',
          'practice',
          'practise',
          'question',
          'questions',
          'revise',
          'help',
          'what is',
          'what are',
          'difference',
          'compare',
          'vs',
          'versus',
          'how',
          'samjhao',
          'kya',
          'basics',
          'formula',
          'formulas',
          'define',
          'definition',
          'meaning',
          'tell me about',
          'notes on',
          'why',
          'what causes',
          'causes of',
          'what happened',
          'batao',
          'समझाओ',
          'क्या',
          'बताओ',
        ]) ||
        lessons.any(
          (l) => l.aliases.any((a) {
            final alias = OfflineText.normalize(a);
            return OfflineText.has(text, alias) &&
                words - alias.split(' ').length <= 2;
          }),
        );
  }

  static bool isFollowUp(String input, OfflineContext? context, DateTime now) {
    if (input.length > OfflineText.maxInputLength) return false;
    if (context == null || !context.fresh(now)) return false;
    final text = OfflineText.normalize(input);
    return _followUps.contains(text) ||
        context.question != null &&
            (_option(input, context.question!) != null ||
                RegExp(
                  r'^(?:my answer is |answer is |i think |option )?[a-e1-5]$',
                ).hasMatch(text) ||
                _numericAnswer(input));
  }

  static OfflineTurn converse(
    String input,
    StudySnapshot s, {
    OfflineContext? context,
  }) {
    final safe = OfflineSafety.reply(input);
    if (safe != null) return OfflineTurn(_text(safe));
    if (input.length > OfflineText.maxInputLength) {
      return OfflineTurn(
        _text(
          'Please split that into a shorter question '
          '(up to ${OfflineText.maxInputLength} characters). I can help with one study topic at a time.',
        ),
      );
    }
    final text = OfflineText.normalize(input);
    final previous = context?.fresh(s.now) == true ? context : null;
    if (previous != null &&
        OfflineKnowledge.byId(previous.lessonId) != null &&
        isFollowUp(input, previous, s.now)) {
      return _followUp(input, text, s, previous);
    }
    if (OfflineGuide.app(input) case final topic?) {
      return OfflineTurn(OfflineGuide.reply(topic));
    }
    if (OfflinePlanner.recognizes(input)) return OfflineTurn(_plan(input, s));
    if (OfflineMath.recognizes(input)) {
      return OfflineTurn(_text(OfflineMath.answer(input)));
    }
    final lessons = OfflineKnowledge.find(input);
    if (lessons.isEmpty || !_asksLesson(text, lessons)) {
      if (OfflineGuide.habit(input) case final topic?) {
        return OfflineTurn(OfflineGuide.reply(topic));
      }
    }
    if (lessons.length >= 2 &&
        OfflineText.any(text, const [
          'vs',
          'versus',
          'compare',
          'difference',
        ])) {
      final a = lessons[0];
      final b = lessons[1];
      return OfflineTurn(
        _text(
          '${a.title}: ${a.summary}\n\n${b.title}: ${b.summary}\n\n'
          'Explain when each idea is useful, then try one example of each.',
          suggestions: [_topicChip(a), _topicChip(b)],
        ),
      );
    }
    final lesson = lessons.firstOrNull;
    if (lesson != null) {
      final next = OfflineContext(lessonId: lesson.id, at: s.now);
      final asksPractice =
          OfflineText.any(text, const [
            'quiz',
            'test me',
            'practice question',
            'practise question',
            'challenge',
          ]) ||
          !OfflineText.any(text, const [
                'explain',
                'teach',
                'what is',
                'what are',
              ]) &&
              OfflineText.any(text, const [
                'practice',
                'practise',
                'question',
                'questions',
              ]);
      if (asksPractice) {
        return _question(
          lesson,
          s,
          next,
          harder: OfflineText.any(text, const [
            'hard',
            'hardest',
            'harder',
            'difficult',
            'advanced',
            'challenge',
          ]),
        );
      }
      if (OfflineText.any(text, const ['flashcards', 'flashcard'])) {
        final cards = lesson.questions
            .take(3)
            .map(
              (q) =>
                  'Q: ${q.prompt}\nA: ${q.options[q.correct]}. ${q.explanation}',
            )
            .join('\n\n');
        return OfflineTurn(
          _text(
            '${lesson.title} — recall cards\n\n$cards\n\n'
            'Cover each answer before recalling it. No reminders have been saved.',
            suggestions: _lessonChips(lesson),
          ),
          next,
        );
      }
      return _explain(lesson, s);
    }
    return OfflineTurn(
      _text(
        'Choose a topic first, for example fractions, derivatives, '
        'photosynthesis, genetics, SQL, active recall, or essay writing. '
        'I use a bundled study library and calculations, so I may not know every '
        'topic or the latest syllabus.',
        suggestions: [
          _topicChip(OfflineKnowledge.lessons.first),
          _topicChip(OfflineKnowledge.byId('derivatives')!),
          _topicChip(OfflineKnowledge.byId('photosynthesis')!),
        ],
      ),
    );
  }

  static OfflineTurn _explain(
    OfflineLesson lesson,
    StudySnapshot s, {
    String mode = '',
    OfflineContext? context,
  }) {
    final answer = switch (mode) {
      'simple' =>
        '${lesson.title}\n\n${_simple(lesson)}\n\nSay the main idea in your own words, then ask for a worked example.',
      'example' =>
        '${lesson.title} — worked example\n\n${lesson.example}\n\nCheck: ${lesson.pitfall}',
      _ =>
        '${lesson.title}\n\n${lesson.summary}\n\nExample: ${lesson.example}\n\nWatch out: ${lesson.pitfall}',
    };
    return OfflineTurn(
      _text(answer, suggestions: _lessonChips(lesson)),
      context == null
          ? OfflineContext(lessonId: lesson.id, at: s.now)
          : _copy(
              context,
              s,
              assisted: context.question != null || context.assisted,
            ),
    );
  }

  static OfflineTurn _followUp(
    String input,
    String text,
    StudySnapshot s,
    OfflineContext previous,
  ) {
    final lesson = OfflineKnowledge.byId(previous.lessonId)!;
    final q = previous.question;
    if (q != null) {
      if (OfflineText.any(text, const [
        'hint',
        'give me a hint',
        'i dont know',
      ])) {
        return OfflineTurn(
          _text(
            'Hint: ${q.hint}\n\nChoose A, B, C, or D when you are ready.',
            suggestions: _quizChips(),
          ),
          _copy(previous, s, assisted: true),
        );
      }
      if (OfflineText.any(text, const [
        'answer',
        'show answer',
        'show the answer',
        'skip',
      ])) {
        return _finish(q, s, previous, correct: false, reveal: true);
      }
      final choice = _option(input, q);
      if (choice != null) {
        if (choice == q.correct) return _finish(q, s, previous, correct: true);
        if (previous.attempts >= 1) {
          return _finish(q, s, previous, correct: false);
        }
        return OfflineTurn(
          _text(
            'Not quite. ${q.hint}\n\nTry A, B, C, or D once more, or ask for the answer.',
            suggestions: _quizChips(),
          ),
          _copy(previous, s, attempts: 1),
        );
      }
      if (RegExp(r'^(?:option )?[e5]$').hasMatch(text) ||
          _numericAnswer(input)) {
        return OfflineTurn(
          _text('Please choose A, B, C, or D, or ask for a hint.'),
          _copy(previous, s),
        );
      }
    }
    if (OfflineText.any(text, const [
      'quiz me',
      'test me',
      'practice',
      'next',
      'next question',
      'another question',
      'harder',
      'make it harder',
      'hard question',
      'easier',
      'easy question',
    ])) {
      return _question(
        lesson,
        s,
        previous,
        harder: OfflineText.any(text, const [
          'harder',
          'make it harder',
          'hard question',
        ]),
        easier: OfflineText.any(text, const ['easier', 'easy question']),
      );
    }
    if (OfflineText.any(text, const [
      'answer',
      'show answer',
      'show the answer',
      'hint',
    ])) {
      return OfflineTurn(
        _text(
          'There is no unanswered practice question. Choose “Quiz me” to start.',
          suggestions: _lessonChips(lesson),
        ),
        _copy(previous, s),
      );
    }
    final simple = OfflineText.any(text, const [
      'simpler',
      'make it simpler',
      'in simple words',
      'explain simply',
      'samjhao',
      'समझाओ',
    ]);
    final example = OfflineText.any(text, const [
      'example',
      'another example',
      'worked example',
    ]);
    return _explain(
      lesson,
      s,
      context: previous,
      mode: simple
          ? 'simple'
          : example
          ? 'example'
          : '',
    );
  }

  static OfflineTurn _question(
    OfflineLesson lesson,
    StudySnapshot s,
    OfflineContext previous, {
    bool harder = false,
    bool easier = false,
  }) {
    final difficulty = harder
        ? 3
        : easier
        ? 1
        : previous.difficulty;
    final generated = OfflinePractice.question(
      lesson,
      previous.sequence,
      difficulty,
    );
    if (generated == null) {
      final next =
          OfflineKnowledge.lessons[(OfflineKnowledge.lessons.indexOf(lesson) +
                  1) %
              OfflineKnowledge.lessons.length];
      return OfflineTurn(
        _text(
          'You have reached the end of the bundled questions for ${lesson.title}. '
          'Try another topic, or revisit the explanation and attempt your textbook questions.',
          suggestions: [_topicChip(next), _topicChip(lesson)],
        ),
        _copy(previous, s),
      );
    }
    final prefix = previous.question == null
        ? ''
        : 'Previous answer: ${previous.question!.options[previous.question!.correct]}. '
              '${previous.question!.explanation}\n\n';
    final options = generated.options.indexed
        .map((e) => '${String.fromCharCode(65 + e.$1)}. ${e.$2}')
        .join('\n');
    return OfflineTurn(
      _text(
        '$prefix${lesson.title} — '
        '${generated.difficulty >= 3 ? 'challenge' : 'practice'}\n\n'
        '${generated.prompt}\n\n$options\n\nReply A, B, C, or D. You can ask for a hint.',
        suggestions: _quizChips(),
      ),
      OfflineContext(
        lessonId: lesson.id,
        at: s.now,
        question: generated,
        sequence: previous.sequence + 1,
        completed: previous.completed + (previous.question == null ? 0 : 1),
        correct: previous.correct,
        difficulty: difficulty,
      ),
    );
  }

  static OfflineTurn _finish(
    OfflineQuestion q,
    StudySnapshot s,
    OfflineContext previous, {
    required bool correct,
    bool reveal = false,
  }) {
    final completed = previous.completed + 1;
    final score =
        previous.correct +
        (correct && previous.attempts == 0 && !previous.assisted ? 1 : 0);
    final difficulty = !correct || previous.attempts > 0 || previous.assisted
        ? (previous.difficulty - 1).clamp(1, 3)
        : completed.isEven
        ? (previous.difficulty + 1).clamp(1, 3)
        : previous.difficulty;
    return OfflineTurn(
      _text(
        '${reveal
            ? 'Answer'
            : correct
            ? 'Correct'
            : 'Let’s work it through'}: '
        '${q.options[q.correct]}. ${q.explanation}\n\n'
        'Practice check: $score of $completed answered correctly on the first try without a hint. '
        'This is a practice score, not a prediction of exam marks.',
        suggestions: [
          _chip('Next question', 'next question', Icons.navigate_next_rounded),
          _chip('Harder question', 'harder', Icons.psychology_alt_outlined),
          _chip('Worked example', 'worked example', Icons.menu_book_rounded),
        ],
      ),
      OfflineContext(
        lessonId: previous.lessonId,
        at: s.now,
        sequence: previous.sequence,
        completed: completed,
        correct: score,
        difficulty: difficulty,
      ),
    );
  }

  static OfflineContext _copy(
    OfflineContext p,
    StudySnapshot s, {
    int? attempts,
    bool? assisted,
  }) => OfflineContext(
    lessonId: p.lessonId,
    at: s.now,
    question: p.question,
    sequence: p.sequence,
    attempts: attempts ?? p.attempts,
    completed: p.completed,
    correct: p.correct,
    difficulty: p.difficulty,
    assisted: assisted ?? p.assisted,
  );

  static int? _option(String input, OfflineQuestion q) {
    final text = OfflineText.normalize(input);
    // Preserve mathematical signs and separators. Normalising prose would
    // collapse −2 and 2, or 1/2 and 12, into the same answer.
    final value = input.toLowerCase().replaceFirst(
      RegExp(r'^(?:my answer is |answer is |i think )'),
      '',
    );
    final exact = q.options.indexWhere(
      (o) => _optionText(o) == _optionText(value),
    );
    if (exact >= 0) return exact;
    final match = RegExp(
      r'^(?:my answer is |answer is |i think |option )?([a-d])$',
    ).firstMatch(text);
    if (match != null) {
      final answer = match[1]!;
      return answer.codeUnitAt(0) - 97;
    }
    final numbered = RegExp(r'^option ([1-4])$').firstMatch(text);
    if (numbered != null) return int.parse(numbered[1]!) - 1;
    return null;
  }

  static String _optionText(String input) =>
      input.toLowerCase().replaceAll('−', '-').replaceAll(RegExp(r'\s+'), '');
  static bool _numericAnswer(String input) =>
      RegExp(r'^\s*[-−]?\d+(?:[./]\d+)?\s*$').hasMatch(input);

  static String _simple(OfflineLesson lesson) => switch (lesson.id) {
    'derivatives' =>
      'A derivative tells you how fast something is changing right now. '
          'On a graph, it is the slope at one point. A steeper upward slope means a larger positive derivative.',
    'integrals' =>
      'An integral adds many tiny contributions. Think of adding thin strips '
          'under a graph, keeping track of which side of the axis they are on.',
    'conditional-probability' =>
      'A condition gives you new information. Keep only the outcomes '
          'that fit it, then work out the chance inside that smaller group.',
    'logarithms' =>
      'A logarithm asks “what power do I need?” Since 2 cubed is 8, '
          'the base-2 logarithm of 8 is 3.',
    'matrices' =>
      'A matrix is a rectangular grid of numbers. The positions matter. '
          'You can use the grid to describe several equations or how points move.',
    'thermodynamics' =>
      'Energy can enter or leave a system as heat or work. '
          'The first law keeps an account of those transfers.',
    'complexity' =>
      'Complexity asks how the work grows when a problem gets bigger. '
          'Searching every item takes roughly twice as much work when the list doubles.',
    'recursion' =>
      'Recursion solves a task by asking for a smaller version of the same task. '
          'There must be a small enough case that can be answered directly.',
    _ => lesson.summary.split(RegExp(r'(?<=[.!?])\s+')).first,
  };

  static AssistantReply _plan(String input, StudySnapshot s) {
    final plan = OfflinePlanner.build(s, input);
    if (plan.requestedMinutes <= 0) {
      return _text(
        'Take a proper break. When you have a few minutes, choose one small topic to revisit.',
      );
    }
    final timeline = plan.slots.indexed
        .take(13)
        .map((e) => '${e.$2.minutes} min ${e.$1.isEven ? 'study' : 'break'}')
        .join(' → ');
    final tasks = <String>[];
    for (final slot in plan.slots.indexed.where((e) => e.$1.isEven).take(4)) {
      final subject = slot.$2.subject?.name ?? 'your chosen topic';
      final task = switch (slot.$1 ~/ 2 % 3) {
        0 => 'recall what you know, then repair one gap',
        1 => 'attempt practice questions and check the method',
        _ => 'redo a missed question and explain the correction',
      };
      tasks.add('• $subject: $task.');
    }
    return _text(
      'Use ${plan.requestedMinutes > 480 ? 'the next ' : ''}${plan.minutes} minutes: '
      '$timeline${plan.slots.length > 13 ? ' → continue the study/break pattern within the remaining time' : ''}. '
      'That is ${plan.blocks} study block${plan.blocks == 1 ? '' : 's'}, with breaks included '
      '(${plan.studyMinutes} focus minutes).\n\n${tasks.join('\n')}'
      '${plan.requestedMinutes > 480 ? '\n\nI capped this plan at 8 hours including breaks. Keep time for meals, sleep, and other commitments.' : ''}'
      '\n\n${s.timerRunning ? 'Your focus timer is already running. Finish or pause that block before starting another.' : 'This is a suggested plan; your timer and saved goals have not been changed.'}',
    );
  }

  static AssistantReply _text(
    String text, {
    List<Suggestion> suggestions = const [],
  }) => AssistantReply([Say(Copy.raw(text))], suggestions: suggestions);
  static Suggestion _chip(String label, String question, IconData icon) =>
      Suggestion(Copy(label), icon, AssistantAction(Act.coach, said: question));
  static Suggestion _topicChip(OfflineLesson lesson) => _chip(
    lesson.title,
    'explain ${lesson.aliases.first}',
    Icons.menu_book_rounded,
  );
  static List<Suggestion> _lessonChips(OfflineLesson lesson) => [
    _chip('Quiz me', 'quiz me', Icons.quiz_outlined),
    _chip('Worked example', 'worked example', Icons.calculate_outlined),
    _chip('Explain simply', 'simpler', Icons.lightbulb_outline_rounded),
  ];
  static List<Suggestion> _quizChips() => [
    _chip('Hint', 'hint', Icons.lightbulb_outline_rounded),
    _chip('Show answer', 'show answer', Icons.visibility_outlined),
  ];
}
