import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/seed.dart';
import '../services/local_store.dart';
import 'app_providers.dart';
import 'shield_providers.dart';
import 'study_providers.dart';

// -- Prototype history -------------------------------------------------------
//
// `UserNotifier._installPrototypeHistory` seeds two weeks of demo sessions on
// a first run so the dashboard has something to show. That is a designed demo
// affordance for the charts; it is not the user's work, and neither an
// achievement nor a leaderboard place may claim it. Both the badge recompute
// and the board therefore filter these rows out.

/// The prefix the first-run seeder mints prototype session ids with —
/// `proto-<daysAgo>-<i>`. Real sessions are `s-<micros>` (see `TimerNotifier`),
/// so the shape is a durable marker in the data, not a flag a real row could
/// also carry. Duplicated from app_providers.dart, where the constant is
/// private.
const _prototypeSessionPrefix = 'proto-';

bool _isPrototypeSession(FocusSession session) =>
    session.id.startsWith(_prototypeSessionPrefix);

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
        if (_measurableBadgeIds.contains(badge.id))
          // Seed progress is demo content, not this user's history. Strip it
          // so not even the first frame can show a fabricated bar; [refresh]
          // fills in the measured value.
          badge.copyWith(progress: 0),
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
    // Demo rows from the first-run seeder are dropped before anything is
    // measured: an achievement is a claim about the user, and the prototype
    // history is not the user's work. The stats aggregate is deliberately not
    // read either — on a first run it holds the seeder's demo numbers, so a
    // badge measured from it could unlock for study that never happened.
    final sessions = ref
        .read(sessionsProvider)
        .where((s) => !_isPrototypeSession(s))
        .toList(growable: false);
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
    // not read: it carries the prototype seeder's demo values on a first run,
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
/// [Subject.weekDone]: the subject counters are derived from the whole log,
/// demo rows included, so trusting them would let prototype history complete a
/// real achievement. The targets themselves are real user settings.
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

final groupsProvider = Provider<List<StudyGroup>>((_) => SeedData.groups);

/// Groups are the one feature gated behind a real account.
final canUseGroupsProvider = Provider<bool>(
  (ref) => !ref.watch(userProvider).isAnonymous,
);

// -- Leaderboard -------------------------------------------------------------

class LeaderboardScopeNotifier extends Notifier<LeaderboardScope> {
  /// Persisted under a dotted key like every other store entry; this should
  /// become a [StoreKeys] constant with the next store change.
  static const _scopeKey = 'leaderboard.scope';

  @override
  LeaderboardScope build() {
    // Read straight from the store: the scope is only needed once the
    // leaderboard screen opens, so there is no first-frame value to protect
    // and no reason to depend on bootstrap's hydrate call being wired.
    return _parse(ref.read(localStoreProvider).getString(_scopeKey));
  }

  LocalStore get _store => ref.read(localStoreProvider);

  /// Restores a persisted scope; exposed for bootstrap.
  void hydrate(String? stored) {
    final parsed = _parseOrNull(stored);
    if (parsed != null) state = parsed;
  }

  Future<void> set(LeaderboardScope scope) async {
    state = scope;
    await _store.setString(_scopeKey, scope.name);
  }

  static LeaderboardScope _parse(String? stored) =>
      _parseOrNull(stored) ?? LeaderboardScope.friends;

  static LeaderboardScope? _parseOrNull(String? stored) =>
      LeaderboardScope.values.where((s) => s.name == stored).firstOrNull;
}

final leaderboardScopeProvider =
    NotifierProvider<LeaderboardScopeNotifier, LeaderboardScope>(
      LeaderboardScopeNotifier.new,
    );

/// Hours of completed, non-prototype focus logged since Monday 00:00 local —
/// the span the subject rings and the heatmap call "this week".
///
/// Deliberately not [weekTotalHoursProvider]: that one is a rolling
/// last-seven-days window, so reading it under a "This week" label put the
/// board and the rest of the app on different weeks. Prototype demo rows are
/// excluded for the same reason the badge recompute drops them — a standing is
/// a claim about the user.
final leaderboardWeekHoursProvider = Provider<double>((ref) {
  final now = DateTime.now();
  final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
  var minutes = 0;
  for (final session in ref.watch(sessionsProvider)) {
    if (!session.completed || _isPrototypeSession(session)) continue;
    if (session.startedAt.isBefore(monday)) continue;
    minutes += session.minutes;
  }
  return minutes / 60;
});

/// The board for the selected scope.
///
/// Every row but the user's is [SeedData] sample content — there is no backend
/// to supply friends or global standings, and the screen says so. The user's
/// row is real: it is measured over the current Monday-aligned week, inserted
/// at the rank those hours actually earn, and omitted at zero so a fresh
/// install — including one whose log holds only prototype demo history — is
/// never handed a standing it has not earned.
final leaderboardProvider = Provider<List<LeaderboardEntry>>((ref) {
  final scope = ref.watch(leaderboardScopeProvider);
  final myHours = ref.watch(leaderboardWeekHoursProvider);
  final displayName = ref.watch(userProvider).displayName.trim();

  final sample = switch (scope) {
    LeaderboardScope.friends => SeedData.leaderboard,
    LeaderboardScope.group =>
      SeedData.leaderboard.take(5).toList(growable: false),
    LeaderboardScope.global => _globalSample,
  };

  final rows = [
    for (final entry in sample)
      if (!entry.isMe) entry,
  ];

  if (myHours > 0) {
    rows.add(
      LeaderboardEntry(
        name: displayName.isEmpty ? 'You' : displayName,
        hours: myHours,
        isMe: true,
      ),
    );
    rows.sort((a, b) => b.hours.compareTo(a.hours));
  }
  return rows;
});

/// Sample global standings, pending the backend. See [leaderboardProvider].
const _globalSample = <LeaderboardEntry>[
  LeaderboardEntry(name: 'Kenji A.', hours: 31.4),
  LeaderboardEntry(name: 'Marta L.', hours: 29.8),
  LeaderboardEntry(name: 'Sarah K.', hours: 27.2),
  LeaderboardEntry(name: 'Omar F.', hours: 24.1),
  LeaderboardEntry(name: 'Mike R.', hours: 21.5),
  LeaderboardEntry(name: 'Emma T.', hours: 20.2),
  LeaderboardEntry(name: 'Luna S.', hours: 18.4),
];

/// The signed-in user's row, wherever they are in the list.
final myRankProvider = Provider<LeaderboardEntry?>(
  (ref) => ref.watch(leaderboardProvider).where((e) => e.isMe).firstOrNull,
);

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
