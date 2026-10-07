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
  const ChildLink({
    required this.uid,
    required this.name,
    this.linkedAt,
    this.focusOnly = false,
  });

  final String uid;
  final String name;
  final DateTime? linkedAt;

  /// True when the parent has chosen to watch rather than to block: the
  /// child's progress is visible and no blocks are pushed.
  final bool focusOnly;

  Map<String, dynamic> toJson() => {
    'name': name,
    'linkedAt': linkedAt?.millisecondsSinceEpoch,
    'focusOnly': focusOnly,
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
      focusOnly: raw['focusOnly'] == true,
    );
  }

  ChildLink copyWith({String? name, bool? focusOnly}) => ChildLink(
    uid: uid,
    name: name ?? this.name,
    linkedAt: linkedAt,
    focusOnly: focusOnly ?? this.focusOnly,
  );
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

/// The block list a parent has set for one child.
@immutable
class RemoteBlocks {
  const RemoteBlocks({
    this.apps = const [],
    this.youtube = YoutubeRules.off,
    this.updatedAt,
  });

  final List<RemoteBlock> apps;
  final YoutubeRules youtube;
  final DateTime? updatedAt;

  bool get isEmpty => apps.isEmpty && !youtube.any;

  Map<String, dynamic> toJson() => {
    'apps': apps.map((a) => a.toJson()).toList(growable: false),
    'youtube': youtube.toJson(),
    'updatedAt': updatedAt?.millisecondsSinceEpoch,
  };

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
      updatedAt: updated is num
          ? DateTime.fromMillisecondsSinceEpoch(updated.toInt())
          : null,
    );
  }
}
