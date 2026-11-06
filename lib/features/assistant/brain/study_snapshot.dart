import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/providers/goal_planner_providers.dart';
import '../../../core/providers/shield_providers.dart';
import '../../../core/providers/social_providers.dart';
import '../../../core/providers/study_providers.dart';
import '../../../core/providers/usage_providers.dart';
import '../../../core/providers/usage_stats_providers.dart';
import '../../../core/services/app_catalog.dart';
import '../../../core/services/native_shield_service.dart';
import '../assistant_memory.dart';
import 'assistant_models.dart';

/// Reads a provider once. Both `Ref.read` and `WidgetRef.read` fit.
typedef Reader = T Function<T>(ProviderListenable<T> provider);

/// Whether this device can read screen time and close apps.
final appBlockingSupportedProvider = Provider<bool>(
  (ref) => NativeShieldService.isSupported,
);

/// Everything Pip looks at to answer, read at one moment.
///
/// Built from the same stores the screens read, so Pip can never disagree
/// with the ring, the chart or the Shield list.
@immutable
class StudySnapshot {
  const StudySnapshot({
    required this.now,
    this.name = '',
    this.todayMinutes = 0,
    this.goalMinutes = 0,
    this.defaultGoalMinutes = 0,
    this.streak = 0,
    this.timerRunning = false,
    this.blockMinutes = 25,
    this.breakMinutes = 5,
    this.subjects = const [],
    this.todayBySubject = const {},
    this.weekMinutes = 0,
    this.lastWeekSpanMinutes = 0,
    this.lastWeekMinutes = 0,
    this.dayparts = const [0, 0, 0, 0],
    this.sessionsToday = 0,
    this.android = false,
    this.appListConsent = false,
    this.usageAccess = false,
    this.distracting = const [],
    this.distractingInstalled = const [],
    this.installed = const [],
    this.reached = 0,
    this.walkedAway = 0,
    this.lockedPackages = const {},
    this.memory = const AssistantMemory(),
    this.hasHistory = false,
    this.boardRank,
    this.boardJoined = false,
    this.boardMinutes = 0,
    this.boardBehind,
    this.boardSize = 0,
  });

  final DateTime now;
  final String name;
  final int todayMinutes;

  /// Today's goal from the goal planner, or 0 when none is set.
  final int goalMinutes;

  /// The daily goal setting, used as a starting size for a plan.
  final int defaultGoalMinutes;
  final int streak;
  final bool timerRunning;

  /// The current focus block length.
  final int blockMinutes;
  final int breakMinutes;
  final List<SubjectTrend> subjects;

  /// Minutes per subject id today. Untagged time is under ''.
  final Map<String, int> todayBySubject;

  /// Monday to now.
  final int weekMinutes;

  /// The same weekdays last week.
  final int lastWeekSpanMinutes;
  final int lastWeekMinutes;

  /// Minutes over the last four weeks in the morning, afternoon, evening and
  /// night.
  final List<int> dayparts;
  final int sessionsToday;
  final bool android;
  final bool appListConsent;
  final bool usageAccess;

  /// Today's distracting apps, busiest first.
  final List<AppMinutes> distracting;

  /// Installed apps that count as distracting, for locking with no usage.
  final List<AppMinutes> distractingInstalled;

  /// Apps the user could name, for "lock Instagram".
  final List<AppMinutes> installed;

  /// Times today the user opened a blocked app, and times they walked away.
  final int reached;
  final int walkedAway;
  final Set<String> lockedPackages;
  final AssistantMemory memory;

  /// Whether this account has ever logged a session.
  final bool hasHistory;

  /// The user's place on this week's leaderboard, 1 for the top, when they
  /// chose to appear on it.
  final int? boardRank;

  /// Whether the user chose to appear on the leaderboard.
  final bool boardJoined;

  /// The user's minutes on this week's board.
  final int boardMinutes;

  /// Minutes short of the person one place up, when there is one.
  final int? boardBehind;

  /// How many people are on this week's board.
  final int boardSize;

  bool get usageReady => android && appListConsent && usageAccess;

  int get distractingMinutes =>
      distracting.fold(0, (sum, a) => sum + a.minutes);

  int get remainingToGoal =>
      goalMinutes <= 0 ? 0 : (goalMinutes - todayMinutes).clamp(0, goalMinutes);

  /// Whole days until the saved exam date, or null with no date or a past one.
  int? get daysToExam {
    final date = memory.examDate;
    if (date == null) return null;
    final today = DateTime(now.year, now.month, now.day);
    final days = DateTime(
      date.year,
      date.month,
      date.day,
    ).difference(today).inHours;
    final whole = (days / 24).round();
    return whole < 0 ? null : whole;
  }

  /// Reads what is already loaded, without waiting for the platform.
  static ({bool joined, int? rank, int minutes, int? behind, int size}) _board(
    Reader read,
  ) {
    if (!read(boardOptInProvider)) {
      return (joined: false, rank: null, minutes: 0, behind: null, size: 0);
    }
    final rows = read(leaderboardProvider);
    final index = rows.indexWhere((e) => e.isMe);
    if (index < 0) {
      return (
        joined: true,
        rank: null,
        minutes: 0,
        behind: null,
        size: rows.length,
      );
    }
    final mine = (rows[index].hours * 60).round();
    return (
      joined: true,
      rank: index + 1,
      minutes: mine,
      behind: index == 0
          ? null
          : math.max(1, (rows[index - 1].hours * 60).round() - mine),
      size: rows.length,
    );
  }

  static StudySnapshot capture(Reader read, {DateTime? now}) => _build(
    read,
    now: now ?? DateTime.now(),
    android: read(appBlockingSupportedProvider),
    access: read(usageAccessProvider).valueOrNull ?? false,
    usage: read(appUsageTodayProvider).valueOrNull,
    installed: read(installedAppsProvider).valueOrNull,
  );

  /// Waits briefly for screen time and the app list, then reads everything.
  static Future<StudySnapshot> gather(Reader read, {DateTime? now}) async {
    Future<T?> soft<T>(Future<T> future) async {
      try {
        return await future.timeout(const Duration(seconds: 3));
      } catch (_) {
        return null;
      }
    }

    final android = read(appBlockingSupportedProvider);
    final consent = read(appListConsentProvider);
    final access =
        android && (await soft(read(usageAccessProvider.future)) ?? false);
    final usage = consent && access
        ? await soft(read(appUsageTodayProvider.future))
        : null;
    final installed = consent
        ? await soft(read(installedAppsProvider.future))
        : null;
    return _build(
      read,
      now: now ?? DateTime.now(),
      android: android,
      access: access,
      usage: usage,
      installed: installed,
    );
  }

  static StudySnapshot _build(
    Reader read, {
    required DateTime now,
    required bool android,
    required bool access,
    required Map<String, int>? usage,
    required List<InstalledApp>? installed,
  }) {
    final today = read(focusCalendarDateProvider);
    final sessions = read(sessionsProvider);
    final subjects = read(subjectsProvider);
    final timer = read(timerProvider);
    final presets = read(presetsProvider);
    final preset = presets.isEmpty
        ? null
        : presets[timer.presetIndex.clamp(0, presets.length - 1)];

    final monday = weekStart(today);
    final tomorrow = addDays(today, 1);
    final lastMonday = addDays(monday, -7);
    final lastSpanEnd = addDays(lastMonday, today.weekday);
    final fourWeeks = addDays(today, -27);

    final thisWeek = <String, int>{};
    final lastSpan = <String, int>{};
    final todayBy = <String, int>{};
    final dayparts = [0, 0, 0, 0];
    var week = 0, lastWeekSpan = 0, lastWeek = 0, sessionsToday = 0;
    for (final s in sessions) {
      if (!s.completed) continue;
      final at = s.startedAt;
      final m = s.minutes;
      bool within(DateTime from, DateTime until) =>
          !at.isBefore(from) && at.isBefore(until);
      if (within(monday, tomorrow)) {
        thisWeek.update(s.subjectId, (v) => v + m, ifAbsent: () => m);
        week += m;
      }
      if (within(lastMonday, lastSpanEnd)) {
        lastSpan.update(s.subjectId, (v) => v + m, ifAbsent: () => m);
        lastWeekSpan += m;
      }
      if (within(lastMonday, monday)) lastWeek += m;
      if (within(today, tomorrow)) {
        todayBy.update(s.subjectId, (v) => v + m, ifAbsent: () => m);
        sessionsToday++;
      }
      if (within(fourWeeks, tomorrow)) dayparts[_daypart(at.hour)] += m;
    }

    final trends = [
      for (final subject in subjects)
        SubjectTrend(
          id: subject.id,
          name: subject.name,
          color: subject.color,
          thisWeek: thisWeek[subject.id] ?? 0,
          lastWeekSpan: lastSpan[subject.id] ?? 0,
          today: todayBy[subject.id] ?? 0,
          weekTarget: (subject.weekTarget * 60).round(),
        ),
    ];

    var distracting = const <AppMinutes>[];
    var distractingInstalled = const <AppMinutes>[];
    var named = const <AppMinutes>[];
    if (usage != null || installed != null) {
      final classifier = read(usageClassifierProvider);
      final names = {
        for (final app in installed ?? const <InstalledApp>[])
          app.packageId: app.name,
      };
      String nameOf(String id) => names[id] ?? classifier.nameOf(id);
      if (usage != null) {
        distracting = [
          for (final entry
              in classifier.select(usage, UsageCategory.distracting).entries)
            AppMinutes(entry.key, nameOf(entry.key), entry.value),
        ]..sort((a, b) => b.minutes.compareTo(a.minutes));
      }
      if (installed != null) {
        named = [
          for (final app in installed)
            if (!app.isSystem) AppMinutes(app.packageId, app.name, 0),
        ];
        distractingInstalled = [
          for (final app in named)
            if (classifier.categoryOf(app.packageId) ==
                UsageCategory.distracting)
              app,
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      }
    }

    var reached = 0, walkedAway = 0;
    for (final event in read(breathEventsProvider)) {
      if (!event.at.isBefore(today) && event.at.isBefore(tomorrow)) {
        reached++;
        if (event.walkedAway) walkedAway++;
      }
    }

    final board = _board(read);
    return StudySnapshot(
      now: now,
      name: read(userProvider).firstName,
      todayMinutes: read(liveFocusSecondsTodayProvider) ~/ 60,
      goalMinutes: read(activeFocusGoalProvider)?.totalMinutes ?? 0,
      defaultGoalMinutes: read(dailyGoalProvider).forWeekday(today.weekday),
      streak: read(currentStreakProvider),
      timerRunning: timer.running,
      blockMinutes: preset == null || preset.isRandomFocus
          ? 45
          : preset.focus.clamp(10, 120),
      breakMinutes: preset?.shortBreak ?? 5,
      subjects: trends,
      todayBySubject: todayBy,
      weekMinutes: week,
      lastWeekSpanMinutes: lastWeekSpan,
      lastWeekMinutes: lastWeek,
      dayparts: dayparts,
      sessionsToday: sessionsToday,
      android: android,
      appListConsent: read(appListConsentProvider),
      usageAccess: access,
      distracting: distracting,
      distractingInstalled: distractingInstalled,
      installed: named,
      reached: reached,
      walkedAway: walkedAway,
      lockedPackages: {
        for (final entry in read(whitelistProvider))
          if (entry.packageId != null && entry.tier.isEnforced)
            entry.packageId!,
      },
      memory: read(assistantMemoryProvider),
      hasHistory: sessions.isNotEmpty,
      boardRank: board.rank,
      boardJoined: board.joined,
      boardMinutes: board.minutes,
      boardBehind: board.behind,
      boardSize: board.size,
    );
  }

  static int _daypart(int hour) => switch (hour) {
    >= 5 && < 12 => 0,
    >= 12 && < 17 => 1,
    >= 17 && < 22 => 2,
    _ => 3,
  };
}
