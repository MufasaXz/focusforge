import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'assistant_models.dart';
import 'study_snapshot.dart';

/// Deterministic coaching, using only the current local snapshot. No model,
/// downloads, telemetry, or network dependencies are involved.
class OfflineCoach {
  const OfflineCoach._();

  static AssistantReply? respond(AssistantAction action, StudySnapshot s) {
    if (!const {
      Act.unknown,
      Act.help,
      Act.plan,
      Act.tip,
      Act.motivate,
      Act.examAsk,
    }.contains(action.act)) {
      return null;
    }
    final text = (action.said ?? '').toLowerCase();
    bool has(List<String> words) => words.any(text.contains);
    final subjects = [...s.subjects]
      ..sort((a, b) {
        final needA = math.max(
          a.weekTarget - a.thisWeek,
          a.lastWeekSpan - a.thisWeek,
        );
        final needB = math.max(
          b.weekTarget - b.thisWeek,
          b.lastWeekSpan - b.thisWeek,
        );
        final result = needB.compareTo(needA);
        return result != 0 ? result : a.today.compareTo(b.today);
      });
    final named = subjects
        .where((v) => text.contains(v.name.toLowerCase()))
        .firstOrNull;
    final subject = named ?? subjects.firstOrNull;
    final topic = subject == null
        ? 'one topic you want to practise'
        : subject.name;
    final lines = <Say>[];
    if (has([
      'spaced repet',
      'forget',
      'remember',
      'memor',
      'yaad',
      'active recall',
      'flashcard',
    ])) {
      lines.add(
        Say(
          Copy.raw(
            'For $topic, close your notes and recall three key ideas. Check what you missed, then make a few question-and-answer cards. Review them tomorrow, in three days, and next week; bring difficult cards back sooner.',
          ),
        ),
      );
    } else if (has([
      'mock test',
      'practice paper',
      'practice test',
      'past paper',
      'mistake',
      'error log',
    ])) {
      lines.add(
        Say(
          Copy.raw(
            'Try a short timed practice set for $topic. Afterward, label each mistake: concept, recall, or rushing. Review the weakest concept and redo two missed questions before starting another set. Check official exam notices for current formats.',
          ),
        ),
      );
    } else if (has([
      'pomodoro',
      'only have',
      'i have ',
      'minutes free',
      'minute plan',
      'hour free',
    ])) {
      final duration = RegExp(r'\b(\d{1,3})\s*(minutes?|mins?|hours?|hrs?)\b')
          .firstMatch(text);
      final supplied = duration == null ? null : int.tryParse(duration[1]!);
      final budget = supplied == null
          ? null
          : supplied * (duration![2]!.startsWith('h') ? 60 : 1);
      if (budget != null && budget <= 0) {
        lines.add(
          const Say(
            Copy(
              'Take a proper break. When you have a few minutes, choose one small topic to revisit.',
            ),
          ),
        );
      } else {
        final total =
            (budget ?? (s.remainingToGoal > 0 ? s.remainingToGoal : 60)).clamp(
              1,
              480,
            );
        final block = s.blockMinutes.clamp(5, 50);
        final rest = s.breakMinutes.clamp(1, 15);
        var left = total;
        final chunks = <String>[];
        var blocks = 0;
        while (left > 0) {
          final study = math.min(block, left);
          chunks.add('$study min study');
          blocks++;
          left -= study;
          if (left > rest) {
            chunks.add('$rest min break');
            left -= rest;
          } else if (left > 0) {
            chunks.add('$left min break');
            left = 0;
          }
        }
        lines.add(
          Say(
            Copy.raw(
              'Use ${budget != null && budget > 480 ? 'the next ' : ''}$total minutes: ${chunks.join(' → ')}. Start with $topic and finish each block by recalling what you learned. That is $blocks study block${blocks == 1 ? '' : 's'}, with breaks included.',
            ),
          ),
        );
      }
    } else if (has([
      'exam tomorrow',
      'exam today',
      'last minute',
      'exam stress',
      'exam anxiety',
    ])) {
      final explicitTomorrow = text.contains('exam tomorrow');
      final explicitToday = text.contains('exam today');
      final days = explicitTomorrow
          ? 1
          : explicitToday
          ? 0
          : s.daysToExam;
      final when = explicitTomorrow
          ? 'For your exam tomorrow'
          : explicitToday
          ? 'For your exam today'
          : days == null
          ? 'If your exam is close'
          : days == 0
          ? 'Your saved exam is today'
          : 'Your saved exam is in $days day${days == 1 ? '' : 's'}';
      lines.add(
        Say(
          Copy.raw(
            '$when: revise familiar material, check a short mistake list, and avoid an all-night catch-up. Pack what you need and leave time to rest. One calm revision block is a useful next step.',
          ),
        ),
      );
    } else if (has([
      'what next',
      'next step',
      'coach me',
      'catch up',
      'falling behind',
      'improve my',
      'study better',
    ])) {
      lines.add(
        Say(
          Copy.raw(
            'You have logged ${s.todayMinutes} focus minutes today and ${s.weekMinutes} this week. ${s.goalMinutes <= 0
                ? 'Set a small daily target you can repeat.'
                : s.remainingToGoal == 0
                ? 'Your daily target is complete; rest or do a light review.'
                : '${s.remainingToGoal} minutes remain toward your daily target.'} ${subject == null ? 'Add subjects for a more specific plan.' : 'Give $topic the next short block, then check your progress again.'}',
          ),
        ),
      );
      if (s.daysToExam case final days?) {
        lines.add(
          Say(
            Copy.raw(
              'Your saved exam countdown is $days day${days == 1 ? '' : 's'}. Reserve revision time before the exam; the countdown uses the date you entered.',
            ),
          ),
        );
      }
    } else if (action.act == Act.unknown) {
      lines.add(
        Say(
          Copy.raw(
            'I can help locally with study plans, subject progress, exam countdowns, reminders, subject explanations, worked maths, and practice quizzes. ${s.todayMinutes > 0 ? 'You have already logged ${s.todayMinutes} focus minutes today.' : 'Start small: one topic and a short focus block.'} Try “I have 40 minutes”, “explain derivatives”, “quiz me on genetics”, or “what next”. My bundled study library may not cover every topic or the latest syllabus.',
          ),
        ),
      );
    } else {
      return null;
    }
    if (s.timerRunning) {
      lines.add(
        const Say(
          Copy(
            'Your focus timer is already running. Finish or pause that block before starting another.',
          ),
        ),
      );
    }
    return AssistantReply(
      lines,
      suggestions: const [
        Suggestion(
          Copy('Plan my study'),
          Icons.event_note_rounded,
          AssistantAction(Act.plan),
        ),
        Suggestion(
          Copy('My report'),
          Icons.insights_rounded,
          AssistantAction(Act.report),
        ),
        Suggestion(
          Copy('Start a block'),
          Icons.play_arrow_rounded,
          AssistantAction(Act.focusNow),
        ),
      ],
    );
  }
}
