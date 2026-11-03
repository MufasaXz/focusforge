import 'package:flutter/material.dart';

/// Which tier a whitelist entry sits in.
///
/// The four tiers are also the shield's rule set: `blocked` closes the app,
/// `budgeted` closes it once a daily allowance is spent, `focusOnly` closes it
/// while a focus block runs, and `alwaysAllowed` leaves it alone. Keeping one
/// list rather than a separate rule list is what stops the screen and the
/// engine from disagreeing about what is armed.
enum WhitelistTier {
  alwaysAllowed('Always allowed', Color(0xFF8FE39B)),
  budgeted('Time budgeted', Color(0xFF7FA9FF)),
  blocked('Blocked', Color(0xFFFFB4AB)),
  focusOnly('Only while focusing', Color(0xFFFFD08A));

  const WhitelistTier(this.label, this.color);

  final String label;
  final Color color;

  /// True when this tier produces a rule the engine enforces.
  bool get isEnforced => this != WhitelistTier.alwaysAllowed;
}

/// One app the user has placed in a tier.
///
/// [packageId] is what the engine actually matches on. It is null only for
/// entries that predate the field or that the user typed by hand, and such an
/// entry is shown but never enforced — a rule with nothing to match cannot be
/// honoured, and pretending otherwise is the failure mode this model exists to
/// avoid.
@immutable
class WhitelistEntry {
  const WhitelistEntry({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.tier,
    this.packageId,
    this.budgetMinutes,
    this.usedMinutes = 0,
  });

  final String id;
  final String name;

  /// The fallback glyph, used when the real launcher icon cannot be read —
  /// on web, or after the app has been uninstalled.
  final IconData icon;
  final Color color;

  final WhitelistTier tier;

  /// The Android package this entry blocks, e.g. `com.instagram.android`.
  final String? packageId;

  /// The daily allowance, for [WhitelistTier.budgeted]. Null means none.
  final int? budgetMinutes;

  /// Today's foreground time, filled in from the platform rather than stored.
  final int usedMinutes;

  bool get budgeted => budgetMinutes != null && budgetMinutes! > 0;

  double get usage => budgetMinutes == null || budgetMinutes == 0
      ? 0
      : (usedMinutes / budgetMinutes!).clamp(0.0, 1.0);

  bool get overBudget => budgeted && usedMinutes >= budgetMinutes!;

  /// Whether this entry can actually be enforced by the engine.
  bool get enforceable => packageId != null && tier.isEnforced;

  WhitelistEntry copyWith({
    String? name,
    IconData? icon,
    Color? color,
    WhitelistTier? tier,
    String? packageId,
    int? budgetMinutes,
    int? usedMinutes,
    bool clearBudget = false,
  }) => WhitelistEntry(
    id: id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    color: color ?? this.color,
    tier: tier ?? this.tier,
    packageId: packageId ?? this.packageId,
    budgetMinutes: clearBudget ? null : (budgetMinutes ?? this.budgetMinutes),
    usedMinutes: usedMinutes ?? this.usedMinutes,
  );
}

/// The YouTube surface rules.
///
/// YouTube is the one app where a package-level decision cannot express what
/// the user wants: the same package holds a lecture and an endless Shorts
/// feed. These two switches pick surfaces to close and leave everything else
/// working, which is the difference between "I can still study from YouTube"
/// and "YouTube is gone".
@immutable
class YoutubeRules {
  const YoutubeRules({
    this.shorts = false,
    this.feed = false,
    this.focusOnly = false,
    this.study = false,
    this.studyChannels = const [],
    this.studyKeywords = const [],
    this.useSubjects = true,
  });

  /// Close the Shorts player.
  final bool shorts;

  /// Close the home feed and search results, so a lecture has to be opened
  /// from a direct link.
  final bool feed;

  /// Arm the two switches only while a focus block runs.
  ///
  /// The same "only while focusing" the app rules offer, for the one app whose
  /// surfaces are picked rather than the whole package: YouTube is free the
  /// rest of the day, and shut while the user is working.
  final bool focusOnly;

  /// Study mode: only videos from [studyChannels] (and a bundled list of
  /// well-known educational creators) play, plus videos whose title names one
  /// of [studyKeywords] or, with [useSubjects], one of the user's subjects.
  /// Shorts close while it is on.
  final bool study;

  /// Channel names or @handles, as the user typed or picked them.
  final List<String> studyChannels;

  /// Extra words that let a video through when its title contains them.
  final List<String> studyKeywords;

  /// Whether the user's subject names count as keywords too.
  final bool useSubjects;

  bool get any => shorts || feed || study;

  static const off = YoutubeRules();

  /// Channel and keyword lists are capped to what the engine reads.
  static const maxChannels = 100;
  static const maxKeywords = 50;

  YoutubeRules copyWith({
    bool? shorts,
    bool? feed,
    bool? focusOnly,
    bool? study,
    List<String>? studyChannels,
    List<String>? studyKeywords,
    bool? useSubjects,
  }) => YoutubeRules(
    shorts: shorts ?? this.shorts,
    feed: feed ?? this.feed,
    focusOnly: focusOnly ?? this.focusOnly,
    study: study ?? this.study,
    studyChannels: studyChannels ?? this.studyChannels,
    studyKeywords: studyKeywords ?? this.studyKeywords,
    useSubjects: useSubjects ?? this.useSubjects,
  );

  /// What the engine receives: the user's keywords plus, when chosen, their
  /// subject names.
  YoutubeRules forEngine(Iterable<String> subjects) => copyWith(
    studyKeywords: {
      ...studyKeywords,
      if (useSubjects)
        ...subjects.map((s) => s.trim()).where((s) => s.length >= 3),
    }.take(maxKeywords).toList(),
  );

  Map<String, dynamic> toJson() => {
    'shorts': shorts,
    'feed': feed,
    'focusOnly': focusOnly,
    'study': study,
    'studyChannels': studyChannels,
    'studyKeywords': studyKeywords,
    'useSubjects': useSubjects,
  };

  /// Trimmed, non-empty strings, de-duplicated without regard to case.
  static List<String> _strings(Object? value, int limit) {
    if (value is! List) return const [];
    final seen = <String>{};
    return [
      for (final item in value.whereType<String>())
        if (item.trim() case final text
            when text.isNotEmpty &&
                text.length <= 100 &&
                seen.add(text.toLowerCase()))
          text,
    ].take(limit).toList();
  }

  /// Type-tested rather than cast: this is read during bootstrap, where a
  /// wrong-typed value must degrade to "off" instead of aborting the launch.
  factory YoutubeRules.fromJson(Map<String, dynamic> j) => YoutubeRules(
    shorts: j['shorts'] is bool ? j['shorts'] as bool : false,
    feed: j['feed'] is bool ? j['feed'] as bool : false,
    focusOnly: j['focusOnly'] is bool ? j['focusOnly'] as bool : false,
    study: j['study'] is bool ? j['study'] as bool : false,
    studyChannels: _strings(j['studyChannels'], maxChannels),
    studyKeywords: _strings(j['studyKeywords'], maxKeywords),
    useSubjects: j['useSubjects'] is bool ? j['useSubjects'] as bool : true,
  );
}

/// A named bundle of blocks — "Exam Week", "Weekend Relax".
@immutable
class RestrictionProfile {
  const RestrictionProfile({
    required this.id,
    required this.name,
    required this.icon,
    required this.dailyTargetHours,
    this.active = false,
  });

  final String id;
  final String name;
  final IconData icon;
  final double dailyTargetHours;
  final bool active;

  RestrictionProfile copyWith({
    String? name,
    IconData? icon,
    double? dailyTargetHours,
    bool? active,
  }) => RestrictionProfile(
    id: id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    dailyTargetHours: dailyTargetHours ?? this.dailyTargetHours,
    active: active ?? this.active,
  );
}

/// Strict Mode configuration — see the settings spec.
@immutable
class StrictModeConfig {
  const StrictModeConfig({
    this.enabled = false,
    this.enabledAtMillis,
    this.durationMinutes = 120,
    this.commitmentPhrase = 'I am choosing to break my focus commitment',
    this.cooldownSeconds = 60,
  });

  final bool enabled;

  /// When the current window opened, as epoch milliseconds.
  ///
  /// The duration needs something to count from, and "when the user flipped
  /// the switch" is not recoverable from the stored config alone — so it is
  /// recorded rather than derived.
  final int? enabledAtMillis;

  final int durationMinutes;
  final String commitmentPhrase;
  final int cooldownSeconds;

  /// 15 minutes to 8 hours.
  static const double minHours = 0.25;
  static const double maxHours = 8;

  /// When the current window closes, or null when none is open.
  DateTime? get endsAt {
    final started = enabledAtMillis;
    if (!enabled || started == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      started + durationMinutes * 60000,
    );
  }

  StrictModeConfig copyWith({
    bool? enabled,
    int? enabledAtMillis,
    bool clearEnabledAt = false,
    int? durationMinutes,
    String? commitmentPhrase,
    int? cooldownSeconds,
  }) => StrictModeConfig(
    enabled: enabled ?? this.enabled,
    enabledAtMillis: clearEnabledAt
        ? null
        : (enabledAtMillis ?? this.enabledAtMillis),
    durationMinutes: durationMinutes ?? this.durationMinutes,
    commitmentPhrase: commitmentPhrase ?? this.commitmentPhrase,
    cooldownSeconds: cooldownSeconds ?? this.cooldownSeconds,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'enabledAtMillis': ?enabledAtMillis,
    'durationMinutes': durationMinutes,
    'cooldownSeconds': cooldownSeconds,
  };

  /// Every field is type-tested and defaulted, not cast — a schema-broken
  /// stored value must degrade rather than throw during bootstrap. A
  /// non-finite number counts as absent: `jsonDecode('1e999')` yields
  /// infinity rather than throwing, and `toInt` rejects it.
  factory StrictModeConfig.fromJson(Map<String, dynamic> j) => StrictModeConfig(
    enabled: j['enabled'] is bool ? j['enabled'] as bool : false,
    enabledAtMillis: _intOrNull(j['enabledAtMillis']),
    durationMinutes: _intOrNull(j['durationMinutes']) ?? 120,
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
    this.ownerUid = '',
  });

  final String appName;
  final DateTime at;
  final bool walkedAway;
  final String ownerUid;

  Map<String, dynamic> toJson() => {
    'appName': appName,
    'at': at.millisecondsSinceEpoch,
    'walkedAway': walkedAway,
    'ownerUid': ownerUid,
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
    ownerUid: j['ownerUid'] is String ? j['ownerUid'] as String : '',
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
