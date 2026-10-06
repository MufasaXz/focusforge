import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/local_store.dart';

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

  Future<void> completeOnboarding() =>
      save(state.copyWith(onboardingComplete: true));

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
  ThemePreference build() {
    // Follow the device on a cold install. Most people have already set a
    // system-wide light/dark preference, and opening on the opposite one reads
    // as the app ignoring a choice they made somewhere else.
    return ThemePreference.system;
  }

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
    // A cold start is empty: stats are the user's history, and anything else
    // would make a deleted account "come back" as someone else's numbers on
    // the next launch.
    return const GamificationStats();
  }

  LocalStore get _store => ref.read(localStoreProvider);

  void hydrate(GamificationStats? stored) {
    if (stored != null) state = stored;
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
