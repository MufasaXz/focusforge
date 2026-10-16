import '../localization/app_strings.dart';

import 'package:flutter/material.dart';

enum AchievementUnit { sessions, days, hours, walkAways, weeklyTargets }

/// A badge. Locked badges show how close the user is rather than hiding.
@immutable
class Achievement {
  const Achievement({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.target,
    this.unit = AchievementUnit.sessions,
    this.progress = 0,
    this.unlockedAt,
  });

  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final double target;
  final AchievementUnit unit;
  final double progress;
  final DateTime? unlockedAt;

  bool get unlocked => unlockedAt != null;

  double get ratio => target <= 0 ? 0 : (progress / target).clamp(0.0, 1.0);

  double get cappedProgress => progress.clamp(0.0, target);
  double get remaining => (target - cappedProgress).clamp(0.0, target);

  String get progressLabel => unit == AchievementUnit.weeklyTargets
      ? tr('{0}% of weekly targets', [(ratio * 100).round()])
      : '${_amount(cappedProgress)} / ${_amount(target)}';

  String get remainingLabel => unlocked || remaining <= 0
      ? tr('Target reached')
      : tr('{0} remaining', [_amount(remaining, roundUp: true)]);

  String _amount(double value, {bool roundUp = false}) {
    if (unit == AchievementUnit.hours) {
      // Session logs keep whole minutes. Avoid rounding a near-complete hour
      // badge to zero remaining or to a whole hour that has not been earned.
      final raw = value * 60;
      final minutes = roundUp ? (raw - 0.0000001).ceil() : raw.round();
      final hours = minutes ~/ 60;
      final rest = minutes % 60;
      if (hours == 0) {
        return tr(rest == 1 ? '{0} minute' : '{0} minutes', [rest]);
      }
      final hourLabel = tr(hours == 1 ? '{0} hour' : '{0} hours', [hours]);
      return rest == 0 ? hourLabel : tr('{0} {1} min', [hourLabel, rest]);
    }
    if (unit == AchievementUnit.weeklyTargets) {
      return tr('{0}% of weekly targets', [(value * 100).ceil()]);
    }
    final count = value.ceil();
    final noun = switch (unit) {
      AchievementUnit.sessions => count == 1 ? 'session' : 'sessions',
      AchievementUnit.days => count == 1 ? 'day' : 'days',
      AchievementUnit.walkAways => count == 1 ? 'walk-away' : 'walk-aways',
      _ => '',
    };
    return tr('{0} {1}', [count, tr(noun)]);
  }

  Achievement copyWith({double? progress, DateTime? unlockedAt}) => Achievement(
    id: id,
    name: name,
    description: description,
    icon: icon,
    color: color,
    target: target,
    unit: unit,
    progress: progress ?? this.progress,
    unlockedAt: unlockedAt ?? this.unlockedAt,
  );
}

/// A private Firebase study group. Only aggregate progress is shared.
@immutable
class StudyGroup {
  const StudyGroup({
    required this.id,
    required this.name,
    required this.icon,
    required this.targetHours,
    required this.createdAt,
    this.inviteCode = '',
    this.ownerUid = '',
    this.memberIds = const [],
  });
  final String id;
  final String name;
  final IconData icon;
  final double targetHours;
  final DateTime createdAt;
  final String inviteCode;
  final String ownerUid;
  final List<String> memberIds;
  int get memberCount => memberIds.length;
}

@immutable
class GroupMember {
  const GroupMember({
    required this.uid,
    required this.name,
    required this.week,
    required this.minutes,
    this.focusUntil,
  });
  final String uid;
  final String name;
  final String week;
  final int minutes;
  final DateTime? focusUntil;
  bool focusingAt(DateTime now) => focusUntil?.isAfter(now) ?? false;
  factory GroupMember.fromJson(String uid, Map<String, dynamic> data) =>
      GroupMember(
        uid: uid,
        name: data['name'] as String? ?? 'A student',
        week: data['week'] as String? ?? '',
        minutes: data['minutes'] as int? ?? 0,
        focusUntil: data['focusUntil'] is int && (data['focusUntil'] as int) > 0
            ? DateTime.fromMillisecondsSinceEpoch(data['focusUntil'] as int)
            : null,
      );
}

/// A member row inside a group, or a row on the leaderboard.
@immutable
class LeaderboardEntry {
  const LeaderboardEntry({
    this.uid = '',
    required this.name,
    required this.hours,
    this.isMe = false,
    this.group,
    this.level,
  });

  final String uid;
  final String name;
  final double hours;
  final int? level;
  final bool isMe;
  final String? group;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.take(1).toString().toUpperCase();
    }
    return (parts.first.characters.take(1).toString() +
            parts.last.characters.take(1).toString())
        .toUpperCase();
  }
}

/// Which leaderboard scope is selected.
enum LeaderboardScope {
  friends('Friends', Icons.people_alt_rounded),
  group('Group', Icons.groups_rounded),
  global('Global', Icons.public_rounded);

  const LeaderboardScope(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Every notification switch, plus the quiet-hours window.
@immutable
class NotificationPrefs {
  const NotificationPrefs({
    this.sessionReminders = true,
    this.dailySummary = true,
    this.streakAlerts = true,
    this.blockingAlerts = false,
    this.weeklyReport = true,
    this.buddyUpdates = true,
    this.groupActivity = true,
    this.challengeInvites = true,
    this.quietHoursEnabled = true,
    this.quietStartHour = 22,
    this.quietEndHour = 7,
  });

  final bool sessionReminders;
  final bool dailySummary;
  final bool streakAlerts;
  final bool blockingAlerts;
  final bool weeklyReport;
  final bool buddyUpdates;
  final bool groupActivity;
  final bool challengeInvites;
  final bool quietHoursEnabled;
  final int quietStartHour;
  final int quietEndHour;

  NotificationPrefs copyWith({
    bool? sessionReminders,
    bool? dailySummary,
    bool? streakAlerts,
    bool? blockingAlerts,
    bool? weeklyReport,
    bool? buddyUpdates,
    bool? groupActivity,
    bool? challengeInvites,
    bool? quietHoursEnabled,
    int? quietStartHour,
    int? quietEndHour,
  }) => NotificationPrefs(
    sessionReminders: sessionReminders ?? this.sessionReminders,
    dailySummary: dailySummary ?? this.dailySummary,
    streakAlerts: streakAlerts ?? this.streakAlerts,
    blockingAlerts: blockingAlerts ?? this.blockingAlerts,
    weeklyReport: weeklyReport ?? this.weeklyReport,
    buddyUpdates: buddyUpdates ?? this.buddyUpdates,
    groupActivity: groupActivity ?? this.groupActivity,
    challengeInvites: challengeInvites ?? this.challengeInvites,
    quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
    quietStartHour: quietStartHour ?? this.quietStartHour,
    quietEndHour: quietEndHour ?? this.quietEndHour,
  );

  Map<String, dynamic> toJson() => {
    'sessionReminders': sessionReminders,
    'dailySummary': dailySummary,
    'streakAlerts': streakAlerts,
    'blockingAlerts': blockingAlerts,
    'weeklyReport': weeklyReport,
    'buddyUpdates': buddyUpdates,
    'groupActivity': groupActivity,
    'challengeInvites': challengeInvites,
    'quietHoursEnabled': quietHoursEnabled,
    'quietStartHour': quietStartHour,
    'quietEndHour': quietEndHour,
  };

  factory NotificationPrefs.fromJson(Map<String, dynamic> j) =>
      NotificationPrefs(
        sessionReminders: j['sessionReminders'] as bool? ?? true,
        dailySummary: j['dailySummary'] as bool? ?? true,
        streakAlerts: j['streakAlerts'] as bool? ?? true,
        blockingAlerts: j['blockingAlerts'] as bool? ?? false,
        weeklyReport: j['weeklyReport'] as bool? ?? true,
        buddyUpdates: j['buddyUpdates'] as bool? ?? true,
        groupActivity: j['groupActivity'] as bool? ?? true,
        challengeInvites: j['challengeInvites'] as bool? ?? true,
        quietHoursEnabled: j['quietHoursEnabled'] as bool? ?? true,
        quietStartHour: j['quietStartHour'] as int? ?? 22,
        quietEndHour: j['quietEndHour'] as int? ?? 7,
      );
}
