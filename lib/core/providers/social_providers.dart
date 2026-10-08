import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/seed.dart';
import '../services/leaderboard_service.dart';
import '../services/study_group_service.dart';
import '../services/local_store.dart';
import 'app_providers.dart';
import 'parent_providers.dart';
import 'shield_providers.dart';
import 'study_providers.dart';

// -- Achievements ------------------------------------------------------------

/// Catalogue ids whose progress can be measured from state the app really
/// keeps.
///
/// The seed catalogue also carries aspirational badges — shields blocked,
/// groups joined, challenges won, strict four-hour blocks, account age — and
/// nothing records any of that yet. They are left out rather than shown: a
/// locked tile no user action can ever move is a goal in name only, and the
/// whole point of the cabinet is that its numbers are true.
const _measurableBadgeIds = <String>{
  'first_focus',
  'week_warrior',
  'century_club',
  'night_owl',
  'early_bird',
  'deep_diver',
  'steady_hand',
  'month_king',
  'hundred_hours',
  'marathon',
  'perfectionist',
  'subject_master',
  'night_shift',
  'breath_master',
};

/// Marks an unlock restored from a store written before timestamps were
/// persisted. The cabinet renders it as "Earned earlier" rather than inventing
/// a date.
final _unknownUnlockTime = DateTime.fromMillisecondsSinceEpoch(0);

/// True when [at] is the unknown-time sentinel above.
bool isUnknownUnlockTime(DateTime? at) => at == _unknownUnlockTime;

class AchievementsNotifier extends Notifier<List<Achievement>> {
  /// Unlock timestamps live under their own key: [StoreKeys.achievements] is
  /// the bool map bootstrap already reads, and widening it to epoch millis
  /// would silently break that read. The dotted name follows the convention of
  /// every other store key and should move into [StoreKeys] with the next
  /// store change.
  static const _unlockedAtKey = 'achievements.unlockedAt';

  @override
  List<Achievement> build() {
    // Every session-derived badge is measured from the session log, not the
    // stats aggregate (see [_recompute]), so the log's own event is the only
    // signal needed for it; subjects and breath events feed the rest. Keeping
    // the wiring here means the timer never has to know badges exist.
    ref.listen(sessionsProvider, (_, _) => refresh());
    ref.listen(subjectsProvider, (_, _) => refresh());
    ref.listen(breathEventsProvider, (_, _) => refresh());

    return [
      for (final badge in SeedData.badges)
        if (_measurableBadgeIds.contains(badge.id)) badge,
    ];
  }

  LocalStore get _store => ref.read(localStoreProvider);

  /// Restores persisted unlocks, then re-measures immediately: bootstrap calls
  /// this after the stats, subjects and session log are in, so the first frame
  /// already shows measured progress rather than zeros.
  void hydrate(Map<String, bool> unlocked) {
    if (unlocked.isNotEmpty) {
      final times = _store.getMap(_unlockedAtKey);
      state = [
        for (final a in state)
          if (unlocked[a.id] == true && !a.unlocked)
            a.copyWith(
              progress: a.target,
              unlockedAt: _restoredTime(times, a.id),
            )
          else
            a,
      ];
    }
    if (_recompute()) unawaited(_persist());
  }

  static DateTime _restoredTime(Map<String, dynamic>? times, String id) {
    final millis = times?[id];
    return millis is int
        ? DateTime.fromMillisecondsSinceEpoch(millis)
        : _unknownUnlockTime;
  }

  /// Re-measures every badge from live state, moves the progress bars and
  /// permanently unlocks whatever is genuinely earned.
  ///
  /// Unlocks are one-way — a badge earned with a 30-day streak stays earned
  /// when the streak later lapses — which is why only the unlock and its
  /// timestamp are persisted and progress is recomputed from state instead.
  Future<void> refresh() async {
    if (!_recompute()) return;
    await _persist();
  }

  /// The synchronous half of [refresh]; true when something was newly unlocked
  /// and therefore needs persisting.
  bool _recompute() {
    // Measured from the session log, never from the stats aggregate: a badge
    // is a claim about the user, and the aggregate is a running total that a
    // cleared log would leave behind.
    final sessions = ref.read(sessionsProvider).toList(growable: false);
    final subjects = ref.read(subjectsProvider);
    final walkedAway = ref
        .read(breathEventsProvider)
        .where((e) => e.walkedAway)
        .length;
    final now = DateTime.now();

    var changed = false;
    var unlockedNew = false;
    final next = <Achievement>[];
    for (final badge in state) {
      if (badge.unlocked) {
        next.add(badge);
        continue;
      }
      final progress = _measure(badge.id, sessions, subjects, walkedAway);
      if (progress == null) {
        next.add(badge);
      } else if (progress >= badge.target) {
        next.add(badge.copyWith(progress: badge.target, unlockedAt: now));
        changed = true;
        unlockedNew = true;
      } else if (progress != badge.progress) {
        next.add(badge.copyWith(progress: progress));
        changed = true;
      } else {
        next.add(badge);
      }
    }

    if (changed) state = next;
    return unlockedNew;
  }

  Future<void> _persist() async {
    final unlocked = state.where((a) => a.unlocked).toList(growable: false);
    await _store.setBoolMap(StoreKeys.achievements, {
      for (final a in unlocked) a.id: true,
    });
    await _store.setMap(_unlockedAtKey, {
      for (final a in unlocked) a.id: a.unlockedAt!.millisecondsSinceEpoch,
    });
  }

  List<Achievement> get unlockedList =>
      state.where((a) => a.unlocked).toList(growable: false);
}

final achievementsProvider =
    NotifierProvider<AchievementsNotifier, List<Achievement>>(
      AchievementsNotifier.new,
    );

final unlockedCountProvider = Provider<int>(
  (ref) => ref.watch(achievementsProvider).where((a) => a.unlocked).length,
);

/// Progress toward the badge with [id], measured from the user's own session
/// log and the state the app really keeps. Returns null for an id nothing can
/// measure — the catalogue only contains [_measurableBadgeIds], so null is a
/// contract violation rather than a case the UI has to handle.
double? _measure(
  String id,
  List<FocusSession> sessions,
  List<Subject> subjects,
  int walkedAway,
) {
  final done = sessions.where((s) => s.completed).toList(growable: false);
  return switch (id) {
    // Every session-derived number comes from the log — totals, streaks,
    // times of day and per-subject splits. The stats aggregate is deliberately
    // not read: it is a running total that a cleared log would leave behind,
    // and a badge unlocked by those would be credit the user never earned.
    'first_focus' => done.isEmpty ? 0.0 : 1.0,
    // The streak is the longest run of consecutive days carrying a completed
    // session. That is the only definition the app can actually keep: nothing
    // in the session path updates the aggregate's streak fields, so pointing
    // these two badges at `stats.longestStreak` made them unreachable goals.
    'week_warrior' || 'month_king' => _longestStreak(done).toDouble(),
    'century_club' || 'hundred_hours' => _completedHours(done),
    'steady_hand' => done.length.toDouble(),
    'night_owl' => done.any((s) => s.startedAt.hour >= 23) ? 1.0 : 0.0,
    'early_bird' => done.any((s) => s.startedAt.hour < 6) ? 1.0 : 0.0,
    'deep_diver' => done.any((s) => s.minutes >= 90) ? 1.0 : 0.0,
    'night_shift' =>
      done.where((s) => s.startedAt.hour >= 23).length.toDouble(),
    'marathon' => _bestDayHours(done),
    'perfectionist' => _subjectTargetFraction(subjects, done),
    'subject_master' => _bestSubjectHours(done),
    'breath_master' => walkedAway.toDouble(),
    _ => null,
  };
}

/// Total hours across [sessions], which the caller has already filtered to
/// completed rows.
double _completedHours(List<FocusSession> sessions) =>
    sessions.fold(0, (sum, s) => sum + s.minutes) / 60;

/// Longest run of consecutive calendar days carrying at least one completed
/// session.
///
/// Derived from the log rather than read from the stats aggregate: the
/// aggregate's streak fields have no writer in the session path, and on a
/// first run they hold the seeder's demo numbers.
int _longestStreak(List<FocusSession> sessions) {
  final days = <DateTime>{
    for (final s in sessions)
      DateTime(s.startedAt.year, s.startedAt.month, s.startedAt.day),
  }.toList()..sort();

  var best = 0;
  var run = 0;
  DateTime? previous;
  for (final day in days) {
    // Compared as calendar dates, not instants: a 23-hour DST day would make
    // `difference().inDays` read as 0 and break the run.
    final consecutive =
        previous != null &&
        day == DateTime(previous.year, previous.month, previous.day + 1);
    run = consecutive ? run + 1 : 1;
    if (run > best) best = run;
    previous = day;
  }
  return best;
}

/// Hours on the user's best single day. Day-level facts can only come from the
/// session log — the stats aggregate does not carry dates.
double _bestDayHours(List<FocusSession> sessions) {
  final byDay = <int, int>{};
  for (final s in sessions) {
    final key =
        s.startedAt.year * 10000 + s.startedAt.month * 100 + s.startedAt.day;
    byDay[key] = (byDay[key] ?? 0) + s.minutes;
  }
  return byDay.values.fold(0, (a, b) => a > b ? a : b) / 60;
}

/// Hours logged in the user's strongest subject, across the whole log.
double _bestSubjectHours(List<FocusSession> sessions) {
  final bySubject = <String, int>{};
  for (final s in sessions) {
    if (s.subjectId.isEmpty) continue;
    bySubject[s.subjectId] = (bySubject[s.subjectId] ?? 0) + s.minutes;
  }
  return bySubject.values.fold(0, (a, b) => a > b ? a : b) / 60;
}

/// Share of this week's subject targets that have been met.
///
/// The week's minutes are summed from [sessions] rather than read from
/// [Subject.weekDone]: the subject counters are a lifetime total, not a weekly
/// one, so trusting them would credit this week with last term's work. The
/// targets themselves are real user settings.
double _subjectTargetFraction(
  List<Subject> subjects,
  List<FocusSession> sessions,
) {
  final tracked = subjects
      .where((s) => s.weekTarget > 0)
      .toList(growable: false);
  if (tracked.isEmpty) return 0;

  // Monday-aligned, matching the subject counters in study_providers.dart.
  final now = DateTime.now();
  final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
  final bySubject = <String, int>{};
  for (final s in sessions) {
    if (s.subjectId.isEmpty || s.startedAt.isBefore(monday)) continue;
    bySubject[s.subjectId] = (bySubject[s.subjectId] ?? 0) + s.minutes;
  }

  final met = tracked
      .where((s) => (bySubject[s.id] ?? 0) / 60 >= s.weekTarget)
      .length;
  return met / tracked.length;
}

// -- Study groups ------------------------------------------------------------

/// The user's own groups.
///
/// A group lives on this device: it holds a name, an icon, a weekly target and
/// a code to share. The hours are the user's real logged time, recomputed from
/// the session log so the bar moves when a session ends rather than on the
/// next launch.
///
/// There is no seeded group. A group nobody joined, with members nobody
/// invited, is not a feature — it is a screenshot.
final studyGroupServiceProvider = Provider<StudyGroupService>(
  (ref) => FirebaseLeaderboardService.isSupported
      ? FirebaseStudyGroupService()
      : const UnavailableStudyGroupService(),
);
final cloudGroupsProvider = StreamProvider<List<StudyGroup>>((ref) {
  final service = ref.watch(studyGroupServiceProvider);
  final uid = ref.watch(accountUidProvider);
  if (!service.available || uid == null || !ref.watch(canUseGroupsProvider)) {
    return Stream.value([]);
  }
  return service.watchGroups(uid);
});
final groupsProvider = Provider<List<StudyGroup>>(
  (ref) => ref.watch(cloudGroupsProvider).valueOrNull ?? [],
);
final groupMembersProvider = StreamProvider.autoDispose
    .family<List<GroupMember>, String>(
      (ref, id) => ref.watch(studyGroupServiceProvider).watchMembers(id),
    );
final canUseGroupsProvider = Provider<bool>(
  (ref) => !ref.watch(userProvider).isAnonymous,
);
final groupClockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 30), (_) => DateTime.now());
});
final groupWeekProvider = Provider<String>(
  (ref) => weekKey(
    (ref.watch(groupClockProvider).valueOrNull ?? DateTime.now()).toUtc(),
  ),
);
final groupWeekMinutesProvider = Provider<int>((ref) {
  final now = ref.watch(groupClockProvider).valueOrNull ?? DateTime.now();
  final utc = now.toUtc();
  final start = DateTime.utc(utc.year, utc.month, utc.day - utc.weekday + 1);
  return ref
      .watch(sessionsProvider)
      .where(
        (s) =>
            s.completed &&
            !s.startedAt.isBefore(start) &&
            !s.startedAt.isAfter(now),
      )
      .fold(0, (sum, s) => sum + s.minutes);
});
final groupSyncErrorProvider = StateProvider<String?>((ref) => null);
final groupPublisherProvider = Provider<void>((ref) {
  var disposed = false;
  var sending = false;
  var queued = false;
  Object? lastPublished;
  ref.onDispose(() => disposed = true);
  Future<void> publish() async {
    if (disposed) return;
    if (sending) {
      queued = true;
      return;
    }
    final service = ref.read(studyGroupServiceProvider);
    if (!service.available || !ref.read(canUseGroupsProvider)) return;
    final groups = ref.read(groupsProvider);
    final timer = ref.read(timerProvider);
    final end = timer.running && timer.phase == TimerPhase.focus
        ? timer.targetEnd
        : null;
    final week = ref.read(groupWeekProvider);
    final minutes = ref.read(groupWeekMinutesProvider).clamp(0, 10080);
    final name = ref.read(userProvider).displayName;
    final payload = (
      ref.read(accountUidProvider),
      groups.map((g) => g.id).join(','),
      week,
      minutes,
      name,
      end,
    );
    if (payload == lastPublished) return;
    sending = true;
    try {
      await Future.wait([
        for (final group in groups)
          service.publish(group.id, week, minutes, name, end),
      ]);
      lastPublished = payload;
      if (!disposed) ref.read(groupSyncErrorProvider.notifier).state = null;
    } catch (_) {
      if (!disposed) {
        ref.read(groupSyncErrorProvider.notifier).state =
            'Your latest progress has not synced. We will retry shortly.';
      }
    } finally {
      sending = false;
      if (queued && !disposed) {
        queued = false;
        unawaited(publish());
      }
    }
  }

  ref.listen(groupsProvider, (_, _) => unawaited(publish()));
  ref.listen(groupWeekMinutesProvider, (_, _) => unawaited(publish()));
  ref.listen(userProvider, (_, _) => unawaited(publish()));
  ref.listen(
    timerProvider.select((t) => (t.running, t.phase, t.targetEnd)),
    (_, _) => unawaited(publish()),
  );
  ref.listen(groupClockProvider, (_, _) => unawaited(publish()));
  unawaited(publish());
});

// -- Leaderboard -------------------------------------------------------------

/// Hours of completed focus logged since Monday 00:00 local — the span the
/// subject rings and the heatmap call "this week".
///
/// Deliberately not [weekTotalHoursProvider]: that one is a rolling
/// last-seven-days window, so reading it under a "This week" label put the
/// board and the rest of the app on different weeks.
final leaderboardWeekHoursProvider = Provider<double>((ref) {
  final now = DateTime.now();
  final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
  var minutes = 0;
  for (final session in ref.watch(sessionsProvider)) {
    if (!session.completed) continue;
    if (session.startedAt.isBefore(monday)) continue;
    minutes += session.minutes;
  }
  return minutes / 60;
});

/// The same window, one week earlier — the only honest comparison the app can
/// draw without a server, because it is against the user's own history.
final previousWeekHoursProvider = Provider<double>((ref) {
  final now = DateTime.now();
  final thisMonday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
  final lastMonday = DateTime(
    thisMonday.year,
    thisMonday.month,
    thisMonday.day - 7,
  );

  var minutes = 0;
  for (final session in ref.watch(sessionsProvider)) {
    if (!session.completed) continue;
    final at = session.startedAt;
    if (at.isBefore(lastMonday) || !at.isBefore(thisMonday)) continue;
    minutes += session.minutes;
  }
  return minutes / 60;
});

/// Completed sessions logged this week.
final weekSessionCountProvider = Provider<int>((ref) {
  final now = DateTime.now();
  final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
  return ref
      .watch(sessionsProvider)
      .where((s) => s.completed && !s.startedAt.isBefore(monday))
      .length;
});

/// The board for the selected scope.
///
/// Real rows from the backend, mine marked. Empty when nothing has been
/// published — a board with nobody on it is a real state, and inventing a
/// rival is the one kind of demo data a user cannot tell from a real one.
final leaderboardProvider = Provider<List<LeaderboardEntry>>((ref) {
  final rows = ref.watch(weekBoardProvider).value ?? const <BoardRow>[];
  final myUid = ref.watch(accountUidProvider);
  return [
    for (final row in rows)
      LeaderboardEntry(
        name: row.name,
        hours: row.minutes / 60,
        isMe: myUid != null && row.uid == myUid,
      ),
  ];
});

/// The signed-in user's row, wherever they are in the list.
final myRankProvider = Provider<LeaderboardEntry?>(
  (ref) => ref.watch(leaderboardProvider).where((e) => e.isMe).firstOrNull,
);

/// The backend the board is read from and written to.
final leaderboardServiceProvider = Provider<LeaderboardService>((ref) {
  final service = FirebaseLeaderboardService.isSupported
      ? FirebaseLeaderboardService()
      : const UnavailableLeaderboardService();
  ref.onDispose(service.dispose);
  return service;
});

/// Whether the user has chosen to appear on the board.
///
/// Off by default, and off means nothing is written: publishing a study
/// record under someone's name is not something to opt out of afterwards.
class BoardOptInNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  LocalStore get _store => ref.read(localStoreProvider);

  void hydrate(bool? stored) => state = stored ?? false;

  Future<void> set(bool value) async {
    state = value;
    await _store.setBool(StoreKeys.boardOptIn, value);
  }
}

final boardOptInProvider = NotifierProvider<BoardOptInNotifier, bool>(
  BoardOptInNotifier.new,
);

/// This week's board key. Fixed for the run — a week that turns over while the
/// app is open is a detail the next launch handles.
final currentWeekKeyProvider = Provider<String>(
  (ref) => weekKey(DateTime.now()),
);

/// This week's rows, best first.
final weekBoardProvider = StreamProvider<List<BoardRow>>((ref) {
  final service = ref.watch(leaderboardServiceProvider);
  if (!service.available) return Stream.value(const <BoardRow>[]);
  return service.watch(ref.watch(currentWeekKeyProvider));
});

/// Keeps this device's row in step with the week it has actually studied.
///
/// Publishing is not a one-off: the row is rewritten as sessions land, and
/// withdrawn the moment the switch goes off, so leaving the board is
/// immediate rather than at the end of the week.
final leaderboardPublisherProvider = Provider<void>((ref) {
  Future<void> publish() async {
    final service = ref.read(leaderboardServiceProvider);
    final uid = ref.read(accountUidProvider);
    if (!service.available || uid == null) return;
    if (!ref.read(boardOptInProvider)) return;

    final minutes = (ref.read(leaderboardWeekHoursProvider) * 60).round();
    // A row reading 0m is not a standing; it is an absence with a name on it.
    if (minutes <= 0) return;

    final name = ref.read(userProvider).displayName.trim();
    await service.publish(
      week: ref.read(currentWeekKeyProvider),
      uid: uid,
      name: name.isEmpty ? 'A student' : name,
      minutes: minutes,
    );
  }

  Future<void> withdraw() async {
    final service = ref.read(leaderboardServiceProvider);
    final uid = ref.read(accountUidProvider);
    if (!service.available || uid == null) return;
    await service.withdraw(ref.read(currentWeekKeyProvider), uid);
  }

  ref.listen(sessionsProvider, (previous, next) => unawaited(publish()));
  ref.listen(boardOptInProvider, (previous, next) {
    unawaited(next ? publish() : withdraw());
  });
  unawaited(publish());
});

// -- Notifications -----------------------------------------------------------

class NotificationsNotifier extends Notifier<NotificationPrefs> {
  @override
  NotificationPrefs build() => SeedData.notifications;

  LocalStore get _store => ref.read(localStoreProvider);

  void hydrate(Map<String, dynamic>? stored) {
    if (stored != null) state = NotificationPrefs.fromJson(stored);
  }

  Future<void> _persist() =>
      _store.setMap(StoreKeys.notifications, state.toJson());

  Future<void> update(NotificationPrefs next) async {
    state = next;
    await _persist();
  }

  Future<void> setQuietHours({int? start, int? end, bool? enabled}) async {
    state = state.copyWith(
      quietStartHour: start,
      quietEndHour: end,
      quietHoursEnabled: enabled,
    );
    await _persist();
  }
}

final notificationsProvider =
    NotifierProvider<NotificationsNotifier, NotificationPrefs>(
      NotificationsNotifier.new,
    );
