import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/seed.dart';
import '../services/local_store.dart';
import '../services/shield_service.dart';
import 'app_providers.dart';

final shieldServiceProvider = Provider<ShieldPlatformService>((ref) {
  final service = RecordingShieldService();
  ref.onDispose(service.dispose);
  return service;
});

/// Pushes the current shield state to the native engine. Every mutating
/// notifier funnels through here, so there is exactly one place that knows a
/// platform channel exists.
///
/// A caller passes the value it already holds for its own provider: a notifier
/// that reads the provider it belongs to trips Riverpod's self-dependency
/// assert, which is stripped in release and would otherwise leave every shield
/// mutation throwing in debug after its state change had landed. The providers
/// the caller is not inside are read here as usual.
void syncShield(
  Ref ref, {
  List<FeedGroup>? feedGroups,
  List<WhitelistEntry>? whitelist,
  List<RestrictionProfile>? profiles,
  StrictModeConfig? strictMode,
}) {
  final service = ref.read(shieldServiceProvider);
  // The explicit types are load-bearing: `??` whose result is a method-chain
  // receiver has no context type, so Dart would infer the `ref.read` result as
  // nullable.
  final List<FeedGroup> groups = feedGroups ?? ref.read(feedGroupsProvider);
  final List<RestrictionProfile> allProfiles =
      profiles ?? ref.read(profilesProvider);
  final config = ShieldConfig(
    feedShields: groups.expand((g) => g.rows).toList(),
    whitelist: whitelist ?? ref.read(whitelistProvider),
    activeProfileId: allProfiles.where((p) => p.active).firstOrNull?.id,
    strictMode: strictMode ?? ref.read(strictModeProvider),
  );
  // Fire and forget — a slow channel must never stall a toggle.
  unawaited(service.applyConfig(config));
}

// -- Feed-level shields ------------------------------------------------------

class FeedGroupsNotifier extends Notifier<List<FeedGroup>> {
  @override
  List<FeedGroup> build() => SeedData.feedGroups;

  LocalStore get _store => ref.read(localStoreProvider);

  /// Applies persisted per-row overrides on top of the seed catalogue. Copy and
  /// artwork stay in code; only the mutable bits live in storage, so a copy
  /// change between releases does not need a migration.
  void hydrate(List<Map<String, dynamic>> stored) {
    if (stored.isEmpty) return;
    // A row whose id is missing or not a string has no seed to apply to, so it
    // is skipped rather than cast — this runs during bootstrap.
    final byId = <String, Map<String, dynamic>>{
      for (final m in stored)
        if (m['id'] case final String id) id: m,
    };
    state = [
      for (final group in state)
        group.copyWith(
          rows: [
            for (final row in group.rows)
              if (byId[row.id] case final m?) row.withJson(m) else row,
          ],
        ),
    ];
  }

  Future<void> _persist() async {
    await _store.setList(StoreKeys.feedShields, [
      for (final g in state)
        for (final r in g.rows)
          {'id': r.id, 'enabled': r.enabled, 'mode': r.mode.index},
    ]);
    syncShield(ref, feedGroups: state);
  }

  Future<void> toggle(String id, bool enabled) async {
    state = [
      for (final g in state)
        g.copyWith(
          rows: [
            for (final r in g.rows)
              if (r.id == id) r.copyWith(enabled: enabled) else r,
          ],
        ),
    ];
    await _persist();
  }

  Future<void> setMode(String id, ShieldMode mode) async {
    state = [
      for (final g in state)
        g.copyWith(
          rows: [
            for (final r in g.rows)
              if (r.id == id) r.copyWith(mode: mode) else r,
          ],
        ),
    ];
    await _persist();
  }

  Future<void> setAll(bool enabled) async {
    state = [
      for (final g in state)
        g.copyWith(
          rows: [for (final r in g.rows) r.copyWith(enabled: enabled)],
        ),
    ];
    await _persist();
  }
}

final feedGroupsProvider =
    NotifierProvider<FeedGroupsNotifier, List<FeedGroup>>(
      FeedGroupsNotifier.new,
    );

/// Every feed row flattened — handy for counts and the all-on/off affordance.
final allFeedRowsProvider = Provider<List<FeedRow>>(
  (ref) => ref.watch(feedGroupsProvider).expand((g) => g.rows).toList(),
);

/// How many feed shields are currently armed. Drives the header badge.
final activeShieldCountProvider = Provider<int>(
  (ref) => ref.watch(allFeedRowsProvider).where((r) => r.enabled).length,
);

// -- Whitelist ---------------------------------------------------------------

class WhitelistNotifier extends Notifier<List<WhitelistEntry>> {
  @override
  List<WhitelistEntry> build() => _seeds;

  /// The whole catalogue in one list. Stored rows carry only `id`, `tier` and
  /// — for entries that are not seeds — their own presentation data, so these
  /// seed entries stay the source of name, icon and colour for seed rows.
  static const _seeds = <WhitelistEntry>[
    ...SeedData.alwaysAllowed,
    ...SeedData.budgeted,
    ...SeedData.blockedApps,
  ];

  LocalStore get _store => ref.read(localStoreProvider);

  /// Stored tier index, clamped. A missing or wrong-typed value falls back
  /// instead of throwing or indexing out of bounds.
  static WhitelistTier _tierOr(Object? value, int fallback) =>
      WhitelistTier.values[(value is num ? value.toInt() : fallback).clamp(
        0,
        2,
      )];

  /// Rebuilds a user-added entry from its stored row. Presentation data is
  /// written by [_persist] precisely so this is possible; a row written before
  /// that existed carries only `id`/`tier` and comes back degraded (id as the
  /// name, tier colour) rather than being dropped. Every field is type-tested:
  /// hydrate runs during bootstrap, where one bad row must not abort launch.
  static WhitelistEntry _entryFromStored(String id, Map<String, dynamic> m) {
    final tier = _tierOr(m['tier'], 0);
    return WhitelistEntry(
      id: id,
      name: m['name'] is String ? m['name'] as String : id,
      icon: AppIcons.resolve(m['icon'] is String ? m['icon'] as String : null),
      color: m['color'] is num
          ? Color((m['color'] as num).toInt())
          : tier.color,
      tier: tier,
      budgetMinutes: m['budgetMinutes'] is num
          ? (m['budgetMinutes'] as num).toInt()
          : null,
    );
  }

  /// Rebuilds state from the stored rows, so an entry removed with the minus
  /// button stays gone instead of being re-seeded on every launch.
  ///
  /// A missing key means the whitelist was never customised and the seed
  /// catalogue is the state; once a stored list exists it is authoritative,
  /// including when it holds nothing but removal tombstones (see [_persist]).
  void hydrate(List<Map<String, dynamic>> stored) {
    if (stored.isEmpty) return;
    final seedsById = {for (final e in _seeds) e.id: e};
    state = [
      for (final m in stored)
        if (m['removed'] != true)
          if (m['id'] case final String id)
            if (seedsById[id] case final seed?)
              // A seed row takes its name, icon and colour from the catalogue,
              // so copy and artwork can change between releases.
              seed.copyWith(tier: _tierOr(m['tier'], seed.tier.index))
            else
              // Not in the catalogue, so it is a user-added entry: rebuild it
              // from its own stored data instead of dropping it.
              _entryFromStored(id, m),
    ];
  }

  Future<void> _persist() async {
    final seedIds = {for (final e in _seeds) e.id};
    final present = {for (final e in state) e.id};
    await _store.setList(StoreKeys.whitelistTiers, [
      for (final e in state)
        {
          'id': e.id,
          'tier': e.tier.index,
          // A seed row is rebuilt from the catalogue on hydrate, so its tier
          // is all it needs to store. A user-added entry has no seed to
          // rebuild from, so it carries its own presentation data — without
          // it the entry would survive `add()` and then vanish on relaunch.
          if (!seedIds.contains(e.id)) ...{
            'name': e.name,
            'icon': AppIcons.nameOfOr(e.icon, 'book'),
            'color': e.color.toARGB32(),
            'budgetMinutes': ?e.budgetMinutes,
          },
        },
      // Tombstone every seed row the user removed. Without these, a whitelist
      // emptied down to nothing would persist as `[]` — indistinguishable
      // from "never customised" — and be re-seeded on the next launch.
      for (final seed in _seeds)
        if (!present.contains(seed.id)) {'id': seed.id, 'removed': true},
    ]);
    syncShield(ref, whitelist: state);
  }

  Future<void> setTier(String id, WhitelistTier tier) async {
    state = [
      for (final e in state)
        if (e.id == id) e.copyWith(tier: tier) else e,
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

  Future<void> remove(String id) async {
    state = state.where((e) => e.id != id).toList(growable: false);
    await _persist();
  }

  Future<void> add(WhitelistEntry entry) async {
    state = [...state, entry];
    await _persist();
  }
}

final whitelistProvider =
    NotifierProvider<WhitelistNotifier, List<WhitelistEntry>>(
      WhitelistNotifier.new,
    );

// -- Restriction profiles ----------------------------------------------------

/// Icons a user-created profile can pick from, by name. Reuses the app-wide
/// registry so nothing has to maintain a second table.
class ProfileIcons {
  const ProfileIcons._();

  static const _choices = [
    'fire',
    'book',
    'beach',
    'work',
    'night',
    'code',
    'school',
    'groups',
    'star',
    'bolt',
  ];

  static IconData resolve(String? name) => AppIcons.resolve(name);

  static String nameOf(IconData icon) => AppIcons.nameOfOr(icon, 'book');

  static List<String> get names => _choices;

  static IconData at(int i) => AppIcons.resolve(_choices[i % _choices.length]);
}

/// Applies the "at most one active profile" invariant. When [preferredId]
/// names a profile it becomes the active one; otherwise the first profile
/// already flagged active is kept. Every other profile is forced inactive.
List<RestrictionProfile> _withSingleActive(
  List<RestrictionProfile> profiles, {
  String? preferredId,
}) {
  final activeId =
      preferredId ?? profiles.where((p) => p.active).firstOrNull?.id;
  return [for (final p in profiles) p.copyWith(active: p.id == activeId)];
}

class ProfilesNotifier extends Notifier<List<RestrictionProfile>> {
  @override
  List<RestrictionProfile> build() => SeedData.profiles;

  LocalStore get _store => ref.read(localStoreProvider);

  /// Rebuilds the list as seeds + stored customs, restoring exactly one
  /// active profile.
  ///
  /// This *replaces* state rather than appending to it, so it stays correct
  /// when called more than once per process — bootstrap re-hydrates after
  /// account deletion, and an appending hydrate would duplicate every custom
  /// profile.
  void hydrate(List<Map<String, dynamic>> stored) {
    final seeds = SeedData.profiles;
    final seededIds = {for (final p in seeds) p.id};
    final restored = <RestrictionProfile>[
      ...seeds,
      for (final j in stored)
        // Stored ids never collide with seeds (`_persist` filters them out),
        // so a collision is corruption — skipping keeps the list unique.
        if (j['id'] case final String id when !seededIds.contains(id))
          RestrictionProfile(
            id: id,
            // Every field is type-tested, not cast: this runs during bootstrap,
            // where a wrong-typed value must degrade rather than abort launch.
            name: j['name'] is String ? j['name'] as String : 'Profile',
            icon: ProfileIcons.resolve(
              j['icon'] is String ? j['icon'] as String : null,
            ),
            blockedApps: j['blockedApps'] is num
                ? (j['blockedApps'] as num).toInt()
                : 0,
            dailyTargetHours: j['dailyTargetHours'] is num
                ? (j['dailyTargetHours'] as num).toDouble()
                : 3,
            schedules: j['schedules'] is List
                ? (j['schedules'] as List).whereType<String>().toList(
                    growable: false,
                  )
                : const <String>[],
          ),
    ];

    // The active flag is shared by seed and custom profiles alike, so it is
    // persisted as one id rather than duplicated into each stored row. A
    // missing key means "never customised" and the seed default (Exam Week)
    // wins; an empty string or a dangling id activates nothing rather than
    // guessing at a restriction the user did not choose.
    final storedActiveId = _store.getString(StoreKeys.activeProfile);
    final seedDefaultId = seeds.where((p) => p.active).firstOrNull?.id;
    final activeId = storedActiveId == null
        ? seedDefaultId
        : (restored.any((p) => p.id == storedActiveId) ? storedActiveId : null);
    state = [for (final p in restored) p.copyWith(active: p.id == activeId)];
  }

  Future<void> _persist() async {
    final seededIds = SeedData.profiles.map((p) => p.id).toSet();
    await _store.setList(StoreKeys.customProfiles, [
      for (final p in state.where((p) => !seededIds.contains(p.id)))
        {
          'id': p.id,
          'name': p.name,
          'icon': ProfileIcons.nameOf(p.icon),
          'blockedApps': p.blockedApps,
          'dailyTargetHours': p.dailyTargetHours,
          'schedules': p.schedules,
        },
    ]);
    // Which profile is active is the one mutable bit shared by seed and
    // custom profiles, so it lives under its own key instead of inside each
    // stored row (seeds are not persisted at all). `LocalStore` has no key
    // removal, so '' is the "none active" sentinel.
    await _store.setString(
      StoreKeys.activeProfile,
      state.where((p) => p.active).firstOrNull?.id ?? '',
    );
    syncShield(ref, profiles: state);
  }

  /// Activating a profile is exclusive — there is only one active at a time.
  Future<void> activate(String id) async {
    state = _withSingleActive(state, preferredId: id);
    await _persist();
  }

  Future<void> add(RestrictionProfile profile) async {
    state = _withSingleActive([
      ...state,
      profile,
    ], preferredId: profile.active ? profile.id : null);
    await _persist();
  }

  Future<void> update(RestrictionProfile profile) async {
    state = _withSingleActive([
      for (final p in state)
        if (p.id == profile.id) profile else p,
    ], preferredId: profile.active ? profile.id : null);
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((p) => p.id != id).toList(growable: false);
    await _persist();
  }
}

final profilesProvider =
    NotifierProvider<ProfilesNotifier, List<RestrictionProfile>>(
      ProfilesNotifier.new,
    );

final activeProfileProvider = Provider<RestrictionProfile?>(
  (ref) => ref.watch(profilesProvider).where((p) => p.active).firstOrNull,
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

  Future<void> setEnabled(bool value) async {
    state = state.copyWith(enabled: value);
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
