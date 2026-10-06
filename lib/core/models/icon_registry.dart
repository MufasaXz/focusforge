import 'package:flutter/material.dart';

/// Persisted models must never store an [IconData] code point.
///
/// Two reasons, and the second one bites at release time:
///
///  1. A raw code point is meaningless in a diff or in exported JSON — nobody
///     can tell what `0xe4f5` is.
///  2. `flutter build apk` runs with `--tree-shake-icons`, which statically
///     finds every *constant* `IconData` in the program and strips the rest of
///     the font. An icon rebuilt from a runtime integer is invisible to that
///     analysis, so it survives in debug and renders as a blank box — or fails
///     the build — in release.
///
/// So icons cross the storage boundary as names, and this table is the only
/// place the two representations meet. Anything not listed falls back to a
/// neutral glyph rather than throwing.
class AppIcons {
  const AppIcons._();

  static const _byName = <String, IconData>{
    // Subjects & study
    'math': Icons.square_foot_rounded,
    'physics': Icons.bolt_rounded,
    'english': Icons.menu_book_rounded,
    'history': Icons.history_edu_rounded,
    'chemistry': Icons.science_rounded,
    'biology': Icons.biotech_rounded,
    'code': Icons.code_rounded,
    'art': Icons.palette_rounded,
    'deepwork': Icons.psychology_rounded,
    'planning': Icons.insights_rounded,
    'writing': Icons.edit_note_rounded,
    'meetings': Icons.call_rounded,
    'email': Icons.mail_rounded,
    'homework': Icons.assignment_rounded,
    'reading': Icons.menu_book_rounded,
    'revision': Icons.refresh_rounded,
    'creative': Icons.palette_rounded,
    // Apps
    'instagram': Icons.photo_camera_rounded,
    'facebook': Icons.facebook_rounded,
    'youtube': Icons.smart_display_rounded,
    'tiktok': Icons.music_note_rounded,
    'twitter': Icons.close_rounded,
    'snapchat': Icons.chat_bubble_rounded,
    'reddit': Icons.forum_rounded,
    'whatsapp': Icons.chat_rounded,
    'telegram': Icons.send_rounded,
    'discord': Icons.headset_mic_rounded,
    'docs': Icons.description_rounded,
    'notion': Icons.sticky_note_2_rounded,
    'calculator': Icons.calculate_rounded,
    'slack': Icons.forum_rounded,
    'gmail': Icons.mail_rounded,
    'linkedin': Icons.work_rounded,
    'phone': Icons.call_rounded,
    'maps': Icons.map_rounded,
    'calendar': Icons.calendar_today_rounded,
    'clock': Icons.alarm_rounded,
    // Profiles
    'fire': Icons.local_fire_department_rounded,
    'beach': Icons.beach_access_rounded,
    'work': Icons.work_rounded,
    'night': Icons.bedtime_rounded,
    'star': Icons.star_rounded,
    'heart': Icons.favorite_rounded,
    'school': Icons.school_rounded,
    'groups': Icons.groups_rounded,
    'book': Icons.menu_book_rounded,
    // Shield
    'apps': Icons.apps_rounded,
    'shield': Icons.shield_rounded,
    // Ambient
    'rain': Icons.water_drop_rounded,
    'forest': Icons.forest_rounded,
    'cafe': Icons.local_cafe_rounded,
    'waves': Icons.waves_rounded,
    'noise': Icons.blur_on_rounded,
  };

  static IconData resolve(String? name) =>
      _byName[name] ?? Icons.circle_outlined;

  /// The glyphs the app offers where the user is choosing one — a subject's
  /// mark, an avatar. A curated slice of the table rather than all of it: the
  /// rest are tied to a particular app or a particular screen, and offering
  /// `tiktok` as a way to sign your name would be nonsense.
  ///
  /// Every name here is in [_byName], which is what makes it survive a
  /// round-trip through storage.
  static const curated = <String>[
    'book',
    'math',
    'physics',
    'chemistry',
    'biology',
    'english',
    'history',
    'code',
    'art',
    'writing',
    'deepwork',
    'planning',
    'school',
    'star',
    'heart',
    'work',
    'fire',
    'clock',
  ];

  /// Reverse lookup for persistence. Returns `null` for an icon that is not in
  /// the table, so callers can decide whether that is a bug or a fallback.
  static String? nameOf(IconData icon) =>
      _byName.entries.where((e) => e.value == icon).firstOrNull?.key;

  /// Like [nameOf] but never null — for seed data that must round-trip.
  static String nameOfOr(IconData icon, String fallback) =>
      nameOf(icon) ?? fallback;

  static List<String> get names => _byName.keys.toList(growable: false);
}
