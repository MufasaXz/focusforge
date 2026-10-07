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

  /// Sets the avatar. A null [icon] is the "use my initials" choice rather
  /// than a missing value, so it is passed through as a deliberate clear.
  Future<void> setAvatar({String? icon, int? color}) => save(
    state.copyWith(
      avatarIcon: icon,
      avatarColor: color,
      clearAvatar: icon == null,
    ),
  );

  Future<void> completeOnboarding() =>
      save(state.copyWith(onboardingComplete: true));
}

final userProvider = NotifierProvider<UserNotifier, UserProfile>(
  UserNotifier.new,
);

// -- Theme -------------------------------------------------------------------

class ThemeSettingsNotifier extends Notifier<ThemeSettings> {
  @override
  ThemeSettings build() {
    // Follow the device on a cold install. Most people have already set a
    // system-wide light/dark preference, and opening on the opposite one reads
    // as the app ignoring a choice they made somewhere else. The palette and
    // AMOLED defaults are the ones the app shipped with, so an untouched
    // install looks exactly as it did before the picker existed.
    return const ThemeSettings();
  }

  LocalStore get _store => ref.read(localStoreProvider);

  /// Called during bootstrap with whatever was persisted.
  ///
  /// The three keys are read separately because they were written separately —
  /// the mode predates the other two, and an install that has only ever set
  /// the mode must keep it rather than be reset to the defaults.
  void hydrate(String? mode, String? palette, bool? amoled) {
    state = ThemeSettings(
      mode: ThemePreference.fromName(mode),
      palette: AppPalette.fromName(palette),
      // An install that never touched the switch has nothing stored and takes
      // the shipped default; one that turned it off keeps that.
      amoled: amoled ?? ThemeSettings.defaultAmoled,
    );
  }

  Future<void> setMode(ThemePreference mode) async {
    state = state.copyWith(mode: mode);
    await _store.setString(StoreKeys.theme, mode.name);
  }

  Future<void> setPalette(AppPalette palette) async {
    state = state.copyWith(palette: palette);
    await _store.setString(StoreKeys.palette, palette.name);
  }

  Future<void> setAmoled(bool amoled) async {
    state = state.copyWith(amoled: amoled);
    await _store.setBool(StoreKeys.amoled, amoled);
  }
}

final themeSettingsProvider =
    NotifierProvider<ThemeSettingsNotifier, ThemeSettings>(
      ThemeSettingsNotifier.new,
    );

// -- Focus clock -------------------------------------------------------------

/// Which face the focus timer wears.
///
/// Its own notifier rather than a fourth field on [ThemeSettings]: the clock
/// is drawn on one screen and read by nothing else, so folding it in would
/// make every palette swatch rebuild the focus tab.
class ClockFaceNotifier extends Notifier<ClockFace> {
  @override
  ClockFace build() => ClockFace.minimal;

  LocalStore get _store => ref.read(localStoreProvider);

  /// Called during bootstrap with whatever was persisted. Null — a first run —
  /// keeps the shipped face.
  void hydrate(String? stored) => state = ClockFace.fromName(stored);

  Future<void> set(ClockFace face) async {
    state = face;
    await _store.setString(StoreKeys.clockFace, face.name);
  }
}

final clockFaceProvider = NotifierProvider<ClockFaceNotifier, ClockFace>(
  ClockFaceNotifier.new,
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
}

final statsProvider = NotifierProvider<StatsNotifier, GamificationStats>(
  StatsNotifier.new,
);
