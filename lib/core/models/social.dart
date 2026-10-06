import 'package:flutter/material.dart';

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
    this.progress = 0,
    this.unlockedAt,
  });

  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final double target;
  final double progress;
  final DateTime? unlockedAt;

  bool get unlocked => unlockedAt != null;

  double get ratio => target <= 0 ? 0 : (progress / target).clamp(0.0, 1.0);

  Achievement copyWith({double? progress, DateTime? unlockedAt}) => Achievement(
        id: id,
        name: name,
        description: description,
        icon: icon,
        color: color,
        target: target,
        progress: progress ?? this.progress,
        unlockedAt: unlockedAt ?? this.unlockedAt,
      );
}

/// A study group the user belongs to.
@immutable
class StudyGroup {
  const StudyGroup({
    required this.id,
    required this.name,
    required this.icon,
    required this.memberCount,
    required this.weeklyHours,
    required this.targetHours,
    this.inviteCode = '',
  });

  final String id;
  final String name;
  final IconData icon;
  final int memberCount;
  final double weeklyHours;
  final double targetHours;
  final String inviteCode;

  double get progress =>
      targetHours <= 0 ? 0 : (weeklyHours / targetHours).clamp(0.0, 1.0);
}

/// A member row inside a group, or a row on the leaderboard.
@immutable
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.name,
    required this.hours,
    this.isMe = false,
    this.group,
  });

  final String name;
  final double hours;
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
  }) =>
      NotificationPrefs(
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

  factory NotificationPrefs.fromJson(Map<String, dynamic> j) => NotificationPrefs(
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
