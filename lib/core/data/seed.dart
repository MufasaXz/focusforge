import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
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

/// The catalogue a fresh install starts from.
///
/// Nothing here is anybody's history, and nothing here is anybody's choices.
/// It is the reference content the app cannot render without — the subject
/// templates offered during onboarding, the badge definitions, the ambient
/// tracks, the Pomodoro presets. All of it is the same for every user and none
/// of it claims to be progress.
///
/// What is deliberately *not* here: the app list, the block rules, the
/// leaderboard, the study groups. Those are the user's own, and a seeded
/// version of any of them would be the app putting words in their mouth. The
/// numbers that used to live here — a demo account, 129 hours, a 12-day
/// streak, five weeks of invented heatmap history — are gone with them.
class SeedData {
  const SeedData._();

  static const subjects = <Subject>[
    Subject(
      id: 'math',
      name: 'Math',
      icon: Icons.square_foot_rounded,
      color: SubjectPalette.math,
      minutesToday: 65,
      weekDone: 5.5,
      weekTarget: 7,
    ),
    Subject(
      id: 'physics',
      name: 'Physics',
      icon: Icons.bolt_rounded,
      color: SubjectPalette.physics,
      minutesToday: 52,
      weekDone: 3.2,
      weekTarget: 5,
    ),
    Subject(
      id: 'english',
      name: 'English',
      icon: Icons.menu_book_rounded,
      color: SubjectPalette.english,
      minutesToday: 40,
      weekDone: 4,
      weekTarget: 4,
    ),
    Subject(
      id: 'history',
      name: 'History',
      icon: Icons.history_edu_rounded,
      color: SubjectPalette.history,
      minutesToday: 35,
      weekDone: 1.5,
      weekTarget: 3,
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
      unlockedAt: null,
    ),
    Achievement(
      id: 'week_warrior',
      name: 'Week Warrior',
      description: 'Focus every day for seven days.',
      icon: Icons.calendar_month_rounded,
      color: Color(0xFF7FA9FF),
      target: 7,
    ),
    Achievement(
      id: 'century_club',
      name: 'Century Club',
      description: 'Log 100 hours of deep work.',
      icon: Icons.military_tech_rounded,
      color: Color(0xFFFFD166),
      target: 100,
    ),
    Achievement(
      id: 'night_owl',
      name: 'Night Owl',
      description: 'Complete a session after 11pm.',
      icon: Icons.nightlight_round,
      color: Color(0xFFB79CFF),
      target: 1,
    ),
    Achievement(
      id: 'early_bird',
      name: 'Early Bird',
      description: 'Start a session before 6am.',
      icon: Icons.wb_twilight_rounded,
      color: Color(0xFFFFC48A),
      target: 1,
    ),
    Achievement(
      id: 'shield_bearer',
      name: 'Shield Bearer',
      description: 'Block 500 distracting feeds.',
      icon: Icons.shield_rounded,
      color: Color(0xFF8FE39B),
      target: 500,
    ),
    Achievement(
      id: 'deep_diver',
      name: 'Deep Diver',
      description: 'Complete a 90 minute block.',
      icon: Icons.self_improvement_rounded,
      color: Color(0xFF7FD8E8),
      target: 1,
    ),
    Achievement(
      id: 'steady_hand',
      name: 'Steady Hand',
      description: 'Finish 50 sessions without quitting early.',
      icon: Icons.check_circle_rounded,
      color: Color(0xFF8FE39B),
      target: 50,
    ),
    Achievement(
      id: 'month_king',
      name: 'Crown of Focus',
      description: 'Hold a 30 day streak.',
      icon: Icons.workspace_premium_rounded,
      color: Color(0xFFFFD166),
      target: 30,
    ),
    Achievement(
      id: 'hundred_hours',
      name: 'Triple Digits',
      description: 'Reach 100 total focus hours.',
      icon: Icons.timelapse_rounded,
      color: Color(0xFFB79CFF),
      target: 100,
    ),
    Achievement(
      id: 'marathon',
      name: 'Marathon Mind',
      description: 'Focus for 6 hours in one day.',
      icon: Icons.hiking_rounded,
      color: Color(0xFFFFC48A),
      target: 6,
    ),
    Achievement(
      id: 'breath_master',
      name: 'Breath Master',
      description: 'Walk away from 25 impulse opens.',
      icon: Icons.air_rounded,
      color: Color(0xFF7FD8E8),
      target: 25,
    ),
    Achievement(
      id: 'group_up',
      name: 'Better Together',
      description: 'Join your first study group.',
      icon: Icons.groups_rounded,
      color: Color(0xFF8FE39B),
      target: 1,
    ),
    Achievement(
      id: 'challenger',
      name: 'Challenger',
      description: 'Win a weekly challenge.',
      icon: Icons.emoji_events_rounded,
      color: Color(0xFFFFD166),
      target: 1,
    ),
    Achievement(
      id: 'perfectionist',
      name: 'Perfectionist',
      description: 'Hit every subject target in one week.',
      icon: Icons.star_rounded,
      color: Color(0xFFB79CFF),
      target: 1,
    ),
    Achievement(
      id: 'unplugged',
      name: 'Unplugged',
      description: 'Complete a 4 hour strict session.',
      icon: Icons.do_not_disturb_on_rounded,
      color: Color(0xFFFF9FC4),
      target: 1,
    ),
    Achievement(
      id: 'subject_master',
      name: 'Subject Master',
      description: 'Hit 20 hours in a single subject.',
      icon: Icons.school_rounded,
      color: Color(0xFF7FA9FF),
      target: 20,
    ),
    Achievement(
      id: 'consistency',
      name: 'Metronome',
      description: 'Focus at the same time 10 days running.',
      icon: Icons.schedule_rounded,
      color: Color(0xFF8FE39B),
      target: 10,
    ),
    Achievement(
      id: 'social_butterfly',
      name: 'Study Circle',
      description: 'Join three study groups.',
      icon: Icons.hub_rounded,
      color: Color(0xFF7FD8E8),
      target: 3,
    ),
    Achievement(
      id: 'top_ten',
      name: 'Top Ten',
      description: 'Reach the global top ten.',
      icon: Icons.leaderboard_rounded,
      color: Color(0xFFFFD166),
      target: 1,
    ),
    Achievement(
      id: 'year_one',
      name: 'One Year In',
      description: 'Use FocusForge for a full year.',
      icon: Icons.cake_rounded,
      color: Color(0xFFFFC48A),
      target: 1,
    ),
    Achievement(
      id: 'zero_quit',
      name: 'No Quit November',
      description: 'A month with no abandoned sessions.',
      icon: Icons.verified_rounded,
      color: Color(0xFF8FE39B),
      target: 1,
    ),
    Achievement(
      id: 'night_shift',
      name: 'Night Shift',
      description: 'Log 10 late-night sessions.',
      icon: Icons.bedtime_rounded,
      color: Color(0xFFB79CFF),
      target: 10,
    ),
    Achievement(
      id: 'phoenix',
      name: 'Phoenix',
      description: 'Rebuild a streak after losing one.',
      icon: Icons.auto_awesome_rounded,
      color: Color(0xFFFF9FC4),
      target: 1,
    ),
  ];

  static const notifications = NotificationPrefs();

  // -- Onboarding ------------------------------------------------------------

  static const studentSubjects = <SubjectTemplate>[
    SubjectTemplate('Math', Icons.square_foot_rounded, SubjectPalette.math),
    SubjectTemplate('Physics', Icons.bolt_rounded, SubjectPalette.physics),
    SubjectTemplate('English', Icons.menu_book_rounded, SubjectPalette.english),
    SubjectTemplate('History', Icons.history_edu_rounded, SubjectPalette.history),
    SubjectTemplate('Chemistry', Icons.science_rounded, SubjectPalette.chemistry),
    SubjectTemplate('Biology', Icons.biotech_rounded, SubjectPalette.biology),
    SubjectTemplate('Computer Science', Icons.code_rounded, Color(0xFF7FC8FF)),
    SubjectTemplate('Art', Icons.palette_rounded, Color(0xFFFFB3D9)),
  ];

  static const professionalSubjects = <SubjectTemplate>[
    SubjectTemplate('Deep Work', Icons.psychology_rounded, SubjectPalette.math),
    SubjectTemplate('Planning', Icons.insights_rounded, SubjectPalette.physics),
    SubjectTemplate('Writing', Icons.edit_note_rounded, SubjectPalette.english),
    SubjectTemplate('Coding', Icons.code_rounded, Color(0xFF7FC8FF)),
    SubjectTemplate('Meetings', Icons.call_rounded, SubjectPalette.history),
    SubjectTemplate('Email', Icons.mail_rounded, SubjectPalette.chemistry),
  ];

  static const parentSubjects = <SubjectTemplate>[
    SubjectTemplate('Homework', Icons.assignment_rounded, SubjectPalette.math),
    SubjectTemplate('Reading', Icons.menu_book_rounded, SubjectPalette.english),
    SubjectTemplate('Revision', Icons.refresh_rounded, SubjectPalette.physics),
    SubjectTemplate('Creative', Icons.palette_rounded, Color(0xFFFFB3D9)),
  ];

  static List<SubjectTemplate> templatesFor(Persona p) => switch (p) {
        Persona.student => studentSubjects,
        Persona.professional => professionalSubjects,
        Persona.parent => parentSubjects,
      };

  /// The daily goal before the user has chosen one.
  ///
  /// A product default, not a claim about anyone: the goal step treats this
  /// exact value as "not chosen yet" and opens on the persona's recommended
  /// suggestion instead. Any other number is a deliberate choice and is left
  /// alone.
  static const focusGoalMinutes = 300;

  /// Daily-goal suggestions, in minutes — Light / Recommended / Intense.
  static List<int> goalSuggestions(Persona p) => switch (p) {
        Persona.student => const [120, 180, 300],
        Persona.professional => const [120, 240, 360],
        Persona.parent => const [60, 120, 180],
      };

}
