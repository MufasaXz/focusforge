import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// One row of a week's board, as it is stored.
///
/// Deliberately three fields. A board that carried subjects, session counts or
/// streaks would be publishing more about a person than the question it
/// answers — "who studied most this week" — needs.
@immutable
class BoardRow {
  const BoardRow({required this.uid, required this.name, required this.minutes});

  final String uid;
  final String name;
  final int minutes;

  Map<String, dynamic> toJson() => {'name': name, 'minutes': minutes};

  static BoardRow? fromJson(String uid, Object? raw) {
    if (raw is! Map) return null;
    final minutes = raw['minutes'];
    if (minutes is! num) return null;
    final name = raw['name'];
    return BoardRow(
      uid: uid,
      name: name is String && name.trim().isNotEmpty
          ? name.trim()
          : 'A student',
      minutes: minutes.toInt(),
    );
  }
}

/// The key a week's board is filed under: that week's Monday, `yyyy-mm-dd`.
///
/// A Monday rather than an ISO week number: it is the same window the rest of
/// the app measures a week over, and it sorts and reads as a date rather than
/// as a code.
String weekKey(DateTime when) {
  final monday = DateTime(when.year, when.month, when.day - (when.weekday - 1));
  return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-'
      '${monday.day.toString().padLeft(2, '0')}';
}

/// The weekly board, over whatever backend this build has.
abstract class LeaderboardService {
  /// Whether there is a backend to read or write the board.
  bool get available;

  /// The signed-in account, or null when there is none.
  String? get uid;

  /// Publishes this device's week under [week].
  Future<void> publish({
    required String week,
    required String uid,
    required String name,
    required int minutes,
  });

  /// This week's rows, best first.
  Stream<List<BoardRow>> watch(String week, {int limit = 100});

  /// Removes this device's row, so leaving the board is immediate.
  Future<void> withdraw(String week, String uid);

  void dispose();
}

/// The Firestore implementation.
///
/// One document per person per week under `leaderboard/{week}/entries/{uid}`,
/// which is what makes the read a plain ordered query with no composite index
/// to create and no scan of every week that has ever been played.
class FirebaseLeaderboardService implements LeaderboardService {
  FirebaseLeaderboardService();

  /// True when Firebase has an app to talk to — the same check the parent
  /// layer makes, and for the same reason.
  static bool get isSupported {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _entries(String week) => _db
      .collection('leaderboard')
      .doc(week)
      .collection('entries');

  @override
  bool get available => true;

  @override
  String? get uid => firebase.FirebaseAuth.instance.currentUser?.uid;

  @override
  Future<void> publish({
    required String week,
    required String uid,
    required String name,
    required int minutes,
  }) async {
    await _entries(week).doc(uid).set({
      'name': name,
      'minutes': minutes,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  Stream<List<BoardRow>> watch(String week, {int limit = 100}) => _entries(week)
      .orderBy('minutes', descending: true)
      .limit(limit)
      .snapshots()
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs) ?BoardRow.fromJson(doc.id, doc.data()),
        ],
      );

  @override
  Future<void> withdraw(String week, String uid) =>
      _entries(week).doc(uid).delete();

  @override
  void dispose() {}
}

/// The stand-in where there is no backend: the web preview, tests, and a phone
/// where Firebase could not start. It reads as an empty board rather than
/// pretending, so the screen can say why it is empty.
class UnavailableLeaderboardService implements LeaderboardService {
  const UnavailableLeaderboardService();

  @override
  bool get available => false;

  @override
  String? get uid => null;

  @override
  Future<void> publish({
    required String week,
    required String uid,
    required String name,
    required int minutes,
  }) async {}

  @override
  Stream<List<BoardRow>> watch(String week, {int limit = 100}) =>
      Stream.value(const []);

  @override
  Future<void> withdraw(String week, String uid) async {}

  @override
  void dispose() {}
}
