import 'package:flutter/material.dart';

import '../../app/theme/color_tokens.dart';

/// Static demo content.
///
/// Everything here is replaced by Hive-backed repositories in Phase 1 of the
/// master plan; the shapes are deliberately close to the final models so the
/// swap is mechanical.
///
/// Note: every icon is a Material glyph rather than an emoji. Emoji render at
/// wildly different weights and sizes per platform and are the fastest way to
/// make an interface look assembled rather than designed.
class Subject {
  const Subject({
    required this.name,
    required this.icon,
    required this.color,
    required this.minutes,
    required this.weekDone,
    required this.weekTarget,
  });

  final String name;
  final IconData icon;
  final Color color;
  final int minutes;
  final double weekDone;
  final double weekTarget;

  double get weekProgress =>
      weekTarget == 0 ? 0 : (weekDone / weekTarget).clamp(0.0, 1.0);
}

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

  double get ratio => limit == 0 ? 0 : (minutes / limit).clamp(0.0, 1.0);
}

class DayBar {
  const DayBar(this.label, this.hours, {this.isToday = false});

  final String label;
  final double hours;
  final bool isToday;
}

class FeedGroup {
  const FeedGroup({required this.title, required this.icon, required this.rows});

  final String title;
  final IconData icon;
  final List<FeedRow> rows;
}

class FeedRow {
  const FeedRow({
    required this.name,
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.enabled,
    this.modes,
    this.modeIndex = 0,
  });

  final String name;
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final bool enabled;

  /// Optional exclusive modes rendered as radio chips.
  final List<String>? modes;
  final int modeIndex;
}

class WhitelistEntry {
  const WhitelistEntry({
    required this.name,
    required this.icon,
    required this.color,
    this.budgetMinutes,
    this.usedMinutes = 0,
  });

  final String name;
  final IconData icon;
  final Color color;
  final int? budgetMinutes;
  final int usedMinutes;

  bool get budgeted => budgetMinutes != null;

  double get usage => budgetMinutes == null || budgetMinutes == 0
      ? 0
      : (usedMinutes / budgetMinutes!).clamp(0.0, 1.0);
}

class RestrictionProfile {
  const RestrictionProfile({
    required this.name,
    required this.icon,
    required this.blockedApps,
    required this.dailyTargetHours,
    this.active = false,
  });

  final String name;
  final IconData icon;
  final int blockedApps;
  final double dailyTargetHours;
  final bool active;
}

class AmbientTile {
  const AmbientTile(this.name, this.icon, this.color);

  final String name;
  final IconData icon;
  final Color color;
}

class PomodoroPreset {
  const PomodoroPreset({
    required this.name,
    required this.icon,
    required this.focus,
    required this.shortBreak,
    required this.longBreak,
    required this.segments,
  });

  final String name;
  final IconData icon;
  final int focus;
  final int shortBreak;
  final int longBreak;
  final int segments;
}

class SettingRow {
  const SettingRow(this.icon, this.label, {this.trailing});

  final IconData icon;
  final String label;
  final String? trailing;
}

/// All demo content in one place.
class DemoData {
  const DemoData._();

  static const userName = 'Alex';
  static const userFullName = 'Alex Rivera';
  static const userInitials = 'AR';
  static const persona = 'Student';
  static const personaIcon = Icons.school_rounded;

  // Dashboard -----------------------------------------------------------------
  static const focusMinutesToday = 192;
  static const focusGoalMinutes = 300;
  static const pickups = 24;
  static const unlocks = 52;
  static const focusMinutesStat = 145;
  static const streakDays = 12;
  static const sessionCountToday = 3;
  static const weekTotalHours = 24.2;

  static const week = <DayBar>[
    DayBar('M', 3.2),
    DayBar('T', 4.1),
    DayBar('W', 2.6),
    DayBar('T', 5.0, isToday: true),
    DayBar('F', 3.8),
    DayBar('S', 1.9),
    DayBar('S', 3.2),
  ];

  /// 5 weeks x 7 days, 0..1 intensity. The tail is "today so far".
  static const heatmap = <List<double>>[
    [0.2, 0.6, 0.1, 0.8, 0.4, 0.0, 0.3],
    [0.5, 0.9, 0.3, 0.7, 0.6, 0.2, 0.1],
    [0.1, 0.4, 1.0, 0.5, 0.3, 0.0, 0.4],
    [0.7, 0.8, 0.2, 0.9, 0.5, 0.3, 0.2],
    [0.3, 0.5, 0.6, 0.64, 0.0, 0.0, 0.0],
  ];

  static const apps = <TrackedApp>[
    TrackedApp(
      name: 'Instagram',
      icon: Icons.photo_camera_rounded,
      color: Color(0xFFFF9FC4),
      minutes: 48,
      limit: 30,
      shielded: true,
    ),
    TrackedApp(
      name: 'WhatsApp',
      icon: Icons.chat_bubble_rounded,
      color: Color(0xFF8FE39B),
      minutes: 62,
      limit: 90,
      shielded: false,
    ),
    TrackedApp(
      name: 'YouTube',
      icon: Icons.smart_display_rounded,
      color: Color(0xFFFFB4AB),
      minutes: 95,
      limit: 45,
      shielded: true,
    ),
    TrackedApp(
      name: 'LinkedIn',
      icon: Icons.work_rounded,
      color: Color(0xFF7FA9FF),
      minutes: 18,
      limit: 30,
      shielded: false,
    ),
  ];

  static const subjects = <Subject>[
    Subject(
      name: 'Math',
      icon: Icons.square_foot_rounded,
      color: SubjectColors.math,
      minutes: 65,
      weekDone: 5.5,
      weekTarget: 7,
    ),
    Subject(
      name: 'Physics',
      icon: Icons.bolt_rounded,
      color: SubjectColors.physics,
      minutes: 52,
      weekDone: 3.2,
      weekTarget: 5,
    ),
    Subject(
      name: 'English',
      icon: Icons.menu_book_rounded,
      color: SubjectColors.english,
      minutes: 40,
      weekDone: 4,
      weekTarget: 4,
    ),
    Subject(
      name: 'History',
      icon: Icons.history_edu_rounded,
      color: SubjectColors.history,
      minutes: 35,
      weekDone: 1.5,
      weekTarget: 3,
    ),
  ];

  // Shield --------------------------------------------------------------------
  static const feedGroups = <FeedGroup>[
    FeedGroup(
      title: 'Meta Ecosystem',
      icon: Icons.groups_rounded,
      rows: [
        FeedRow(
          name: 'Instagram',
          icon: Icons.photo_camera_rounded,
          color: Color(0xFFFF9FC4),
          title: 'Block Reels Feed',
          description:
              'Removes the Reels tab and Explore algorithmic content. Stories, DMs and profile stay functional.',
          enabled: true,
        ),
        FeedRow(
          name: 'Facebook',
          icon: Icons.facebook_rounded,
          color: Color(0xFF7FA9FF),
          title: 'Block Watch Feed',
          description: 'Disables the infinite video loop in the Watch tab.',
          enabled: false,
        ),
      ],
    ),
    FeedGroup(
      title: 'Google Ecosystem',
      icon: Icons.play_circle_outline_rounded,
      rows: [
        FeedRow(
          name: 'YouTube',
          icon: Icons.smart_display_rounded,
          color: Color(0xFFFFB4AB),
          title: 'Block Shorts',
          description:
              'Hides the Shorts shelf and blocks the swipe-up player surface.',
          enabled: true,
        ),
      ],
    ),
    FeedGroup(
      title: 'ByteDance',
      icon: Icons.music_note_rounded,
      rows: [
        FeedRow(
          name: 'TikTok',
          icon: Icons.music_note_rounded,
          color: Color(0xFF8FE39B),
          title: 'Restrict TikTok',
          description: 'Choose how aggressively the feed is removed.',
          enabled: true,
          modes: ['Block Feed Only', 'Time Limit', 'Full App Block'],
          modeIndex: 0,
        ),
      ],
    ),
    FeedGroup(
      title: 'Twitter / X',
      icon: Icons.tag_rounded,
      rows: [
        FeedRow(
          name: 'X',
          icon: Icons.close_rounded,
          color: Color(0xFFB0BEC5),
          title: 'Block Explore & Trending',
          description: 'Removes the algorithmic discovery tabs.',
          enabled: false,
        ),
      ],
    ),
  ];

  static const alwaysAllowed = <WhitelistEntry>[
    WhitelistEntry(
      name: 'Phone',
      icon: Icons.call_rounded,
      color: Color(0xFF8FE39B),
    ),
    WhitelistEntry(
      name: 'Maps',
      icon: Icons.map_rounded,
      color: Color(0xFF8FE39B),
    ),
    WhitelistEntry(
      name: 'Calendar',
      icon: Icons.calendar_today_rounded,
      color: Color(0xFF8FE39B),
    ),
    WhitelistEntry(
      name: 'Clock',
      icon: Icons.alarm_rounded,
      color: Color(0xFF8FE39B),
    ),
  ];

  static const budgeted = <WhitelistEntry>[
    WhitelistEntry(
      name: 'Slack',
      icon: Icons.forum_rounded,
      color: Color(0xFF7FA9FF),
      budgetMinutes: 45,
      usedMinutes: 22,
    ),
    WhitelistEntry(
      name: 'Gmail',
      icon: Icons.mail_rounded,
      color: Color(0xFF7FA9FF),
      budgetMinutes: 30,
      usedMinutes: 26,
    ),
  ];

  static const blockedApps = <WhitelistEntry>[
    WhitelistEntry(
      name: 'TikTok',
      icon: Icons.music_note_rounded,
      color: Color(0xFFFFB4AB),
    ),
    WhitelistEntry(
      name: 'Instagram',
      icon: Icons.photo_camera_rounded,
      color: Color(0xFFFFB4AB),
    ),
    WhitelistEntry(
      name: 'Reddit',
      icon: Icons.forum_rounded,
      color: Color(0xFFFFB4AB),
    ),
    WhitelistEntry(
      name: 'YouTube',
      icon: Icons.smart_display_rounded,
      color: Color(0xFFFFB4AB),
    ),
  ];

  static const profiles = <RestrictionProfile>[
    RestrictionProfile(
      name: 'Exam Week',
      icon: Icons.local_fire_department_rounded,
      blockedApps: 14,
      dailyTargetHours: 6,
      active: true,
    ),
    RestrictionProfile(
      name: 'Regular Study',
      icon: Icons.menu_book_rounded,
      blockedApps: 8,
      dailyTargetHours: 4,
    ),
    RestrictionProfile(
      name: 'Weekend Relax',
      icon: Icons.beach_access_rounded,
      blockedApps: 3,
      dailyTargetHours: 2,
    ),
  ];

  // Focus ---------------------------------------------------------------------
  static const presets = <PomodoroPreset>[
    PomodoroPreset(
      name: 'Classic Pomodoro',
      icon: Icons.timer_rounded,
      focus: 25,
      shortBreak: 5,
      longBreak: 15,
      segments: 4,
    ),
    PomodoroPreset(
      name: 'Deep Work',
      icon: Icons.local_fire_department_rounded,
      focus: 50,
      shortBreak: 10,
      longBreak: 30,
      segments: 3,
    ),
    PomodoroPreset(
      name: 'Sprint',
      icon: Icons.bolt_rounded,
      focus: 15,
      shortBreak: 3,
      longBreak: 10,
      segments: 6,
    ),
    PomodoroPreset(
      name: 'Flow State',
      icon: Icons.self_improvement_rounded,
      focus: 90,
      shortBreak: 20,
      longBreak: 45,
      segments: 2,
    ),
  ];

  static const ambient = <AmbientTile>[
    AmbientTile('Rain', Icons.water_drop_rounded, Color(0xFF7FA9FF)),
    AmbientTile('White Noise', Icons.blur_on_rounded, Color(0xFFB0BEC5)),
    AmbientTile('Forest', Icons.forest_rounded, Color(0xFF8FE39B)),
    AmbientTile('Café', Icons.local_cafe_rounded, Color(0xFFFFC48A)),
  ];

  // Profile -------------------------------------------------------------------
  static const totalHours = 128.5;
  static const level = 14;
  static const xp = 2340;
  static const xpForNext = 3000;
  static const achievements = 8;
  static const achievementsTotal = 24;

  static const settings = <SettingRow>[
    SettingRow(Icons.groups_rounded, 'Study Groups', trailing: '3 active'),
    SettingRow(Icons.emoji_events_rounded, 'Achievements', trailing: '8 / 24'),
    SettingRow(Icons.leaderboard_rounded, 'Leaderboard', trailing: '#12'),
    SettingRow(Icons.lock_rounded, 'Strict Mode', trailing: 'Off'),
    SettingRow(Icons.notifications_active_rounded, 'Notifications'),
    SettingRow(Icons.shield_rounded, 'Data & Privacy'),
    SettingRow(Icons.info_rounded, 'About FocusForge', trailing: 'v0.1.0'),
  ];
}
