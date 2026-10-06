import 'package:flutter/material.dart';

/// How the app decides between the light and dark glass themes.
///
/// `system` follows the platform; the other two pin it. Stored by name so the
/// persisted value survives reordering of this enum.
enum ThemePreference {
  light('Light', Icons.light_mode_rounded, ThemeMode.light),
  system('System', Icons.brightness_auto_rounded, ThemeMode.system),
  dark('Dark', Icons.dark_mode_rounded, ThemeMode.dark);

  const ThemePreference(this.label, this.icon, this.mode);

  final String label;
  final IconData icon;
  final ThemeMode mode;

  static ThemePreference fromName(String? name) => values.firstWhere(
        (v) => v.name == name,
        orElse: () => ThemePreference.light,
      );
}

/// Who is using the app. Persona drives the defaults offered during onboarding
/// and the copy used across the app — see the master plan's persona matrix.
enum Persona {
  student(
    'Student',
    Icons.school_rounded,
    'High school, college, exam prep',
    'What do you study?',
    Color(0xFF7FA9FF),
  ),
  professional(
    'Professional',
    Icons.work_rounded,
    'Deep work, meetings, productivity',
    'What do you work on?',
    Color(0xFFB79CFF),
  ),
  parent(
    'Parent',
    Icons.family_restroom_rounded,
    "Manage my child's screen time",
    'What does your child study?',
    Color(0xFF8FE39B),
  );

  const Persona(this.label, this.icon, this.blurb, this.subjectPrompt, this.color);

  final String label;
  final IconData icon;
  final String blurb;
  final String subjectPrompt;
  final Color color;

  static Persona fromName(String? name) => values.firstWhere(
        (v) => v.name == name,
        orElse: () => Persona.student,
      );
}

/// The signed-in (or local-only) account.
@immutable
class UserProfile {
  const UserProfile({
    this.uid = '',
    this.displayName = '',
    this.persona = Persona.student,
    this.timezone = 'UTC',
    this.onboardingComplete = false,
    this.isAnonymous = true,
    this.avatarPath,
    this.dailyGoalMinutes = 180,
    this.createdAt,
  });

  final String uid;
  final String displayName;
  final Persona persona;
  final String timezone;
  final bool onboardingComplete;

  /// True while the user has not linked a real account. Anonymous users get
  /// everything except study groups and the leaderboard.
  final bool isAnonymous;
  final String? avatarPath;
  final int dailyGoalMinutes;
  final DateTime? createdAt;

  String get firstName {
    final n = displayName.trim();
    if (n.isEmpty) return 'there';
    final space = n.indexOf(' ');
    return space > 0 ? n.substring(0, space) : n;
  }

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (displayName.trim().isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.take(1).toString().toUpperCase();
    }
    return (parts.first.characters.take(1).toString() +
            parts.last.characters.take(1).toString())
        .toUpperCase();
  }

  UserProfile copyWith({
    String? uid,
    String? displayName,
    Persona? persona,
    String? timezone,
    bool? onboardingComplete,
    bool? isAnonymous,
    String? avatarPath,
    int? dailyGoalMinutes,
    DateTime? createdAt,
  }) =>
      UserProfile(
        uid: uid ?? this.uid,
        displayName: displayName ?? this.displayName,
        persona: persona ?? this.persona,
        timezone: timezone ?? this.timezone,
        onboardingComplete: onboardingComplete ?? this.onboardingComplete,
        isAnonymous: isAnonymous ?? this.isAnonymous,
        avatarPath: avatarPath ?? this.avatarPath,
        dailyGoalMinutes: dailyGoalMinutes ?? this.dailyGoalMinutes,
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'displayName': displayName,
        'persona': persona.name,
        'timezone': timezone,
        'onboardingComplete': onboardingComplete,
        'isAnonymous': isAnonymous,
        'avatarPath': avatarPath,
        'dailyGoalMinutes': dailyGoalMinutes,
        'createdAt': createdAt?.millisecondsSinceEpoch,
      };

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        uid: j['uid'] as String? ?? '',
        displayName: j['displayName'] as String? ?? '',
        persona: Persona.fromName(j['persona'] as String?),
        timezone: j['timezone'] as String? ?? 'UTC',
        onboardingComplete: j['onboardingComplete'] as bool? ?? false,
        isAnonymous: j['isAnonymous'] as bool? ?? true,
        avatarPath: j['avatarPath'] as String?,
        dailyGoalMinutes: j['dailyGoalMinutes'] as int? ?? 180,
        createdAt: j['createdAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(j['createdAt'] as int),
      );
}

/// Longest streak, totals and level — everything the Profile hero card needs.
@immutable
class GamificationStats {
  const GamificationStats({
    this.xp = 0,
    this.level = 1,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.totalFocusHours = 0,
    this.totalSessions = 0,
    this.badges = const <String>[],
  });

  final int xp;
  final int level;
  final int currentStreak;
  final int longestStreak;
  final double totalFocusHours;
  final int totalSessions;
  final List<String> badges;

  /// XP needed to clear the current level. Levels get progressively hungrier.
  int get xpForNext => 1000 + (level - 1) * 250;

  double get levelProgress => (xp / xpForNext).clamp(0.0, 1.0);

  GamificationStats copyWith({
    int? xp,
    int? level,
    int? currentStreak,
    int? longestStreak,
    double? totalFocusHours,
    int? totalSessions,
    List<String>? badges,
  }) =>
      GamificationStats(
        xp: xp ?? this.xp,
        level: level ?? this.level,
        currentStreak: currentStreak ?? this.currentStreak,
        longestStreak: longestStreak ?? this.longestStreak,
        totalFocusHours: totalFocusHours ?? this.totalFocusHours,
        totalSessions: totalSessions ?? this.totalSessions,
        badges: badges ?? this.badges,
      );

  /// Adds XP and rolls the level over as many times as the total allows.
  GamificationStats withXp(int delta) {
    var next = copyWith(xp: xp + delta);
    while (next.xp >= next.xpForNext) {
      next = next.copyWith(
        xp: next.xp - next.xpForNext,
        level: next.level + 1,
      );
    }
    return next;
  }

  Map<String, dynamic> toJson() => {
        'xp': xp,
        'level': level,
        'currentStreak': currentStreak,
        'longestStreak': longestStreak,
        'totalFocusHours': totalFocusHours,
        'totalSessions': totalSessions,
        'badges': badges,
      };

  factory GamificationStats.fromJson(Map<String, dynamic> j) => GamificationStats(
        xp: j['xp'] as int? ?? 0,
        level: j['level'] as int? ?? 1,
        currentStreak: j['currentStreak'] as int? ?? 0,
        longestStreak: j['longestStreak'] as int? ?? 0,
        totalFocusHours: (j['totalFocusHours'] as num?)?.toDouble() ?? 0,
        totalSessions: j['totalSessions'] as int? ?? 0,
        badges: (j['badges'] as List?)?.cast<String>() ?? const [],
      );
}
