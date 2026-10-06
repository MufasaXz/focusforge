import 'package:flutter/material.dart';

import '../../app/theme/color_tokens.dart';
import '../models/shield.dart';
import '../models/social.dart';
import '../models/study.dart';
import '../models/user.dart';

// Re-exported so a screen can pull its content and its types from one import.
export '../models/icon_registry.dart';
export '../models/shield.dart';
export '../models/social.dart';
export '../models/study.dart';
export '../models/user.dart';

/// One day in the focus heatmap, carrying its own date so cells can be
/// long-pressed for a real value instead of a bare colour swatch.
@immutable
class HeatCell {
  const HeatCell({required this.date, required this.hours});

  final DateTime date;
  final double hours;

  /// 0..1 bucket used to pick the swatch.
  double get intensity => (hours / 6).clamp(0.0, 1.0);

  String get weekday => const [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ][date.weekday - 1];
}

/// A suggested subject during onboarding, per persona.
@immutable
class SubjectTemplate {
  const SubjectTemplate(this.name, this.icon, this.color);

  final String name;
  final IconData icon;
  final Color color;
}

/// A package the onboarding flow can offer to block.
@immutable
class DetectableApp {
  const DetectableApp({
    required this.name,
    required this.packageId,
    required this.icon,
    required this.color,
    required this.tier,
  });

  final String name;
  final String packageId;
  final IconData icon;
  final Color color;

  /// 0 = high distraction, 1 = moderate, 2 = productive.
  final int tier;
}

/// The starting content for a fresh install.
///
/// This is what the repositories seed themselves with on first launch; after
/// that the local store is authoritative. Keeping it in one file means the
/// demo data is obviously demo data, and deleting it later is a one-line
/// change rather than an archaeology exercise.
class SeedData {
  const SeedData._();

  // -- Account ---------------------------------------------------------------

  static const userName = 'Alex';
  static const userFullName = 'Alex Rivera';
  static const userInitials = 'AR';
  static const persona = 'Student';
  static const personaIcon = Icons.school_rounded;

  static UserProfile get user => UserProfile(
        uid: 'demo-local',
        displayName: userFullName,
        persona: Persona.student,
        timezone: 'Asia/Kolkata',
        onboardingComplete: true,
        isAnonymous: true,
        dailyGoalMinutes: focusGoalMinutes,
        createdAt: DateTime(2026, 1, 6),
      );

  static GamificationStats get stats => GamificationStats(
        xp: xp,
        level: level,
        currentStreak: streakDays,
        longestStreak: 23,
        totalFocusHours: totalHours,
        totalSessions: 412,
        badges: badges
            .where((a) => a.unlocked)
            .map((a) => a.id)
            .toList(growable: false),
      );

  // -- Dashboard -------------------------------------------------------------

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

  /// Five weeks of intensity buckets, oldest row first. Legacy shape — kept
  /// for the pre-provider heatmap widget. New code uses [heatmapCells].
  static const heatmap = <List<double>>[
    [0.2, 0.6, 0.1, 0.8, 0.4, 0.0, 0.3],
    [0.5, 0.9, 0.3, 0.7, 0.6, 0.2, 0.1],
    [0.1, 0.4, 1.0, 0.5, 0.3, 0.0, 0.4],
    [0.7, 0.8, 0.2, 0.9, 0.5, 0.3, 0.2],
    [0.3, 0.5, 0.6, 0.64, 0.0, 0.0, 0.0],
  ];

  /// Five weeks of dated history ending today, oldest row first.
  static List<List<HeatCell>> heatmapCells() {
    const hours = <List<double>>[
      [1.2, 3.6, 0.6, 4.8, 2.4, 0.0, 1.8],
      [3.0, 5.4, 1.8, 4.2, 3.6, 1.2, 0.6],
      [0.6, 2.4, 6.0, 3.0, 1.8, 0.0, 2.4],
      [4.2, 4.8, 1.2, 5.4, 3.0, 1.8, 1.2],
      [1.8, 3.0, 3.6, 3.84, 0.0, 0.0, 0.0],
    ];
    final today = DateTime.now();
    final start = today.subtract(const Duration(days: 34));
    return List.generate(hours.length, (row) {
      return List.generate(7, (col) {
        final offset = row * 7 + col;
        return HeatCell(
          date: DateTime(start.year, start.month, start.day + offset),
          hours: hours[row][col],
        );
      });
    });
  }

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
      id: 'math',
      name: 'Math',
      icon: Icons.square_foot_rounded,
      color: SubjectColors.math,
      minutesToday: 65,
      weekDone: 5.5,
      weekTarget: 7,
    ),
    Subject(
      id: 'physics',
      name: 'Physics',
      icon: Icons.bolt_rounded,
      color: SubjectColors.physics,
      minutesToday: 52,
      weekDone: 3.2,
      weekTarget: 5,
    ),
    Subject(
      id: 'english',
      name: 'English',
      icon: Icons.menu_book_rounded,
      color: SubjectColors.english,
      minutesToday: 40,
      weekDone: 4,
      weekTarget: 4,
    ),
    Subject(
      id: 'history',
      name: 'History',
      icon: Icons.history_edu_rounded,
      color: SubjectColors.history,
      minutesToday: 35,
      weekDone: 1.5,
      weekTarget: 3,
    ),
  ];

  // -- Shield ----------------------------------------------------------------

  static const feedGroups = <FeedGroup>[
    FeedGroup(
      title: 'Meta Ecosystem',
      icon: Icons.groups_rounded,
      rows: [
        FeedRow(
          id: 'instagram_reels',
          appName: 'Instagram',
          icon: Icons.photo_camera_rounded,
          color: Color(0xFFFF9FC4),
          title: 'Block Reels Feed',
          description:
              'Removes the Reels tab and Explore algorithmic content. Stories, DMs and profile stay functional.',
          enabled: true,
        ),
        FeedRow(
          id: 'facebook_watch',
          appName: 'Facebook',
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
          id: 'youtube_shorts',
          appName: 'YouTube',
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
          id: 'tiktok_feed',
          appName: 'TikTok',
          icon: Icons.music_note_rounded,
          color: Color(0xFF8FE39B),
          title: 'Restrict TikTok',
          description: 'Choose how aggressively the feed is removed.',
          enabled: true,
          modes: ShieldMode.values,
        ),
      ],
    ),
    FeedGroup(
      title: 'Twitter / X',
      icon: Icons.tag_rounded,
      rows: [
        FeedRow(
          id: 'twitter_trending',
          appName: 'X',
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
      id: 'phone',
      name: 'Phone',
      icon: Icons.call_rounded,
      color: Color(0xFF8FE39B),
      tier: WhitelistTier.alwaysAllowed,
    ),
    WhitelistEntry(
      id: 'maps',
      name: 'Maps',
      icon: Icons.map_rounded,
      color: Color(0xFF8FE39B),
      tier: WhitelistTier.alwaysAllowed,
    ),
    WhitelistEntry(
      id: 'calendar',
      name: 'Calendar',
      icon: Icons.calendar_today_rounded,
      color: Color(0xFF8FE39B),
      tier: WhitelistTier.alwaysAllowed,
    ),
    WhitelistEntry(
      id: 'clock',
      name: 'Clock',
      icon: Icons.alarm_rounded,
      color: Color(0xFF8FE39B),
      tier: WhitelistTier.alwaysAllowed,
    ),
  ];

  static const budgeted = <WhitelistEntry>[
    WhitelistEntry(
      id: 'slack',
      name: 'Slack',
      icon: Icons.forum_rounded,
      color: Color(0xFF7FA9FF),
      tier: WhitelistTier.budgeted,
      budgetMinutes: 45,
      usedMinutes: 22,
    ),
    WhitelistEntry(
      id: 'gmail',
      name: 'Gmail',
      icon: Icons.mail_rounded,
      color: Color(0xFF7FA9FF),
      tier: WhitelistTier.budgeted,
      budgetMinutes: 30,
      usedMinutes: 26,
    ),
  ];

  static const blockedApps = <WhitelistEntry>[
    WhitelistEntry(
      id: 'tiktok',
      name: 'TikTok',
      icon: Icons.music_note_rounded,
      color: Color(0xFFFFB4AB),
      tier: WhitelistTier.blocked,
    ),
    WhitelistEntry(
      id: 'instagram',
      name: 'Instagram',
      icon: Icons.photo_camera_rounded,
      color: Color(0xFFFFB4AB),
      tier: WhitelistTier.blocked,
    ),
    WhitelistEntry(
      id: 'reddit',
      name: 'Reddit',
      icon: Icons.forum_rounded,
      color: Color(0xFFFFB4AB),
      tier: WhitelistTier.blocked,
    ),
    WhitelistEntry(
      id: 'youtube',
      name: 'YouTube',
      icon: Icons.smart_display_rounded,
      color: Color(0xFFFFB4AB),
      tier: WhitelistTier.blocked,
    ),
  ];

  /// The whitelist grouped by tier, which is how the screen renders it.
  static const whitelistTiers = <WhitelistTier, List<WhitelistEntry>>{
    WhitelistTier.alwaysAllowed: alwaysAllowed,
    WhitelistTier.budgeted: budgeted,
    WhitelistTier.blocked: blockedApps,
  };

  static const profiles = <RestrictionProfile>[
    RestrictionProfile(
      id: 'exam_week',
      name: 'Exam Week',
      icon: Icons.local_fire_department_rounded,
      blockedApps: 14,
      dailyTargetHours: 6,
      active: true,
      schedules: ['Mon–Sun 07:00–22:00'],
    ),
    RestrictionProfile(
      id: 'regular',
      name: 'Regular Study',
      icon: Icons.menu_book_rounded,
      blockedApps: 8,
      dailyTargetHours: 4,
      schedules: ['Mon–Fri 16:00–21:00'],
    ),
    RestrictionProfile(
      id: 'weekend',
      name: 'Weekend Relax',
      icon: Icons.beach_access_rounded,
      blockedApps: 3,
      dailyTargetHours: 2,
    ),
  ];

  // -- Focus -----------------------------------------------------------------

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

  /// Ids must match the filenames the audio assets were saved under.
  static const ambient = <AmbientSound>[
    AmbientSound(
      id: 'rain',
      name: 'Rain',
      icon: Icons.water_drop_rounded,
      color: Color(0xFF7FA9FF),
      asset: 'assets/audio/rain.mp3',
    ),
    AmbientSound(
      id: 'forest',
      name: 'Forest',
      icon: Icons.forest_rounded,
      color: Color(0xFF8FE39B),
      asset: 'assets/audio/forest.mp3',
    ),
    AmbientSound(
      id: 'cafe',
      name: 'Café',
      icon: Icons.local_cafe_rounded,
      color: Color(0xFFFFC48A),
      asset: 'assets/audio/cafe.mp3',
    ),
    AmbientSound(
      id: 'waves',
      name: 'Waves',
      icon: Icons.waves_rounded,
      color: Color(0xFF7FD8E8),
      asset: 'assets/audio/waves.mp3',
    ),
    AmbientSound(
      id: 'fire',
      name: 'Fireplace',
      icon: Icons.local_fire_department_rounded,
      color: Color(0xFFFF9FC4),
      asset: 'assets/audio/fire.mp3',
    ),
    AmbientSound(
      id: 'noise',
      name: 'Brown Noise',
      icon: Icons.blur_on_rounded,
      color: Color(0xFFB0BEC5),
      asset: 'assets/audio/noise.mp3',
    ),
  ];

  /// Same ordering as [ambient] — kept as a convenience for old call sites.
  static const ambientTiles = ambient;

  // -- Gamification ----------------------------------------------------------

  /// Every badge in the app, locked and unlocked.
  static const badges = <Achievement>[
    Achievement(
      id: 'first_focus',
      name: 'First Spark',
      description: 'Finish your first focus session.',
      icon: Icons.local_fire_department_rounded,
      color: Color(0xFFFFC48A),
      target: 1,
      progress: 1,
      unlockedAt: null,
    ),
    Achievement(
      id: 'week_warrior',
      name: 'Week Warrior',
      description: 'Focus every day for seven days.',
      icon: Icons.calendar_month_rounded,
      color: Color(0xFF7FA9FF),
      target: 7,
      progress: 7,
    ),
    Achievement(
      id: 'century_club',
      name: 'Century Club',
      description: 'Log 100 hours of deep work.',
      icon: Icons.military_tech_rounded,
      color: Color(0xFFFFD166),
      target: 100,
      progress: 128.5,
    ),
    Achievement(
      id: 'night_owl',
      name: 'Night Owl',
      description: 'Complete a session after 11pm.',
      icon: Icons.nightlight_round,
      color: Color(0xFFB79CFF),
      target: 1,
      progress: 1,
    ),
    Achievement(
      id: 'early_bird',
      name: 'Early Bird',
      description: 'Start a session before 6am.',
      icon: Icons.wb_twilight_rounded,
      color: Color(0xFFFFC48A),
      target: 1,
      progress: 1,
    ),
    Achievement(
      id: 'shield_bearer',
      name: 'Shield Bearer',
      description: 'Block 500 distracting feeds.',
      icon: Icons.shield_rounded,
      color: Color(0xFF8FE39B),
      target: 500,
      progress: 500,
    ),
    Achievement(
      id: 'deep_diver',
      name: 'Deep Diver',
      description: 'Complete a 90 minute block.',
      icon: Icons.self_improvement_rounded,
      color: Color(0xFF7FD8E8),
      target: 1,
      progress: 1,
    ),
    Achievement(
      id: 'steady_hand',
      name: 'Steady Hand',
      description: 'Finish 50 sessions without quitting early.',
      icon: Icons.check_circle_rounded,
      color: Color(0xFF8FE39B),
      target: 50,
      progress: 50,
    ),
    Achievement(
      id: 'month_king',
      name: 'Crown of Focus',
      description: 'Hold a 30 day streak.',
      icon: Icons.workspace_premium_rounded,
      color: Color(0xFFFFD166),
      target: 30,
      progress: 12,
    ),
    Achievement(
      id: 'hundred_hours',
      name: 'Triple Digits',
      description: 'Reach 100 total focus hours.',
      icon: Icons.timelapse_rounded,
      color: Color(0xFFB79CFF),
      target: 100,
      progress: 128.5,
    ),
    Achievement(
      id: 'marathon',
      name: 'Marathon Mind',
      description: 'Focus for 6 hours in one day.',
      icon: Icons.hiking_rounded,
      color: Color(0xFFFFC48A),
      target: 6,
      progress: 5,
    ),
    Achievement(
      id: 'breath_master',
      name: 'Breath Master',
      description: 'Walk away from 25 impulse opens.',
      icon: Icons.air_rounded,
      color: Color(0xFF7FD8E8),
      target: 25,
      progress: 9,
    ),
    Achievement(
      id: 'group_up',
      name: 'Better Together',
      description: 'Join your first study group.',
      icon: Icons.groups_rounded,
      color: Color(0xFF8FE39B),
      target: 1,
      progress: 2,
    ),
    Achievement(
      id: 'challenger',
      name: 'Challenger',
      description: 'Win a weekly challenge.',
      icon: Icons.emoji_events_rounded,
      color: Color(0xFFFFD166),
      target: 1,
      progress: 0,
    ),
    Achievement(
      id: 'perfectionist',
      name: 'Perfectionist',
      description: 'Hit every subject target in one week.',
      icon: Icons.star_rounded,
      color: Color(0xFFB79CFF),
      target: 1,
      progress: 0,
    ),
    Achievement(
      id: 'unplugged',
      name: 'Unplugged',
      description: 'Complete a 4 hour strict session.',
      icon: Icons.do_not_disturb_on_rounded,
      color: Color(0xFFFF9FC4),
      target: 1,
      progress: 0,
    ),
    Achievement(
      id: 'subject_master',
      name: 'Subject Master',
      description: 'Hit 20 hours in a single subject.',
      icon: Icons.school_rounded,
      color: Color(0xFF7FA9FF),
      target: 20,
      progress: 14,
    ),
    Achievement(
      id: 'consistency',
      name: 'Metronome',
      description: 'Focus at the same time 10 days running.',
      icon: Icons.schedule_rounded,
      color: Color(0xFF8FE39B),
      target: 10,
      progress: 4,
    ),
    Achievement(
      id: 'social_butterfly',
      name: 'Study Circle',
      description: 'Join three study groups.',
      icon: Icons.hub_rounded,
      color: Color(0xFF7FD8E8),
      target: 3,
      progress: 2,
    ),
    Achievement(
      id: 'top_ten',
      name: 'Top Ten',
      description: 'Reach the global top ten.',
      icon: Icons.leaderboard_rounded,
      color: Color(0xFFFFD166),
      target: 1,
      progress: 0,
    ),
    Achievement(
      id: 'year_one',
      name: 'One Year In',
      description: 'Use FocusForge for a full year.',
      icon: Icons.cake_rounded,
      color: Color(0xFFFFC48A),
      target: 1,
      progress: 0,
    ),
    Achievement(
      id: 'zero_quit',
      name: 'No Quit November',
      description: 'A month with no abandoned sessions.',
      icon: Icons.verified_rounded,
      color: Color(0xFF8FE39B),
      target: 1,
      progress: 0,
    ),
    Achievement(
      id: 'night_shift',
      name: 'Night Shift',
      description: 'Log 10 late-night sessions.',
      icon: Icons.bedtime_rounded,
      color: Color(0xFFB79CFF),
      target: 10,
      progress: 3,
    ),
    Achievement(
      id: 'phoenix',
      name: 'Phoenix',
      description: 'Rebuild a streak after losing one.',
      icon: Icons.auto_awesome_rounded,
      color: Color(0xFFFF9FC4),
      target: 1,
      progress: 0,
    ),
  ];

  static const groups = <StudyGroup>[
    StudyGroup(
      id: 'physics_squad',
      name: 'Physics Squad',
      icon: Icons.science_rounded,
      memberCount: 5,
      weeklyHours: 48,
      targetHours: 60,
      inviteCode: 'PHY-4821',
    ),
    StudyGroup(
      id: 'math_crew',
      name: 'Math Study Crew',
      icon: Icons.square_foot_rounded,
      memberCount: 3,
      weeklyHours: 16,
      targetHours: 32,
      inviteCode: 'MTH-9134',
    ),
  ];

  static const leaderboard = <LeaderboardEntry>[
    LeaderboardEntry(name: 'Sarah K.', hours: 14.2),
    LeaderboardEntry(name: 'You', hours: 12.8, isMe: true),
    LeaderboardEntry(name: 'Mike R.', hours: 11.5),
    LeaderboardEntry(name: 'Emma T.', hours: 10.2),
    LeaderboardEntry(name: 'James P.', hours: 9.8),
    LeaderboardEntry(name: 'Luna S.', hours: 8.4),
    LeaderboardEntry(name: 'Diego M.', hours: 7.9),
    LeaderboardEntry(name: 'Priya N.', hours: 7.1),
  ];

  static const notifications = NotificationPrefs();

  // -- Onboarding ------------------------------------------------------------

  static const studentSubjects = <SubjectTemplate>[
    SubjectTemplate('Math', Icons.square_foot_rounded, SubjectColors.math),
    SubjectTemplate('Physics', Icons.bolt_rounded, SubjectColors.physics),
    SubjectTemplate('English', Icons.menu_book_rounded, SubjectColors.english),
    SubjectTemplate('History', Icons.history_edu_rounded, SubjectColors.history),
    SubjectTemplate('Chemistry', Icons.science_rounded, SubjectColors.chemistry),
    SubjectTemplate('Biology', Icons.biotech_rounded, SubjectColors.biology),
    SubjectTemplate('Computer Science', Icons.code_rounded, Color(0xFF7FC8FF)),
    SubjectTemplate('Art', Icons.palette_rounded, Color(0xFFFFB3D9)),
  ];

  static const professionalSubjects = <SubjectTemplate>[
    SubjectTemplate('Deep Work', Icons.psychology_rounded, SubjectColors.math),
    SubjectTemplate('Planning', Icons.insights_rounded, SubjectColors.physics),
    SubjectTemplate('Writing', Icons.edit_note_rounded, SubjectColors.english),
    SubjectTemplate('Coding', Icons.code_rounded, Color(0xFF7FC8FF)),
    SubjectTemplate('Meetings', Icons.call_rounded, SubjectColors.history),
    SubjectTemplate('Email', Icons.mail_rounded, SubjectColors.chemistry),
  ];

  static const parentSubjects = <SubjectTemplate>[
    SubjectTemplate('Homework', Icons.assignment_rounded, SubjectColors.math),
    SubjectTemplate('Reading', Icons.menu_book_rounded, SubjectColors.english),
    SubjectTemplate('Revision', Icons.refresh_rounded, SubjectColors.physics),
    SubjectTemplate('Creative', Icons.palette_rounded, Color(0xFFFFB3D9)),
  ];

  static List<SubjectTemplate> templatesFor(Persona p) => switch (p) {
        Persona.student => studentSubjects,
        Persona.professional => professionalSubjects,
        Persona.parent => parentSubjects,
      };

  /// Daily-goal suggestions, in minutes — Light / Recommended / Intense.
  static List<int> goalSuggestions(Persona p) => switch (p) {
        Persona.student => const [120, 180, 300],
        Persona.professional => const [120, 240, 360],
        Persona.parent => const [60, 120, 180],
      };

  static const detectableApps = <DetectableApp>[
    DetectableApp(
      name: 'Instagram',
      packageId: 'com.instagram.android',
      icon: Icons.photo_camera_rounded,
      color: Color(0xFFFF9FC4),
      tier: 0,
    ),
    DetectableApp(
      name: 'TikTok',
      packageId: 'com.zhiliaoapp.musically',
      icon: Icons.music_note_rounded,
      color: Color(0xFF8FE39B),
      tier: 0,
    ),
    DetectableApp(
      name: 'X',
      packageId: 'com.twitter.android',
      icon: Icons.close_rounded,
      color: Color(0xFFB0BEC5),
      tier: 0,
    ),
    DetectableApp(
      name: 'YouTube',
      packageId: 'com.google.android.youtube',
      icon: Icons.smart_display_rounded,
      color: Color(0xFFFFB4AB),
      tier: 0,
    ),
    DetectableApp(
      name: 'Snapchat',
      packageId: 'com.snapchat.android',
      icon: Icons.chat_bubble_rounded,
      color: Color(0xFFFFD166),
      tier: 0,
    ),
    DetectableApp(
      name: 'Reddit',
      packageId: 'com.reddit.frontpage',
      icon: Icons.forum_rounded,
      color: Color(0xFFFFC48A),
      tier: 0,
    ),
    DetectableApp(
      name: 'Facebook',
      packageId: 'com.facebook.katana',
      icon: Icons.facebook_rounded,
      color: Color(0xFF7FA9FF),
      tier: 0,
    ),
    DetectableApp(
      name: 'WhatsApp',
      packageId: 'com.whatsapp',
      icon: Icons.chat_rounded,
      color: Color(0xFF8FE39B),
      tier: 1,
    ),
    DetectableApp(
      name: 'Telegram',
      packageId: 'org.telegram.messenger',
      icon: Icons.send_rounded,
      color: Color(0xFF7FD8E8),
      tier: 1,
    ),
    DetectableApp(
      name: 'Discord',
      packageId: 'com.discord',
      icon: Icons.headset_mic_rounded,
      color: Color(0xFFB79CFF),
      tier: 1,
    ),
    DetectableApp(
      name: 'Google Docs',
      packageId: 'com.google.android.apps.docs',
      icon: Icons.description_rounded,
      color: Color(0xFF7FA9FF),
      tier: 2,
    ),
    DetectableApp(
      name: 'Notion',
      packageId: 'notion.id',
      icon: Icons.sticky_note_2_rounded,
      color: Color(0xFFB0BEC5),
      tier: 2,
    ),
    DetectableApp(
      name: 'Calculator',
      packageId: 'com.google.android.calculator',
      icon: Icons.calculate_rounded,
      color: Color(0xFF8FE39B),
      tier: 2,
    ),
  ];

  // -- Legacy aliases --------------------------------------------------------
  // These mirror the pre-provider constants so screens that have not yet been
  // migrated keep compiling. Delete once every screen reads from a provider.

  static const totalHours = 128.5;
  static const level = 14;
  static const xp = 2340;
  static const xpForNext = 3000;

  /// Count of unlocked badges. Superseded by `badges.where(unlocked).length`.
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

/// A row in the Profile settings list. Superseded by the router-driven
/// `_SettingTile` in the settings feature.
class SettingRow {
  const SettingRow(this.icon, this.label, {this.trailing});

  final IconData icon;
  final String label;
  final String? trailing;
}

/// The seed content used to be called `DemoData`. The alias keeps older call
/// sites compiling while screens migrate to the Riverpod providers.
typedef DemoData = SeedData;

/// Old name for [AmbientSound].
typedef AmbientTile = AmbientSound;
