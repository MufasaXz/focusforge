import 'package:flutter/material.dart';

/// How hard a feed is restricted. The index is persisted, so keep the order.
enum ShieldMode {
  feedOnly('Block Feed Only'),
  timeLimit('Time Limit'),
  fullBlock('Full App Block');

  const ShieldMode(this.label);

  final String label;

  static ShieldMode fromIndex(int? i) =>
      (i == null || i < 0 || i >= values.length)
      ? ShieldMode.feedOnly
      : values[i];
}

/// An app the user has asked us to watch.
@immutable
class TrackedApp {
  const TrackedApp({
    required this.name,
    required this.icon,
    required this.color,
    required this.minutes,
    required this.limit,
    required this.shielded,
  });

  final String name;
  final IconData icon;
  final Color color;
  final int minutes;
  final int limit;
  final bool shielded;

  double get ratio => limit <= 0 ? 0 : (minutes / limit).clamp(0.0, 1.0);

  bool get overLimit => limit > 0 && minutes > limit;

  TrackedApp copyWith({bool? shielded, int? minutes}) => TrackedApp(
    name: name,
    icon: icon,
    color: color,
    minutes: minutes ?? this.minutes,
    limit: limit,
    shielded: shielded ?? this.shielded,
  );
}

/// One feed-level block (Reels, Shorts, Watch…) inside an app.
@immutable
class FeedRow {
  const FeedRow({
    required this.id,
    required this.appName,
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.enabled,
    this.modes,
    this.mode = ShieldMode.feedOnly,
  });

  final String id;
  final String appName;
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final bool enabled;

  /// Non-null when this row offers the exclusive [ShieldMode] radio chips.
  final List<ShieldMode>? modes;
  final ShieldMode mode;

  /// Legacy accessor — the chip row indexes modes positionally.
  int get modeIndex => mode.index;

  FeedRow copyWith({bool? enabled, ShieldMode? mode}) => FeedRow(
    id: id,
    appName: appName,
    icon: icon,
    color: color,
    title: title,
    description: description,
    enabled: enabled ?? this.enabled,
    modes: modes,
    mode: mode ?? this.mode,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'enabled': enabled,
    'mode': mode.index,
  };

  /// Rehydrates only the mutable fields; the rest come from seed data so that
  /// copy and artwork can change between releases without a migration.
  ///
  /// Both fields are type-tested rather than cast: `as bool?` guards against a
  /// null but still throws on a wrong-typed value, and this runs during
  /// bootstrap where one bad row must not abort the launch.
  FeedRow withJson(Map<String, dynamic> j) => copyWith(
    enabled: j['enabled'] is bool ? j['enabled'] as bool : enabled,
    mode: ShieldMode.fromIndex(_intOrNull(j['mode'])),
  );
}

/// Groups the feed rows for display.
@immutable
class FeedGroup {
  const FeedGroup({
    required this.title,
    required this.icon,
    required this.rows,
  });

  final String title;
  final IconData icon;
  final List<FeedRow> rows;

  FeedGroup copyWith({List<FeedRow>? rows}) =>
      FeedGroup(title: title, icon: icon, rows: rows ?? this.rows);
}

/// Which tier a whitelist entry sits in.
enum WhitelistTier {
  alwaysAllowed('Always allowed', Color(0xFF8FE39B)),
  budgeted('Time budgeted', Color(0xFF7FA9FF)),
  blocked('Blocked', Color(0xFFFFB4AB));

  const WhitelistTier(this.label, this.color);

  final String label;
  final Color color;
}

@immutable
class WhitelistEntry {
  const WhitelistEntry({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.tier,
    this.budgetMinutes,
    this.usedMinutes = 0,
  });

  final String id;
  final String name;
  final IconData icon;
  final Color color;
  final WhitelistTier tier;
  final int? budgetMinutes;
  final int usedMinutes;

  bool get budgeted => budgetMinutes != null;

  double get usage => budgetMinutes == null || budgetMinutes == 0
      ? 0
      : (usedMinutes / budgetMinutes!).clamp(0.0, 1.0);

  WhitelistEntry copyWith({WhitelistTier? tier, int? usedMinutes}) =>
      WhitelistEntry(
        id: id,
        name: name,
        icon: icon,
        color: color,
        tier: tier ?? this.tier,
        budgetMinutes: budgetMinutes,
        usedMinutes: usedMinutes ?? this.usedMinutes,
      );
}

/// A named bundle of blocks — "Exam Week", "Weekend Relax".
@immutable
class RestrictionProfile {
  const RestrictionProfile({
    required this.id,
    required this.name,
    required this.icon,
    required this.blockedApps,
    required this.dailyTargetHours,
    this.active = false,
    this.schedules = const <String>[],
  });

  final String id;
  final String name;
  final IconData icon;
  final int blockedApps;
  final double dailyTargetHours;
  final bool active;

  /// Human-readable windows, e.g. `Mon–Fri 09:00–17:00`.
  final List<String> schedules;

  RestrictionProfile copyWith({
    String? name,
    IconData? icon,
    int? blockedApps,
    double? dailyTargetHours,
    bool? active,
    List<String>? schedules,
  }) => RestrictionProfile(
    id: id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    blockedApps: blockedApps ?? this.blockedApps,
    dailyTargetHours: dailyTargetHours ?? this.dailyTargetHours,
    active: active ?? this.active,
    schedules: schedules ?? this.schedules,
  );
}

/// Strict Mode configuration — see the settings spec.
@immutable
class StrictModeConfig {
  const StrictModeConfig({
    this.enabled = false,
    this.durationMinutes = 120,
    this.allowCalls = true,
    this.allowEmergency = true,
    this.allowMaps = false,
    this.commitmentPhrase = 'I am choosing to break my focus commitment',
    this.cooldownSeconds = 60,
  });

  final bool enabled;
  final int durationMinutes;
  final bool allowCalls;
  final bool allowEmergency;
  final bool allowMaps;
  final String commitmentPhrase;
  final int cooldownSeconds;

  /// 15 minutes to 8 hours.
  static const double minHours = 0.25;
  static const double maxHours = 8;

  StrictModeConfig copyWith({
    bool? enabled,
    int? durationMinutes,
    bool? allowCalls,
    bool? allowEmergency,
    bool? allowMaps,
    String? commitmentPhrase,
    int? cooldownSeconds,
  }) => StrictModeConfig(
    enabled: enabled ?? this.enabled,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    allowCalls: allowCalls ?? this.allowCalls,
    allowEmergency: allowEmergency ?? this.allowEmergency,
    allowMaps: allowMaps ?? this.allowMaps,
    commitmentPhrase: commitmentPhrase ?? this.commitmentPhrase,
    cooldownSeconds: cooldownSeconds ?? this.cooldownSeconds,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'durationMinutes': durationMinutes,
    'allowCalls': allowCalls,
    'allowEmergency': allowEmergency,
    'allowMaps': allowMaps,
    'cooldownSeconds': cooldownSeconds,
  };

  /// Every field is type-tested and defaulted, not cast — a schema-broken
  /// stored value must degrade rather than throw during bootstrap. A
  /// non-finite number counts as absent: `jsonDecode('1e999')` yields
  /// infinity rather than throwing, and `toInt` rejects it.
  factory StrictModeConfig.fromJson(Map<String, dynamic> j) => StrictModeConfig(
    enabled: j['enabled'] is bool ? j['enabled'] as bool : false,
    durationMinutes: _intOrNull(j['durationMinutes']) ?? 120,
    allowCalls: j['allowCalls'] is bool ? j['allowCalls'] as bool : true,
    allowEmergency: j['allowEmergency'] is bool
        ? j['allowEmergency'] as bool
        : true,
    allowMaps: j['allowMaps'] is bool ? j['allowMaps'] as bool : false,
    cooldownSeconds: _intOrNull(j['cooldownSeconds']) ?? 60,
  );
}

/// The record of one Deep Breath Gate encounter. These are the raw material
/// for the "impulse events" chart — how often the user reached for a blocked
/// app, and how often they walked away.
@immutable
class BreathEvent {
  const BreathEvent({
    required this.appName,
    required this.at,
    required this.walkedAway,
  });

  final String appName;
  final DateTime at;
  final bool walkedAway;

  Map<String, dynamic> toJson() => {
    'appName': appName,
    'at': at.millisecondsSinceEpoch,
    'walkedAway': walkedAway,
  };

  /// Every field is defaulted: a schema-broken stored row must degrade to a
  /// blank event rather than throw and abort bootstrap before the first frame.
  /// The epoch is the sentinel for a missing timestamp — it is obviously not
  /// a real encounter, unlike `now`, which would fabricate recent activity.
  /// A timestamp outside `DateTime`'s range, or a non-finite one, lands on
  /// the epoch too.
  ///
  /// Each field is type-tested, not cast: `as bool?` guards against a null but
  /// throws on a wrong-typed value, so `{"walkedAway": "yes"}` used to abort
  /// the launch before `??` could apply.
  factory BreathEvent.fromJson(Map<String, dynamic> j) => BreathEvent(
    appName: j['appName'] is String ? j['appName'] as String : '',
    at: _dateOr(j['at']),
    walkedAway: j['walkedAway'] is bool ? j['walkedAway'] as bool : true,
  );
}

// -- Persisted-JSON readers --------------------------------------------------
//
// Hydration runs in bootstrap(), before the first frame, so a value that is
// non-finite or out of range must degrade instead of aborting the launch.
// `jsonDecode('1e999')` yields infinity rather than throwing, and `toInt`
// throws on a non-finite double, so finiteness is part of "readable".

/// The epoch sentinel for a row with no readable timestamp.
final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

/// The stored int, or null when the value is absent or unusable.
int? _intOrNull(Object? value) =>
    value is num && value.isFinite ? value.toInt() : null;

/// The epoch for a timestamp [DateTime] cannot represent: a non-finite double
/// has no int value at all, and an epoch outside ±8.64e15 ms is rejected.
DateTime _dateOr(Object? value) {
  if (value is! num || !value.isFinite) return _epoch;
  try {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  } on ArgumentError {
    return _epoch;
  }
}
