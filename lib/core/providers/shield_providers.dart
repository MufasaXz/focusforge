import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/icon_registry.dart';
import '../models/shield.dart';
import '../services/local_store.dart';
import '../services/native_shield_service.dart';
import '../services/shield_service.dart';
import 'app_providers.dart';

/// The shield engine for this build.
///
/// On Android that is [NativeShieldService], which drives a real accessibility
/// service; everywhere else it is [RecordingShieldService], which records what
/// it was told and blocks nothing. The rest of the app cannot tell the two
/// apart, which is what keeps the browser preview and the test suite honest
/// about what they are exercising.
final shieldServiceProvider = Provider<ShieldPlatformService>((ref) {
  final service = NativeShieldService.isSupported
      ? NativeShieldService()
      : RecordingShieldService();

  // The real engine reports every block as it happens. Those reports are the
  // impulse log — "how often did you reach for it, and how often did you walk
  // away" is the only number that can say whether the shield is working.
  final subscription = service.interceptions.listen((event) {
    ref
        .read(breathEventsProvider.notifier)
        .record(
          BreathEvent(
            appName: event.appName,
            at: event.at,
            walkedAway: event.walkedAway,
          ),
        );
  });

  ref.onDispose(() {
    unawaited(subscription.cancel());
    if (service is RecordingShieldService) service.dispose();
    if (service is NativeShieldService) service.dispose();
  });

  return service;
});

/// Whether the accessibility service is enabled.
///
/// Re-read on demand rather than polled: the answer only changes while the
/// user is in Android's settings, and the app is told to re-check when it
/// resumes.
final shieldEnabledProvider = FutureProvider<bool>(
  (ref) => ref.watch(shieldServiceProvider).isServiceEnabled(),
);

/// Pushes the current shield state to the engine. Every mutating notifier
/// funnels through here, so there is exactly one place that knows a platform
/// channel exists.
///
/// A caller passes the value it already holds for its own provider: a notifier
/// that reads the provider it belongs to trips Riverpod's self-dependency
/// assert, which is stripped in release and would otherwise leave every shield
/// mutation throwing in debug after its state change had landed. The providers
/// the caller is not inside are read here as usual.
void syncShield(
  Ref ref, {
  List<WhitelistEntry>? whitelist,
  YoutubeRules? youtube,
  StrictModeConfig? strictMode,
}) {
  final service = ref.read(shieldServiceProvider);
  // The explicit type is load-bearing: `??` whose result is a method-chain
  // receiver has no context type, so Dart would infer the `ref.read` result as
  // nullable.
  final List<WhitelistEntry> apps = whitelist ?? ref.read(whitelistProvider);
  final config = ShieldConfig(
    whitelist: apps,
    youtube: youtube ?? ref.read(youtubeRulesProvider),
    strictMode: strictMode ?? ref.read(strictModeProvider),
  );
  // Fire and forget — a slow channel must never stall a toggle.
  unawaited(service.applyConfig(config));
}

// -- App rules ---------------------------------------------------------------

/// The stored int, or null when it is absent or unusable.
///
/// Finiteness is part of "readable": `jsonDecode('1e999')` yields infinity
/// rather than throwing, and `toInt` rejects a non-finite double — which,
/// inside hydrate, is a throw before the first frame.
int? _storedInt(Object? value) =>
    value is num && value.isFinite ? value.toInt() : null;

/// The apps the user has placed in a tier.
///
/// Starts empty on a cold install. There is deliberately no seeded catalogue:
/// a list of apps the user never chose is a list that closes things they did
/// not ask to close, and the first thing they would have to do is undo it.
class WhitelistNotifier extends Notifier<List<WhitelistEntry>> {
  @override
  List<WhitelistEntry> build() => const [];

  static const defaultBudgetMinutes = 30;

  LocalStore get _store => ref.read(localStoreProvider);

  /// Stored tier index, clamped. A missing or wrong-typed value falls back
  /// instead of throwing or indexing out of bounds.
  static WhitelistTier _tierOr(Object? value, int fallback) =>
      WhitelistTier.values[(_storedInt(value) ?? fallback).clamp(0, 2)];

  /// Rebuilds an entry from its stored row.
  ///
  /// Every field is type-tested: hydrate runs during bootstrap, where one bad
  /// row must not abort the launch. An entry with no readable package id is
  /// kept — the user can still see and remove it — but it carries no rule.
  static WhitelistEntry _fromStored(String id, Map<String, dynamic> m) {
    final tier = _tierOr(m['tier'], 0);
    final argb = _storedInt(m['color']);
    return WhitelistEntry(
      id: id,
      name: m['name'] is String ? m['name'] as String : id,
      icon: AppIcons.resolve(m['icon'] is String ? m['icon'] as String : null),
      color: argb == null ? tier.color : Color(argb),
      tier: tier,
      packageId: m['packageId'] is String ? m['packageId'] as String : null,
      budgetMinutes: _storedInt(m['budgetMinutes']),
    );
  }

  /// Rebuilds state from the stored rows, so an entry removed stays gone
  /// instead of coming back on the next launch.
  ///
  /// A missing key means the user has never chosen an app, and an empty list
  /// is the correct state for that — not a catalogue.
  void hydrate(List<Map<String, dynamic>> stored) {
    state = [
      for (final m in stored)
        if (m['id'] case final String id) _fromStored(id, m),
    ];
  }

  Future<void> _persist() async {
    await _store.setList(StoreKeys.whitelistTiers, [
      for (final e in state)
        {
          'id': e.id,
          'name': e.name,
          'icon': AppIcons.nameOfOr(e.icon, 'apps'),
          'color': e.color.toARGB32(),
          'tier': e.tier.index,
          'packageId': ?e.packageId,
          'budgetMinutes': ?e.budgetMinutes,
        },
    ]);
    syncShield(ref, whitelist: state);
  }

  Future<void> setTier(String id, WhitelistTier tier) async {
    state = [
      for (final e in state)
        // A budget with no allowance is a rule that can never fire, so moving
        // into the budgeted tier gives one a default rather than leaving the
        // entry armed and inert.
        if (e.id == id)
          e.copyWith(
            tier: tier,
            budgetMinutes: tier == WhitelistTier.budgeted
                ? (e.budgetMinutes ?? defaultBudgetMinutes)
                : null,
            clearBudget: tier != WhitelistTier.budgeted,
          )
        else
          e,
    ];
    await _persist();
  }

  /// Cycles Always allowed → Budgeted → Blocked → Always allowed.
  Future<void> cycleTier(String id) async {
    final entry = state.where((e) => e.id == id).firstOrNull;
    if (entry == null) return;
    final next = WhitelistTier
        .values[(entry.tier.index + 1) % WhitelistTier.values.length];
    await setTier(id, next);
  }

  Future<void> setBudget(String id, int minutes) async {
    state = [
      for (final e in state)
        if (e.id == id)
          e.copyWith(budgetMinutes: minutes.clamp(5, 24 * 60))
        else
          e,
    ];
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((e) => e.id != id).toList(growable: false);
    await _persist();
  }

  /// Adds an app from the device, or moves it if it is already listed.
  ///
  /// Adding the same app twice would produce two rules for one package and the
  /// engine would have to pick one, so the second add is a tier change rather
  /// than a duplicate row.
  Future<void> addInstalledApp({
    required String packageId,
    required String name,
    WhitelistTier tier = WhitelistTier.blocked,
    int? budgetMinutes,
  }) async {
    final existing = state.where((e) => e.packageId == packageId).firstOrNull;
    if (existing != null) {
      await setTier(existing.id, tier);
      return;
    }
    state = [
      ...state,
      WhitelistEntry(
        // Keyed on the package, so re-adding an app after removing it lands on
        // the same identity rather than accumulating history.
        id: 'pkg:$packageId',
        name: name,
        icon: Icons.apps_rounded,
        color: tier.color,
        tier: tier,
        packageId: packageId,
        budgetMinutes: tier == WhitelistTier.budgeted
            ? (budgetMinutes ?? defaultBudgetMinutes)
            : null,
      ),
    ];
    await _persist();
  }
}

final whitelistProvider =
    NotifierProvider<WhitelistNotifier, List<WhitelistEntry>>(
      WhitelistNotifier.new,
    );

/// The entries the engine can actually enforce.
///
/// An entry with no package id is visible on the screen but absent here, which
/// is what stops a count on the dashboard from promising a block that cannot
/// happen.
final enforcedRulesProvider = Provider<List<WhitelistEntry>>(
  (ref) => ref
      .watch(whitelistProvider)
      .where((e) => e.enforceable)
      .toList(growable: false),
);

final blockedAppsProvider = Provider<List<WhitelistEntry>>(
  (ref) => ref
      .watch(enforcedRulesProvider)
      .where((e) => e.tier == WhitelistTier.blocked)
      .toList(growable: false),
);

final budgetedAppsProvider = Provider<List<WhitelistEntry>>(
  (ref) => ref
      .watch(enforcedRulesProvider)
      .where((e) => e.tier == WhitelistTier.budgeted)
      .toList(growable: false),
);

/// How many rules the engine is enforcing right now.
///
/// Counted from the enforceable entries rather than the whole list, so a
/// number shown on the dashboard can never promise a block that cannot happen.
final activeShieldCountProvider = Provider<int>(
  (ref) => ref.watch(enforcedRulesProvider).length,
);

// -- YouTube -----------------------------------------------------------------

/// The YouTube surface switches.
///
/// Independent of the whitelist on purpose: blocking all of YouTube and
/// blocking only its Shorts are different requests, and a user who wants the
/// second one should not have to add YouTube to a block list they do not want.
class YoutubeRulesNotifier extends Notifier<YoutubeRules> {
  @override
  YoutubeRules build() => YoutubeRules.off;

  LocalStore get _store => ref.read(localStoreProvider);

  void hydrate(Map<String, dynamic>? stored) {
    if (stored != null) state = YoutubeRules.fromJson(stored);
  }

  Future<void> set(YoutubeRules next) async {
    state = next;
    await _store.setMap(StoreKeys.youtubeRules, next.toJson());
    syncShield(ref, youtube: next);
  }

  Future<void> setShorts(bool value) => set(state.copyWith(shorts: value));

  Future<void> setFeed(bool value) => set(state.copyWith(feed: value));
}

final youtubeRulesProvider =
    NotifierProvider<YoutubeRulesNotifier, YoutubeRules>(
      YoutubeRulesNotifier.new,
    );

// -- Strict mode -------------------------------------------------------------

class StrictModeNotifier extends Notifier<StrictModeConfig> {
  @override
  StrictModeConfig build() => const StrictModeConfig();

  LocalStore get _store => ref.read(localStoreProvider);

  void hydrate(Map<String, dynamic>? stored) {
    if (stored != null) state = StrictModeConfig.fromJson(stored);
  }

  Future<void> _persist() async {
    await _store.setMap(StoreKeys.strictMode, state.toJson());
    syncShield(ref, strictMode: state);
  }

  /// Turning it on stamps the moment, which is what gives the duration
  /// something to count from. Without it "120 minutes" would have no start.
  Future<void> setEnabled(bool value) async {
    state = value
        ? state.copyWith(
            enabled: true,
            enabledAtMillis: DateTime.now().millisecondsSinceEpoch,
          )
        : state.copyWith(enabled: false, clearEnabledAt: true);
    await _persist();
  }

  Future<void> setDuration(int minutes) async {
    state = state.copyWith(durationMinutes: minutes);
    await _persist();
  }

  Future<void> update(StrictModeConfig next) async {
    state = next;
    await _persist();
  }
}

final strictModeProvider =
    NotifierProvider<StrictModeNotifier, StrictModeConfig>(
      StrictModeNotifier.new,
    );

/// True while a strict-mode window is open, so the UI can say so rather than
/// leaving the user to work it out from a switch.
final strictModeActiveProvider = Provider<bool>((ref) {
  final config = ref.watch(strictModeProvider);
  final started = config.enabledAtMillis;
  if (!config.enabled || started == null) return false;
  final ends = started + config.durationMinutes * 60000;
  return DateTime.now().millisecondsSinceEpoch < ends;
});

// -- Deep Breath Gate --------------------------------------------------------

class BreathEventsNotifier extends Notifier<List<BreathEvent>> {
  @override
  List<BreathEvent> build() => const [];

  LocalStore get _store => ref.read(localStoreProvider);

  void hydrate(List<Map<String, dynamic>> stored) {
    state = stored.map(BreathEvent.fromJson).toList(growable: false);
  }

  Future<void> record(BreathEvent event) async {
    state = [...state, event];
    // Rolling window, not an archive — cap the log so storage stays bounded.
    if (state.length > 200) {
      state = state.sublist(state.length - 200);
    }
    await _store.setList(
      StoreKeys.breathEvents,
      state.map((e) => e.toJson()).toList(growable: false),
    );
  }

  int get walkedAway => state.where((e) => e.walkedAway).length;
  int get total => state.length;
}

final breathEventsProvider =
    NotifierProvider<BreathEventsNotifier, List<BreathEvent>>(
      BreathEventsNotifier.new,
    );
