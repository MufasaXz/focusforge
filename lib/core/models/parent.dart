import 'package:flutter/foundation.dart';

import 'shield.dart';

/// The six digits a child's app shows and a parent types in.
///
/// Short on purpose: it is read off one screen and typed into another, by
/// someone standing next to the child. The expiry is what keeps that trade
/// honest — a code that leaks is only worth anything for a quarter of an hour.
@immutable
class PairCode {
  const PairCode({required this.code, required this.expiresAt});

  final String code;
  final DateTime expiresAt;

  bool get expired => DateTime.now().isAfter(expiresAt);

  /// How long a freshly minted code is good for.
  static const lifetime = Duration(minutes: 15);

  /// Exactly six digits, nothing else. Checked before a lookup so a typo is a
  /// message rather than a round trip.
  static bool looksValid(String value) => RegExp(r'^\d{6}$').hasMatch(value);
}

/// A child on a parent's list.
@immutable
class ChildLink {
  const ChildLink({required this.uid, required this.name, this.linkedAt});

  final String uid;
  final String name;
  final DateTime? linkedAt;

  Map<String, dynamic> toJson() => {
    'name': name,
    'linkedAt': linkedAt?.millisecondsSinceEpoch,
  };

  static ChildLink? fromJson(String uid, Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    if (name is! String || name.trim().isEmpty) return null;
    final at = raw['linkedAt'];
    return ChildLink(
      uid: uid,
      name: name,
      linkedAt: at is num
          ? DateTime.fromMillisecondsSinceEpoch(at.toInt())
          : null,
    );
  }

  ChildLink copyWith({String? name}) =>
      ChildLink(uid: uid, name: name ?? this.name, linkedAt: linkedAt);
}

/// The parent a child's device is linked to.
@immutable
class GuardianLink {
  const GuardianLink({required this.uid, required this.name, this.linkedAt});

  final String uid;
  final String name;
  final DateTime? linkedAt;

  static GuardianLink? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final uid = raw['parentUid'];
    final name = raw['parentName'];
    if (uid is! String || uid.isEmpty) return null;
    final at = raw['linkedAt'];
    return GuardianLink(
      uid: uid,
      name: name is String && name.trim().isNotEmpty ? name : 'Your parent',
      linkedAt: at is num
          ? DateTime.fromMillisecondsSinceEpoch(at.toInt())
          : null,
    );
  }
}

/// What a parent can see of a child's day.
///
/// A summary, not the log: minutes, sessions, the goal and the streak are what
/// answer "is this working", and the individual sessions are the child's own
/// business. The session log never leaves the device.
@immutable
class ChildProgress {
  const ChildProgress({
    this.minutes = 0,
    this.sessions = 0,
    this.goalMinutes = 180,
    this.streak = 0,
    this.topSubject,
    this.day,
    this.updatedAt,
  });

  final int minutes;
  final int sessions;
  final int goalMinutes;
  final int streak;
  final String? topSubject;

  /// The date the numbers belong to, as `yyyy-mm-dd`. A parent looking at a
  /// stale summary should be able to see that it is stale.
  final String? day;

  final DateTime? updatedAt;

  double get goalProgress =>
      goalMinutes <= 0 ? 0 : (minutes / goalMinutes).clamp(0.0, 1.0);

  Map<String, dynamic> toJson() => {
    'minutes': minutes,
    'sessions': sessions,
    'goalMinutes': goalMinutes,
    'streak': streak,
    'topSubject': ?topSubject,
    'day': ?day,
    'updatedAt': updatedAt?.millisecondsSinceEpoch,
  };

  static ChildProgress fromJson(Object? raw) {
    if (raw is! Map) return const ChildProgress();
    int intOr(Object? v, int fallback) => v is num ? v.toInt() : fallback;
    final updated = raw['updatedAt'];
    final subject = raw['topSubject'];
    final day = raw['day'];
    return ChildProgress(
      minutes: intOr(raw['minutes'], 0),
      sessions: intOr(raw['sessions'], 0),
      goalMinutes: intOr(raw['goalMinutes'], 180),
      streak: intOr(raw['streak'], 0),
      topSubject: subject is String && subject.isNotEmpty ? subject : null,
      day: day is String ? day : null,
      updatedAt: updated is num
          ? DateTime.fromMillisecondsSinceEpoch(updated.toInt())
          : null,
    );
  }
}

/// One app a parent keeps closed on a child's device.
@immutable
class RemoteBlock {
  const RemoteBlock({
    required this.packageId,
    required this.name,
    this.focusOnly = false,
  });

  final String packageId;
  final String name;

  /// Blocked only while the child is focusing, rather than all day.
  final bool focusOnly;

  Map<String, dynamic> toJson() => {
    'packageId': packageId,
    'name': name,
    'focusOnly': focusOnly,
  };

  static RemoteBlock? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final packageId = raw['packageId'];
    if (packageId is! String || packageId.isEmpty) return null;
    final name = raw['name'];
    return RemoteBlock(
      packageId: packageId,
      name: name is String && name.isNotEmpty ? name : packageId,
      focusOnly: raw['focusOnly'] == true,
    );
  }
}

/// An app on the child's device, as the parent's picker sees it.
///
/// Only the two things a parent needs to recognise an app: the package the
/// rule is written against and the name they would say out loud. No icon, no
/// usage, no history — the picker is a list of names, not a report on what the
/// child did with them.
@immutable
class CatalogApp {
  const CatalogApp({required this.packageId, required this.name});

  final String packageId;
  final String name;

  Map<String, dynamic> toJson() => {'packageId': packageId, 'name': name};

  static CatalogApp? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final packageId = raw['packageId'];
    if (packageId is! String || packageId.isEmpty) return null;
    final name = raw['name'];
    return CatalogApp(
      packageId: packageId,
      name: name is String && name.trim().isNotEmpty ? name.trim() : packageId,
    );
  }
}

/// The block list a parent has set for one child.
@immutable
class RemoteBlocks {
  const RemoteBlocks({
    this.apps = const [],
    this.youtube = YoutubeRules.off,
    this.enforced = true,
    this.updatedAt,
  });

  final List<RemoteBlock> apps;
  final YoutubeRules youtube;

  /// Whether the parent is enforcing the list or only watching.
  ///
  /// The list is kept either way: a parent who turns enforcement off for a
  /// week should find their choices where they left them. It is the child's
  /// side that reads this and decides what to push to the engine.
  final bool enforced;

  final DateTime? updatedAt;

  bool get isEmpty => apps.isEmpty && !youtube.any;

  /// The rules that are actually in force on the child's device.
  RemoteBlocks get inForce => enforced ? this : const RemoteBlocks();

  Map<String, dynamic> toJson() => {
    'apps': apps.map((a) => a.toJson()).toList(growable: false),
    'youtube': youtube.toJson(),
    'enforced': enforced,
    'updatedAt': updatedAt?.millisecondsSinceEpoch,
  };

  RemoteBlocks copyWith({
    List<RemoteBlock>? apps,
    YoutubeRules? youtube,
    bool? enforced,
  }) => RemoteBlocks(
    apps: apps ?? this.apps,
    youtube: youtube ?? this.youtube,
    enforced: enforced ?? this.enforced,
    updatedAt: DateTime.now(),
  );

  static RemoteBlocks fromJson(Object? raw) {
    if (raw is! Map) return const RemoteBlocks();
    final apps = <RemoteBlock>[];
    final list = raw['apps'];
    if (list is List) {
      for (final row in list) {
        final block = RemoteBlock.fromJson(row);
        if (block != null) apps.add(block);
      }
    }
    final youtube = raw['youtube'];
    final updated = raw['updatedAt'];
    return RemoteBlocks(
      apps: apps,
      youtube: youtube is Map
          ? YoutubeRules.fromJson(Map<String, dynamic>.from(youtube))
          : YoutubeRules.off,
      enforced: raw['enforced'] != false,
      updatedAt: updated is num
          ? DateTime.fromMillisecondsSinceEpoch(updated.toInt())
          : null,
    );
  }
}
