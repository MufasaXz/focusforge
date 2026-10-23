import 'package:flutter/material.dart';

import '../services/profile_photo.dart';

/// How the app decides between the light and dark glass themes.
///
/// `system` follows the platform; the other two pin it. Stored by name so the
/// persisted value survives reordering of this enum.
enum ThemePreference {
  light('Day', Icons.light_mode_rounded, ThemeMode.light),
  system('System', Icons.brightness_auto_rounded, ThemeMode.system),
  dark('Dark', Icons.dark_mode_rounded, ThemeMode.dark);

  const ThemePreference(this.label, this.icon, this.mode);

  final String label;
  final IconData icon;
  final ThemeMode mode;

  /// The stored preference, or [ThemePreference.system] when there is none.
  ///
  /// The fallback is the same one [ThemeNotifier.build] uses, so a first launch
  /// and an unreadable stored value land in the same place — the device
  /// setting — rather than one of them snapping to light.
  static ThemePreference fromName(String? name) => values.firstWhere(
    (v) => v.name == name,
    orElse: () => ThemePreference.system,
  );
}

/// A named seed pair the whole palette derives from.
///
/// One seed generates the palette — but not the *same* seed in both
/// brightnesses. A colour that reads as a confident brand hue on white turns
/// muddy on a near-black surface, because M3 has to desaturate it to keep
/// contrast; a second, brighter seed for dark is the fix, rather than a second
/// hand-tuned palette. Each theme therefore uses its own seed in the pair.
///
/// The values live here rather than in the theme file because a palette is a
/// *preference* — it is stored by name and rebuilt on launch — and the theme
/// file should stay a pure function of what it is handed.
enum AppPalette {
  parchment('Parchment', Color(0xFF766747), Color(0xFFD9B98A)),
  ember('Ember', Color(0xFFE8672A), Color(0xFFFF8A50)),
  tide('Tide', Color(0xFF1B6FD6), Color(0xFF6FA8FF)),
  grove('Grove', Color(0xFF2E7D4F), Color(0xFF6FD39A)),
  iris('Iris', Color(0xFF6A4BC7), Color(0xFFB49BFF)),
  rose('Rose', Color(0xFFC2185B), Color(0xFFFF8FB1)),
  slate('Slate', Color(0xFF4A5568), Color(0xFF9AA7BD));

  const AppPalette(this.label, this.lightSeed, this.darkSeed);

  final String label;
  final Color lightSeed;
  final Color darkSeed;

  Color seedFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkSeed : lightSeed;

  /// The stored palette, or [AppPalette.parchment] when there is none — the same
  /// fallback a cold install gets, so an unreadable value cannot land the app
  /// on a colour the user never chose.
  static AppPalette fromName(String? name) => values.firstWhere(
    (v) => v.name == name,
    orElse: () => AppPalette.parchment,
  );
}

/// How the focus timer draws the time that is left.
///
/// A display preference, not a theme: it changes one widget on one screen, and
/// it is stored by name for the same reason the palette is — the value has to
/// survive reordering of this enum. `retro` is the fallback for a stored
/// value this build cannot read, including a face that has since been retired.
enum ClockFace {
  retro(
    'Retro',
    'A studio dial with a live countdown',
    Icons.timelapse_rounded,
  ),
  flip('Flip', 'Split-flap cards', Icons.view_agenda_rounded),
  segments('Segments', 'Seven-segment display', Icons.bar_chart_rounded),
  minimal('Minimal', 'Thin figures and a rule', Icons.remove_rounded),
  analog('Analog', 'Hour, minute and second hands', Icons.access_time_rounded),
  neon('Neon', 'Lit figures with a glow', Icons.lightbulb_outline_rounded),
  serif(
    'Serif',
    'Typeset figures in the dial serif',
    Icons.text_fields_rounded,
  );

  const ClockFace(this.label, this.blurb, this.icon);

  final String label;
  final String blurb;
  final IconData icon;

  static ClockFace fromName(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => ClockFace.retro);
}

/// Everything the appearance section can change, in one value.
///
/// The three settings travel together — the root widget needs all of them to
/// build a theme, and the appearance card edits all of them — so they are one
/// notifier rather than three that would each have to be read at the root.
class ThemeSettings {
  const ThemeSettings({
    this.mode = ThemePreference.system,
    this.palette = AppPalette.parchment,
    this.amoled = defaultAmoled,
  });

  /// Charcoal glass ships by default. True black remains opt-in.
  static const defaultAmoled = false;

  final ThemePreference mode;
  final AppPalette palette;

  /// True black in dark mode. No effect while the app is light: it is a
  /// property of the dark scheme, not a third theme.
  final bool amoled;

  ThemeSettings copyWith({
    ThemePreference? mode,
    AppPalette? palette,
    bool? amoled,
  }) => ThemeSettings(
    mode: mode ?? this.mode,
    palette: palette ?? this.palette,
    amoled: amoled ?? this.amoled,
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
  );

  const Persona(
    this.label,
    this.icon,
    this.blurb,
    this.subjectPrompt,
    this.color,
  );

  final String label;
  final IconData icon;
  final String blurb;
  final String subjectPrompt;
  final Color color;

  static Persona fromName(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => Persona.student);
}

/// A starting preference; it never enables blocking or changes a running timer.
enum FocusIntention {
  consistency(
    'Build a habit',
    'Start with manageable blocks and a daily goal you can repeat.',
    Icons.eco_outlined,
    25,
    'Try one focused block first. Every completed session counts toward your goal.',
  ),
  distractions(
    'Fewer distractions',
    'Keep useful apps close and give distracting feeds a pause.',
    Icons.notifications_off_outlined,
    25,
    'Choose apps or Shorts to block in Shield. Accessibility is requested only when you enable blocking.',
  ),
  deepWork(
    'Go deeper',
    'Make room for longer stretches of study or uninterrupted work.',
    Icons.psychology_outlined,
    50,
    'Give one subject your full attention, then take the break in your plan.',
  );

  const FocusIntention(
    this.label,
    this.description,
    this.icon,
    this.blockMinutes,
    this.tip,
  );
  final String label;
  final String description;
  final IconData icon;
  final int blockMinutes;
  final String tip;

  static FocusIntention fromName(Object? name) => values.firstWhere(
    (value) => value.name == name,
    orElse: () => FocusIntention.consistency,
  );
}

/// The signed-in (or local-only) account.
@immutable
class UserProfile {
  const UserProfile({
    this.uid = '',
    this.displayName = '',
    this.persona = Persona.student,
    this.focusIntention = FocusIntention.consistency,
    this.timezone = 'UTC',
    this.onboardingComplete = false,
    this.isAnonymous = true,
    this.avatarIcon,
    this.avatarColor,
    this.avatarPhoto,
    this.dailyGoalMinutes = 180,
    this.createdAt,
  });

  final String uid;
  final String displayName;
  final Persona persona;
  final FocusIntention focusIntention;
  final String timezone;
  final bool onboardingComplete;

  /// True while the user has not linked a real account. Anonymous users get
  /// everything except study groups and the leaderboard.
  final bool isAnonymous;

  /// The glyph on the avatar, as an `AppIcons` name, or null for initials.
  ///
  final String? avatarIcon;
  final String? avatarPhoto;

  /// The avatar's colour as ARGB, or null to follow the theme's primary
  /// container. Stored as an int rather than a palette name so a colour the
  /// user picked once does not move when they change palette.
  final int? avatarColor;

  final int dailyGoalMinutes;
  final DateTime? createdAt;

  /// The name to greet the user by, or `''` when they never set one.
  ///
  /// Empty rather than a stand-in like "there": the caller decides whether to
  /// drop the name or substitute something, and only it knows the sentence.
  String get firstName {
    final n = displayName.trim();
    if (n.isEmpty) return '';
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
    FocusIntention? focusIntention,
    String? timezone,
    bool? onboardingComplete,
    bool? isAnonymous,
    String? avatarIcon,
    int? avatarColor,
    String? avatarPhoto,
    bool clearPhoto = false,
    int? dailyGoalMinutes,
    bool clearAvatar = false,
    DateTime? createdAt,
  }) => UserProfile(
    uid: uid ?? this.uid,
    displayName: displayName ?? this.displayName,
    persona: persona ?? this.persona,
    focusIntention: focusIntention ?? this.focusIntention,
    timezone: timezone ?? this.timezone,
    onboardingComplete: onboardingComplete ?? this.onboardingComplete,
    isAnonymous: isAnonymous ?? this.isAnonymous,
    // A null icon means "use my initials", which is a real choice rather
    // than a missing value — so clearing it has to be asked for
    // explicitly, or `copyWith` could never take the glyph away.
    avatarIcon: clearAvatar ? null : (avatarIcon ?? this.avatarIcon),
    avatarColor: avatarColor ?? this.avatarColor,
    avatarPhoto: clearPhoto ? null : avatarPhoto ?? this.avatarPhoto,
    dailyGoalMinutes: dailyGoalMinutes ?? this.dailyGoalMinutes,
    createdAt: createdAt ?? this.createdAt,
  );

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'displayName': displayName,
    'persona': persona.name,
    'focusIntention': focusIntention.name,
    'timezone': timezone,
    'onboardingComplete': onboardingComplete,
    'isAnonymous': isAnonymous,
    'avatarIcon': avatarIcon,
    'avatarColor': avatarColor,
    if (avatarPhoto != null) 'avatarPhoto': avatarPhoto,
    'dailyGoalMinutes': dailyGoalMinutes,
    'createdAt': createdAt?.millisecondsSinceEpoch,
  };

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    uid: j['uid'] as String? ?? '',
    displayName: j['displayName'] as String? ?? '',
    persona: Persona.fromName(j['persona'] as String?),
    focusIntention: FocusIntention.fromName(j['focusIntention']),
    timezone: j['timezone'] as String? ?? 'UTC',
    onboardingComplete: j['onboardingComplete'] as bool? ?? false,
    isAnonymous: j['isAnonymous'] as bool? ?? true,
    // Guarded rather than cast: this runs inside bootstrap, where one
    // malformed entry must not abort the launch.
    avatarIcon: j['avatarIcon'] is String ? j['avatarIcon'] as String : null,
    avatarColor: j['avatarColor'] is int ? j['avatarColor'] as int : null,
    avatarPhoto: ProfilePhoto.valid(j['avatarPhoto']),
    dailyGoalMinutes: j['dailyGoalMinutes'] as int? ?? 180,
    createdAt: j['createdAt'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(j['createdAt'] as int),
  );
}

/// Totals and level — everything the Profile hero card needs.
///
/// There is no streak field here on purpose. A streak is a fact about dates,
/// and this aggregate carries none; it is derived from the session log by
/// `currentStreakProvider` instead. The fields that used to sit here had no
/// writer in the session path, so they read as a permanent zero.
@immutable
class GamificationStats {
  const GamificationStats({
    this.xp = 0,
    this.level = 1,
    this.totalFocusHours = 0,
    this.totalSessions = 0,
    this.badges = const <String>[],
    this.creditedSessionIds = const <String>[],
  });

  final int xp;
  final int level;
  final double totalFocusHours;
  final int totalSessions;
  final List<String> badges;
  final List<String> creditedSessionIds;

  static const maxLevel = 50;

  bool get isMaxLevel => level >= maxLevel;

  /// One XP is one focused minute: quick starts, then a growing commitment.
  int get xpForNext {
    if (level <= 5) return 25 + (level - 1) * 15;
    if (level <= 10) return 120 + (level - 6) * 30;
    final step = level - 11;
    return 300 + step * 50 + step * (step + 1) * 5;
  }

  double get levelProgress => isMaxLevel ? 1 : (xp / xpForNext).clamp(0.0, 1.0);

  GamificationStats copyWith({
    int? xp,
    int? level,
    double? totalFocusHours,
    int? totalSessions,
    List<String>? badges,
    List<String>? creditedSessionIds,
  }) => GamificationStats(
    xp: xp ?? this.xp,
    level: level ?? this.level,
    totalFocusHours: totalFocusHours ?? this.totalFocusHours,
    totalSessions: totalSessions ?? this.totalSessions,
    badges: badges ?? this.badges,
    creditedSessionIds: creditedSessionIds ?? this.creditedSessionIds,
  );

  /// Adds XP and rolls the level over as many times as the total allows.
  GamificationStats withXp(int delta) {
    var next = copyWith(
      xp: xp + delta < 0 ? 0 : xp + delta,
      level: level.clamp(1, maxLevel),
    );
    while (!next.isMaxLevel && next.xp >= next.xpForNext) {
      next = next.copyWith(xp: next.xp - next.xpForNext, level: next.level + 1);
    }
    return next;
  }

  Map<String, dynamic> toJson() => {
    'xp': xp,
    'level': level,
    'totalFocusHours': totalFocusHours,
    'totalSessions': totalSessions,
    'badges': badges,
    'creditedSessionIds': creditedSessionIds,
  };

  factory GamificationStats.fromJson(Map<String, dynamic> j) =>
      GamificationStats(
        xp: j['xp'] as int? ?? 0,
        level: j['level'] as int? ?? 1,
        totalFocusHours: (j['totalFocusHours'] as num?)?.toDouble() ?? 0,
        totalSessions: j['totalSessions'] as int? ?? 0,
        badges: (j['badges'] as List?)?.cast<String>() ?? const [],
        creditedSessionIds:
            (j['creditedSessionIds'] as List?)?.whereType<String>().toList(
              growable: false,
            ) ??
            const [],
      ).withXp(0);
}
