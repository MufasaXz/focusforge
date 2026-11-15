import 'package:flutter/material.dart';

/// Offline cosmetic rewards. These do not unlock permissions or paid features.
/// Stable IDs reuse the existing avatar field and leaderboard wire format.
enum StudyAvatar {
  scout('Scout', 1, 0, Color(0xFFFFB65C), Color(0xFF302A52)),
  ember('Ember Fox', 5, 1, Color(0xFFFF9C59), Color(0xFF3B2451)),
  orbit('Orbit', 10, 2, Color(0xFFB3CBFF), Color(0xFF152C50)),
  sage('Sage Owl', 15, 3, Color(0xFF9CE0C4), Color(0xFF183F40)),
  nova('Nova Cat', 20, 4, Color(0xFFD4B6FF), Color(0xFF302155)),
  ripple('Ripple', 25, 5, Color(0xFFFFADD2), Color(0xFF273F64)),
  frost('Frost Wolf', 30, 1, Color(0xFFC6F1FF), Color(0xFF203F63)),
  moss('Moss Dragon', 35, 6, Color(0xFFB7EA91), Color(0xFF203D32)),
  eclipse('Eclipse', 40, 4, Color(0xFF7F9CE2), Color(0xFF171D36)),
  sol('Sol Phoenix', 45, 3, Color(0xFFFFD16B), Color(0xFF602D40)),
  zenith('Zenith', 50, 2, Color(0xFFEAE2FF), Color(0xFF37336B));

  const StudyAvatar(
    this.label,
    this.unlockLevel,
    this.kind,
    this.color,
    this.background,
  );
  final String label;
  final int unlockLevel;
  final int kind;
  final Color color;
  final Color background;
  String get id => 'portrait_$name';
  bool unlockedAt(int level) => level >= unlockLevel;
  static StudyAvatar? fromId(String? id) =>
      values.where((a) => a.id == id).firstOrNull;
  static StudyAvatar forProfile(String? id, int level) {
    final avatar = fromId(id);
    return avatar != null && avatar.unlockedAt(level) ? avatar : scout;
  }
}
