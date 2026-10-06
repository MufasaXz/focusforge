import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/seed.dart';
import '../services/auth_service.dart';
import '../services/local_store.dart';
// Import cycle, deliberate and harmless in Dart: the prototype-history seeder
// below needs the session store, and the session store needs the local store.
import 'study_providers.dart';

/// The open [LocalStore]. Overridden in `bootstrap()` once the plugin has
/// resolved — a provider that throws until then keeps the async gap honest
/// rather than letting a half-built store leak into the tree.
final localStoreProvider = Provider<LocalStore>(
  (ref) => throw StateError(
    'localStoreProvider must be overridden in ProviderScope — see bootstrap()',
  ),
);

final authServiceProvider = Provider<AuthService>(
  (ref) => LocalAuthService(ref.watch(localStoreProvider)),
);

/// Store key for the one-shot prototype-history marker.
///
/// The demo history exists to make a first run look alive, so it is installed
/// at most once per install; this records that it has been. Dotted by
/// convention like the other ad-hoc keys (`achievements.unlockedAt`,
/// `leaderboard.scope`) — it should move into [StoreKeys] with the next store
/// change.
const prototypeHistorySeededKey = 'onboarding.prototypeSeeded';

// -- Account -----------------------------------------------------------------

class UserNotifier extends Notifier<UserProfile> {
  @override
  UserProfile build() {
    // A cold install starts as a blank, un-onboarded profile — which is what
    // makes the router send the user to /onboarding. bootstrap() replaces this
    // with the persisted profile before the first frame on every later launch.
    return const UserProfile();
  }

  LocalStore get _store => ref.read(localStoreProvider);

  /// Called during bootstrap with whatever the auth service restored.
  void hydrate(UserProfile? stored) {
    if (stored != null) state = stored;
  }

  Future<void> save(UserProfile profile) async {
    state = profile;
    await _store.setMap(StoreKeys.user, profile.toJson());
  }

  Future<void> setDisplayName(String name) =>
      save(state.copyWith(displayName: name.trim()));

  Future<void> setPersona(Persona persona) =>
      save(state.copyWith(persona: persona));

  Future<void> setDailyGoal(int minutes) =>
      save(state.copyWith(dailyGoalMinutes: minutes));

  Future<void> completeOnboarding() async {
    await save(state.copyWith(onboardingComplete: true));
    await _installPrototypeHistory();
  }

  /// Fills in a few weeks of representative history so the dashboard has
  /// something to show on a first run.
  ///
  /// This is a **prototype affordance**, not product behaviour: a real build
  /// would start every chart at zero and earn its data. It lives here, behind
  /// one clearly named call, so that deleting it later is a one-line change
  /// rather than an archaeology exercise. Nothing it writes is ever sent
  /// anywhere.
  ///
  /// Installed at most once per install. [completeOnboarding] runs again on
  /// every "Replay onboarding", and appending a second copy of the log each
  /// time doubled the charts and clobbered earned XP with the seed aggregate;
  /// the marker makes the write one-shot, and the replacement below keeps a
  /// half-written install from duplicating rows.
  Future<void> _installPrototypeHistory() async {
    final store = ref.read(localStoreProvider);
    // A replay — or the onboarding that follows an account deletion, which
    // re-arms this marker — must leave the user's real progress untouched.
    if (store.getBool(prototypeHistorySeededKey) == true) return;

    final existing = ref.read(sessionsProvider);
    final isFirstRun =
        !existing.any((s) => !_isPrototypeSession(s)) &&
        _isPrototypeAggregate(ref.read(statsProvider));
    if (!isFirstRun) {
      // An install that already holds user work predates the marker: adopt it
      // as seeded so no later replay can seed over it.
      await store.setBool(prototypeHistorySeededKey, true);
      return;
    }

    // Only a prototype-safe aggregate is written; anything else was either
    // earned by the user or deliberately cleared.
    await ref
        .read(statsProvider.notifier)
        .hydratePrototypeHistory(SeedData.stats);

    final now = DateTime.now();
    final subjects = SeedData.subjects;
    final seeded = <FocusSession>[
      for (var daysAgo = 0; daysAgo < 14; daysAgo++)
        for (var i = 0; i < 3; i++)
          FocusSession(
            id: '$_prototypeSessionPrefix$daysAgo-$i',
            subjectId: subjects[(daysAgo + i) % subjects.length].id,
            startedAt: now.subtract(Duration(days: daysAgo, hours: 3 + i * 2)),
            minutes: 25 + (i * 10),
          ),
    ];

    // Replace, never append: drop any prototype rows a previous run left
    // behind before the fresh set goes in. `hydrate` is the only public write
    // path on the session store and it does not persist, so the store is
    // written alongside it to keep memory and disk in step.
    final next = [...existing.where((s) => !_isPrototypeSession(s)), ...seeded];
    final encoded = [for (final s in next) s.toJson()];
    ref.read(sessionsProvider.notifier).hydrate(encoded);
    await store.setList(StoreKeys.sessions, encoded);

    await store.setBool(prototypeHistorySeededKey, true);
  }

  /// Resets onboarding so the flow can be replayed from Profile.
  Future<void> replayOnboarding() =>
      save(state.copyWith(onboardingComplete: false));
}

final userProvider = NotifierProvider<UserNotifier, UserProfile>(
  UserNotifier.new,
);

// -- Theme -------------------------------------------------------------------

class ThemeNotifier extends Notifier<ThemePreference> {
  @override
  ThemePreference build() => ThemePreference.light;

  void hydrate(String? stored) => state = ThemePreference.fromName(stored);

  Future<void> set(ThemePreference pref) async {
    state = pref;
    await ref.read(localStoreProvider).setString(StoreKeys.theme, pref.name);
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemePreference>(
  ThemeNotifier.new,
);

/// The [ThemeMode] the MaterialApp should use. A tiny derived provider so the
/// root widget rebuilds on theme changes and nothing else does.
final themeModeProvider = Provider<ThemeMode>(
  (ref) => ref.watch(themeProvider).mode,
);

// -- Gamification ------------------------------------------------------------

class StatsNotifier extends Notifier<GamificationStats> {
  @override
  GamificationStats build() {
    // A cold start is empty, not the demo aggregate: stats are the user's
    // history, and defaulting to SeedData.stats made a deleted account "come
    // back" as the seed numbers on the next launch. The prototype seeder
    // installs the demo values explicitly, once, on a first run.
    return const GamificationStats();
  }

  LocalStore get _store => ref.read(localStoreProvider);

  void hydrate(GamificationStats? stored) {
    if (stored != null) state = stored;
  }

  /// See `UserNotifier._installPrototypeHistory` — prototype-only.
  Future<void> hydratePrototypeHistory(GamificationStats stats) async {
    state = stats;
    await _persist();
  }

  Future<void> _persist() => _store.setMap(StoreKeys.stats, state.toJson());

  /// Awards XP and rolls levels. Returns how many levels were gained so the
  /// caller can decide whether a celebration is warranted.
  Future<int> award(int xp) async {
    final before = state.level;
    state = state.withXp(xp);
    await _persist();
    return state.level - before;
  }

  Future<void> recordSession({
    required int minutes,
    required bool completed,
  }) async {
    state = state.copyWith(
      totalSessions: state.totalSessions + 1,
      totalFocusHours: state.totalFocusHours + minutes / 60,
    );
    if (completed) await award(minutes);
    await _persist();
  }

  Future<void> setStreak(int days) async {
    state = state.copyWith(
      currentStreak: days,
      longestStreak: days > state.longestStreak ? days : state.longestStreak,
    );
    await _persist();
  }
}

final statsProvider = NotifierProvider<StatsNotifier, GamificationStats>(
  StatsNotifier.new,
);

// -- Prototype-history helpers ------------------------------------------------
//
// See `UserNotifier._installPrototypeHistory`. The prefix is how a later
// install recognises the demo rows a previous run wrote so it can replace
// rather than append them.

const _prototypeSessionPrefix = 'proto-';

bool _isPrototypeSession(FocusSession session) =>
    session.id.startsWith(_prototypeSessionPrefix);

/// True while the aggregate holds only prototype-safe content — the all-zero
/// cold start or the seed demo values — and may therefore be (re)written by
/// the first-run seeder. Anything else was earned by the user or deliberately
/// cleared, and must be left alone.
bool _isPrototypeAggregate(GamificationStats stats) {
  final empty =
      stats.xp == 0 &&
      stats.totalFocusHours == 0 &&
      stats.totalSessions == 0 &&
      stats.currentStreak == 0 &&
      stats.longestStreak == 0;
  if (empty) return true;
  final seed = SeedData.stats;
  return stats.xp == seed.xp &&
      stats.level == seed.level &&
      stats.currentStreak == seed.currentStreak &&
      stats.longestStreak == seed.longestStreak &&
      stats.totalFocusHours == seed.totalFocusHours &&
      stats.totalSessions == seed.totalSessions;
}
