import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'leaderboard_service.dart';

/// Only earned badge IDs and their dates leave the device. No session log.
const achievementIds = <String>{
  'first_focus',
  'five_sessions',
  'three_day_streak',
  'five_hours',
  'ten_hours',
  'week_warrior',
  'century_club',
  'night_owl',
  'early_bird',
  'deep_diver',
  'steady_hand',
  'month_king',
  'hundred_hours',
  'marathon',
  'perfectionist',
  'subject_master',
  'night_shift',
  'breath_master',
};

Map<String, int> readAchievementTimes(Object? raw) {
  if (raw is! Map) return {};
  return {
    for (final entry in raw.entries)
      if (achievementIds.contains(entry.key) &&
          entry.value is int &&
          entry.value >= 0 &&
          entry.value <= 253402300799999)
        entry.key as String: entry.value as int,
  };
}

/// Union preserves earned badges; prefer the earliest known date.
Map<String, int> mergeAchievementTimes(
  Map<String, int> local,
  Map<String, int> remote,
) {
  final merged = readAchievementTimes(local);
  for (final entry in readAchievementTimes(remote).entries) {
    final old = merged[entry.key];
    if (old == null || old == 0 || (entry.value > 0 && entry.value < old)) {
      merged[entry.key] = entry.value;
    }
  }
  return merged;
}

abstract class AchievementService {
  bool get available;
  Stream<Map<String, int>> watch(String uid);
  Future<void> save(String uid, Map<String, int> unlockedAt);
}

class FirebaseAchievementService implements AchievementService {
  @override
  bool get available => FirebaseLeaderboardService.isSupported;

  void _requireOwner(String uid) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous || user.uid != uid) {
      throw StateError('An authenticated owner is required.');
    }
  }

  DocumentReference<Map<String, dynamic>> _record(String uid) =>
      FirebaseFirestore.instance.doc('users/$uid/achievements/earned');

  @override
  Stream<Map<String, int>> watch(String uid) {
    _requireOwner(uid);
    return _record(uid).snapshots().map(
      (snapshot) => readAchievementTimes(snapshot.data()?['unlockedAt']),
    );
  }

  @override
  Future<void> save(String uid, Map<String, int> unlockedAt) async {
    _requireOwner(uid);
    // A transaction unions badges from other devices instead of replacing
    // their whole cabinet with this device's older snapshot.
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      _requireOwner(uid);
      final record = _record(uid);
      final snapshot = await transaction.get(record);
      _requireOwner(uid);
      final merged = mergeAchievementTimes(
        unlockedAt,
        readAchievementTimes(snapshot.data()?['unlockedAt']),
      );
      transaction.set(record, {'version': 1, 'unlockedAt': merged});
    });
  }
}

class UnavailableAchievementService implements AchievementService {
  const UnavailableAchievementService();
  @override
  bool get available => false;
  @override
  Stream<Map<String, int>> watch(String uid) => Stream.value(const {});
  @override
  Future<void> save(String uid, Map<String, int> unlockedAt) async {}
}
