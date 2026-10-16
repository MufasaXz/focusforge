import 'dart:async';
import 'dart:convert';

import 'widget_service.dart';
import 'achievement_service.dart';

import 'package:shared_preferences/shared_preferences.dart';

/// Thin typed wrapper over [SharedPreferences].
///
/// Everything the app persists goes through here, and everything is stored as
/// JSON under an `ff.` prefix. That keeps the app's on-disk footprint
/// inspectable, keeps keys collision-free, and means swapping in Hive or a
/// Firebase mirror later is a change to this one file rather than to every
/// call site.
///
/// This is deliberately *local-only*: per the privacy promise, usage data never
/// leaves the device.
class LocalStore {
  LocalStore._(this._prefs);

  final SharedPreferences _prefs;
  final _changes = StreamController<String>.broadcast(sync: true);
  Stream<String> get changes => _changes.stream;

  static LocalStore? _instance;

  /// Opens the store. Safe to call repeatedly — the underlying
  /// [SharedPreferences] instance is cached by the plugin and by us.
  static Future<LocalStore> open() async {
    final existing = _instance;
    if (existing != null) return existing;
    final prefs = await SharedPreferences.getInstance();
    return _instance = LocalStore._(prefs);
  }

  static const _prefix = 'ff.';

  String _k(String key) => '$_prefix$key';

  // -- Primitives ------------------------------------------------------------
  //
  // These type-test the raw value instead of using the plugin's typed getters,
  // which are hard casts (`_preferenceCache[key] as String?`). A key holding a
  // different type — an older build wrote another shape, or the store is
  // corrupt — would otherwise throw a [TypeError], and several of these run in
  // bootstrap() before the first frame. Per the class contract, a malformed
  // value degrades to null.

  /// Reads [key] when it holds a [T], else null.
  T? _read<T>(String key) {
    final value = _prefs.get(_k(key));
    return value is T ? value : null;
  }

  String? getString(String key) => _read<String>(key);

  Future<void> setString(String key, String value) async {
    await _prefs.setString(_k(key), value);
    _changes.add(key);
    if ({
      StoreKeys.sessions,
      StoreKeys.presets,
      StoreKeys.theme,
      StoreKeys.palette,
      StoreKeys.subjects,
      StoreKeys.dailyGoalDays,
      'goal.planner',
      StoreKeys.user,
      StoreKeys.achievementHistoryOwner,
      StoreKeys.achievementAliases,
    }.contains(key)) {
      await WidgetService.refresh();
    }
  }

  bool? getBool(String key) => _read<bool>(key);

  Future<void> setBool(String key, bool value) async {
    await _prefs.setBool(_k(key), value);
    _changes.add(key);
    if (key == StoreKeys.amoled) await WidgetService.refresh();
  }

  int? getInt(String key) => _read<int>(key);

  Future<void> setInt(String key, int value) async {
    await _prefs.setInt(_k(key), value);
    _changes.add(key);
    if (key == StoreKeys.dailyGoal) await WidgetService.refresh();
  }

  double? getDouble(String key) => _read<double>(key);

  Future<void> setDouble(String key, double value) async {
    await _prefs.setDouble(_k(key), value);
    _changes.add(key);
  }

  Future<void> remove(String key) async {
    await _prefs.remove(_k(key));
    _changes.add(key);
  }

  // -- Structured ------------------------------------------------------------

  /// Reads a JSON object. Returns null on a missing key *or* on a decode
  /// failure — a corrupt value should degrade to "no data", never crash the
  /// launch path.
  Map<String, dynamic>? getMap(String key) {
    final raw = getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> setMap(String key, Map<String, dynamic> value) =>
      setString(key, jsonEncode(value));

  /// Reads a JSON array of objects. Same defensive posture as [getMap].
  List<Map<String, dynamic>> getList(String key) {
    final raw = getString(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<Map<String, dynamic>>().toList();
    } on FormatException {
      return const [];
    }
  }

  Future<void> setList(String key, List<Map<String, dynamic>> value) =>
      setString(key, jsonEncode(value));

  /// Decodes a list of `[id, value]` pairs — used by the per-row toggle maps
  /// (feed shields, notification switches) which are small and hot.
  Map<String, bool> getBoolMap(String key) {
    final raw = getString(key);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return decoded.map((k, v) => MapEntry(k.toString(), v == true));
    } on FormatException {
      return const {};
    }
  }

  Future<void> setBoolMap(String key, Map<String, bool> value) =>
      setString(key, jsonEncode(value));

  /// Decodes a map of numeric values. Entries that are not numbers coerce to
  /// 0 rather than throwing, mirroring [getBoolMap]: this map is read during
  /// bootstrap, so one bad value must not white-screen the launch.
  Map<String, double> getDoubleMap(String key) {
    final raw = getString(key);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return decoded.map(
        (k, v) => MapEntry(k.toString(), v is num ? v.toDouble() : 0),
      );
    } on FormatException {
      return const {};
    }
  }

  Future<void> setDoubleMap(String key, Map<String, double> value) =>
      setString(key, jsonEncode(value));

  /// Before Firebase replaces the stored identity, attribute the legacy
  /// device cabinet/history to its previous owner. This also covers a restored
  /// credential change before the achievement notifier exists at bootstrap.
  Future<void> prepareAchievementIdentity(String nextUid) async {
    final previousUid = getMap(StoreKeys.user)?['uid'];
    if (previousUid is! String || previousUid.isEmpty) return;
    if (getString(StoreKeys.achievementHistoryOwner) == null) {
      await setString(StoreKeys.achievementHistoryOwner, previousUid);
    }
    if (previousUid == nextUid ||
        getMap(StoreKeys.achievementAccounts) != null) {
      return;
    }
    final times = readAchievementTimes(getMap('achievements.unlockedAt'));
    final cabinet = {
      for (final entry in getBoolMap(StoreKeys.achievements).entries)
        if (entry.value && achievementIds.contains(entry.key))
          entry.key: times[entry.key] ?? 0,
    };
    await setMap(StoreKeys.achievementAccounts, {previousUid: cabinet});
  }

  // -- Maintenance -----------------------------------------------------------

  /// Clears the app's own keys. Deliberately not `prefs.clear()` — that would
  /// take out anything a plugin stored under its own namespace.
  Future<void> clearAll() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final k in keys) {
      await _prefs.remove(k);
    }
    await WidgetService.refresh();
  }

  /// Everything the app has stored, as a plain map — backs "Export my data".
  Map<String, Object?> exportAll() {
    final out = <String, Object?>{};
    for (final k in _prefs.getKeys().where((k) => k.startsWith(_prefix))) {
      out[k.substring(_prefix.length)] = _prefs.get(k);
    }
    return out;
  }
}

/// Keys in one place so a typo is a compile error rather than a silent reset.
class StoreKeys {
  const StoreKeys._();

  static const user = 'user';
  static const stats = 'stats';
  static const subjects = 'subjects';
  static const sessions = 'sessions';
  static const theme = 'theme';
  static const palette = 'theme.palette';
  static const amoled = 'theme.amoled';
  static const whitelistTiers = 'shield.whitelist';
  static const youtubeRules = 'shield.youtube';
  static const strictMode = 'shield.strict';
  static const remoteBlocks = 'shield.parentCache';
  static const breathEvents = 'shield.breathEvents';
  static const notifications = 'notifications';
  static const achievements = 'achievements';
  static const achievementAccounts = 'achievements.accounts';
  static const achievementHistoryOwner = 'achievements.historyOwner';
  static const achievementLinkedOwners = 'achievements.linkedOwners';
  static const achievementAliases = 'achievements.aliases';
  static const ambientVolumes = 'audio.volumes';
  static const ambientActive = 'audio.active';
  static const dailyGoal = 'goal.daily';
  static const dailyGoalDays = 'goal.days';
  static const presets = 'focus.presets';
  static const startingPlan = 'setup.startingPlan';
  static const setupProgress = 'setup.progress';
  static const customPlan = 'focus.customPlan';
  static const planLibrary = 'focus.planLibrary';
  static const coachSeen = 'coachmarks.seen';
  static const clockFace = 'focus.clock';

  /// Whether this device's week appears on the weekly board.
  static const boardOptIn = 'leaderboard.optIn';
}
