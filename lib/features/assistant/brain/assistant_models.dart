import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/utils/format.dart';
import 'reminders.dart';
import 'timetable.dart';

/// A length of time, formatted for the reader's language when shown.
@immutable
class Minutes {
  const Minutes(this.value);
  final int value;

  @override
  bool operator ==(Object other) => other is Minutes && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// A whole number, written in the reader's digits when shown.
@immutable
/// A time of day for a [Copy], written the phone's way.
@immutable
class Clock {
  const Clock(this.minuteOfDay);
  final int minuteOfDay;

  @override
  bool operator ==(Object other) =>
      other is Clock && other.minuteOfDay == minuteOfDay;

  @override
  int get hashCode => minuteOfDay.hashCode;
}

/// A calendar day for a [Copy], written out the phone's way.
@immutable
class Day {
  const Day(this.date);
  final DateTime date;

  @override
  bool operator ==(Object other) => other is Day && other.date == date;

  @override
  int get hashCode => date.hashCode;
}

class Count {
  const Count(this.value);
  final int value;

  @override
  bool operator ==(Object other) => other is Count && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Copy that is translated when it is shown rather than when it is written.
///
/// A reply is built away from any widget, so it carries the English key and
/// its arguments; the bubble resolves them against the live locale. An
/// argument may itself be a [Copy]. [Copy.raw] carries text that is never
/// translated — a subject name, an app name, an exam's proper name.
@immutable
class Copy {
  const Copy(this.key, [this.args = const []]) : raw = false;
  const Copy.raw(this.key) : args = const [], raw = true;

  final String key;
  final List<Object?> args;
  final bool raw;

  String of(BuildContext context) => resolve(AppStrings.of(context));

  String resolve(AppStrings strings) => raw
      ? key
      : strings.text(key, [for (final arg in args) _value(arg, strings)]);

  static Object? _value(Object? arg, AppStrings strings) => switch (arg) {
    Copy() => arg.resolve(strings),
    Minutes() => formatMinutes(arg.value, locale: strings.locale),
    Clock() => formatTimeOfDay(arg.minuteOfDay, locale: strings.locale),
    Day() => formatDate(arg.date, locale: strings.locale),
    Count() => NumberFormat.decimalPattern(
      strings.locale.languageCode,
    ).format(arg.value),
    _ => arg,
  };

  @override
  bool operator ==(Object other) =>
      other is Copy &&
      other.key == key &&
      other.raw == raw &&
      other.args.length == args.length &&
      List.generate(
        args.length,
        (i) => other.args[i] == args[i],
      ).every((e) => e);

  @override
  int get hashCode => Object.hash(key, raw, Object.hashAll(args));

  @override
  String toString() => raw ? key : '$key $args';
}

/// Everything Pip can be asked to do.
enum Act {
  greet,
  intro,
  help,
  plan,
  report,
  distractions,
  lock,
  focusNow,
  examAsk,
  exam,
  examPick,
  examDate,
  motivate,
  tip,
  goal,
  goalSet,
  streak,
  thanks,
  bye,
  unknown,

  // Reminders and the timetable.
  examReminder,
  examReminderOff,
  timetable,
  timetableOff,
  reminder,
  reminders,
  reminderOff,
  leaderboard,

  // Answers to the one-time question about online answers.
  aiAllow,
  aiDecline,

  // Steps that need the screen: a permission, a picker or a tab.
  usageAccess,
  appList,
  openShield,
  openFocus,
  openLeaderboard,
  reminderDate,
}

/// One request: what to do, and what to do it to.
@immutable
class AssistantAction {
  const AssistantAction(this.act, {this.arg, this.value, this.said});

  final Act act;

  /// A subject id, an exam id, an app's package or an app name to find.
  final String? arg;

  /// Minutes, for a goal or a plan length change.
  final int? value;

  /// What the user typed, when the request came from typing.
  final String? said;

  @override
  bool operator ==(Object other) =>
      other is AssistantAction &&
      other.act == act &&
      other.arg == arg &&
      other.value == value;

  @override
  int get hashCode => Object.hash(act, arg, value);

  @override
  String toString() => 'AssistantAction($act, $arg, $value)';
}

/// A tappable follow-up under Pip's reply.
@immutable
class Suggestion {
  const Suggestion(this.label, this.icon, this.action);

  final Copy label;
  final IconData icon;
  final AssistantAction action;
}

/// One subject's time this week against the same days last week.
@immutable
class SubjectTrend {
  const SubjectTrend({
    required this.id,
    required this.name,
    required this.color,
    required this.thisWeek,
    required this.lastWeekSpan,
    required this.today,
    this.weekTarget = 0,
  });

  final String id;
  final String name;
  final Color color;

  /// Minutes from Monday to now.
  final int thisWeek;

  /// Minutes over the same weekdays last week.
  final int lastWeekSpan;
  final int today;

  /// The subject's weekly target in minutes, or 0 when it has none.
  final int weekTarget;

  int get delta => thisWeek - lastWeekSpan;
}

/// An app and its minutes.
@immutable
class AppMinutes {
  const AppMinutes(this.packageId, this.name, this.minutes);

  final String packageId;
  final String name;
  final int minutes;
}

/// One block of a plan.
@immutable
class PlanBlock {
  const PlanBlock({
    required this.subjectId,
    required this.name,
    required this.color,
    required this.minutes,
  });

  final String subjectId;
  final String name;
  final Color color;
  final int minutes;
}

/// Rich content inside one of Pip's bubbles.
sealed class ChatCard {
  const ChatCard();
}

class ReportCard extends ChatCard {
  const ReportCard({
    required this.todayMinutes,
    required this.goalMinutes,
    required this.weekMinutes,
    required this.lastWeekSpanMinutes,
    required this.streak,
    required this.subjects,
    required this.usageReady,
    required this.distractingMinutes,
    required this.topApps,
  });

  final int todayMinutes;
  final int goalMinutes;
  final int weekMinutes;
  final int lastWeekSpanMinutes;
  final int streak;
  final List<SubjectTrend> subjects;
  final bool usageReady;
  final int distractingMinutes;
  final List<AppMinutes> topApps;
}

class PlanCard extends ChatCard {
  const PlanCard({
    required this.blocks,
    required this.breakMinutes,
    required this.todayBySubject,
    required this.doneToday,
  });

  final List<PlanBlock> blocks;
  final int breakMinutes;

  /// What is already done today, so a saved goal counts it.
  final Map<String, int> todayBySubject;
  final int doneToday;

  int get totalMinutes => blocks.fold(0, (sum, b) => sum + b.minutes);
}

class LockCard extends ChatCard {
  const LockCard({required this.apps, required this.preselected});

  final List<AppMinutes> apps;
  final Set<String> preselected;
}

class ExamCard extends ChatCard {
  const ExamCard({required this.examId, required this.isMine});

  final String examId;
  final bool isMine;
}

/// The reminders the user has set, each with a way to remove it.
class RemindersCard extends ChatCard {
  const RemindersCard(this.reminders);

  final List<StudyReminder> reminders;
}

/// A timetable to adjust and save, with each subject's name.
class TimetableCard extends ChatCard {
  const TimetableCard({
    required this.timetable,
    required this.names,
    this.colors = const {},
  });

  final Timetable timetable;

  /// Subject names by id, for the subjects on the timetable and the others
  /// the user can add.
  final Map<String, String> names;
  final Map<String, Color> colors;
}

class GoalCard extends ChatCard {
  const GoalCard({required this.currentMinutes});

  final int currentMinutes;

  static const options = [60, 120, 180, 240, 300, 360, 480];
}

/// Buttons that hand a step to the screen, such as a permission.
class ActionCard extends ChatCard {
  const ActionCard(this.actions);

  final List<Suggestion> actions;
}

/// One thing Pip says: a line, a card, or both.
@immutable
class Say {
  const Say(this.copy, {this.online = false}) : card = null;
  const Say.card(this.card) : copy = null, online = false;

  final Copy? copy;
  final ChatCard? card;

  /// Whether the line came from the online model rather than the phone.
  final bool online;
}

/// Pip's whole answer to one request.
@immutable
class AssistantReply {
  const AssistantReply(
    this.says, {
    this.suggestions = const [],
    this.thinking = const [],
  });

  final List<Say> says;
  final List<Suggestion> suggestions;

  /// Steps to show while Pip works something out. Empty for small talk.
  final List<Copy> thinking;
}

/// Something Pip says from the home screen, and what tapping it does.
@immutable
class BuddyPrompt {
  const BuddyPrompt(this.copy, this.action, {this.happy = false});

  final Copy copy;
  final AssistantAction action;

  /// Good news, which Pip says with a happy wiggle.
  final bool happy;
}
