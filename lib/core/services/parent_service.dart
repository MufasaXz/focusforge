import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:firebase_core/firebase_core.dart';

import '../models/parent.dart';

/// Pairing and sync between a parent's device and a child's.
///
/// The same shape as [AuthService] on purpose: the screens talk to this, not
/// to Firestore, so a build with no backend — the web preview, a phone with no
/// network — degrades to "parent control is not available here" rather than
/// throwing out of a page. Only the summary travels: the session log, the
/// subjects and the shield rules of the child stay on the child's device.
abstract class ParentService {
  /// Whether this build has a backend to pair over.
  bool get available;

  /// The signed-in account, or null when there is none.
  String? get uid;

  /// Mints a code the parent types in, valid for [PairCode.lifetime].
  Future<PairCode> mintPairCode({required String childName});

  /// Claims [code] on behalf of the signed-in parent.
  ///
  /// Throws [PairFailure] with something the screen can say when the code is
  /// wrong, spent or expired.
  Future<ChildLink> linkChild(String code, {required String parentName});

  /// The children on this parent's list.
  Stream<List<ChildLink>> watchChildren(String parentUid);

  /// The parent this device is linked to, if any.
  Stream<GuardianLink?> watchGuardian(String uid);

  /// Breaks the link. Called by the child's device, behind its security code.
  Future<void> unlink(String uid);

  /// Publishes the child's summary for the parent to read.
  Future<void> publishProgress(String uid, ChildProgress progress);

  /// The child's summary, as the parent sees it.
  Stream<ChildProgress?> watchProgress(String childUid);

  /// Publishes the block list a parent set for a child.
  Future<void> publishBlocks(String childUid, RemoteBlocks blocks);

  /// The block list a parent set for this device, if any.
  Stream<RemoteBlocks?> watchBlocks(String childUid);

  void dispose();
}

/// Why a pairing attempt failed, in a form the screen can say out loud.
enum PairFailure {
  badCode,
  expired,
  alreadyLinked,
  noBackend,
  offline,
  unknown,
}

class PairException implements Exception {
  const PairException(this.failure, [this.message]);

  final PairFailure failure;
  final String? message;

  String get friendly => switch (failure) {
    PairFailure.badCode => 'That code does not match any waiting child.',
    PairFailure.expired =>
      'That code has expired. Ask for a fresh one from the child\'s app.',
    PairFailure.alreadyLinked =>
      'That device is already linked to a parent account.',
    PairFailure.noBackend => 'This build has no backend to pair over.',
    PairFailure.offline => 'No connection. Pairing needs one.',
    PairFailure.unknown => 'Something went wrong while pairing.',
  };

  @override
  String toString() => 'PairException($failure): $message';
}

/// The Firestore implementation.
class FirebaseParentService implements ParentService {
  FirebaseParentService();

  /// True when Firebase has an app to talk to.
  ///
  /// Checked rather than assumed: `bootstrap()` falls back to the on-device
  /// account backend when `Firebase.initializeApp()` fails, and a build with
  /// no project must not reach for Firestore at all.
  static bool get isSupported {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  final _random = Random.secure();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  @override
  bool get available => true;

  @override
  String? get uid => firebase.FirebaseAuth.instance.currentUser?.uid;

  String _requireUid() {
    final id = uid;
    if (id == null) throw const PairException(PairFailure.noBackend);
    return id;
  }

  /// Firestore's own failures, mapped to something a screen can say. A
  /// permission denial is the interesting one: it means the rules refused,
  /// which is a bug or an expired link rather than a network problem.
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw PairException(PairFailure.alreadyLinked, error.message);
      }
      if (error.code == 'unavailable') {
        throw PairException(PairFailure.offline, error.message);
      }
      throw PairException(PairFailure.unknown, error.message);
    }
  }

  @override
  Future<PairCode> mintPairCode({required String childName}) async {
    final me = _requireUid();
    // Six digits, leading zeros kept: the code is a string everywhere, so
    // 000123 is a code rather than the number 123.
    final code = List.generate(6, (_) => _random.nextInt(10)).join();
    final expires = DateTime.now().add(PairCode.lifetime);
    await _guard(
      () => _db.collection('pairCodes').doc(code).set({
        'childUid': me,
        'childName': childName,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'expiresAt': expires.millisecondsSinceEpoch,
      }),
    );
    return PairCode(code: code, expiresAt: expires);
  }

  @override
  Future<ChildLink> linkChild(String code, {required String parentName}) async {
    final me = _requireUid();
    final doc = await _guard(() => _db.collection('pairCodes').doc(code).get());
    final data = doc.data();
    if (!doc.exists || data == null) {
      throw const PairException(PairFailure.badCode);
    }
    final childUid = data['childUid'];
    if (childUid is! String || childUid.isEmpty) {
      throw const PairException(PairFailure.badCode);
    }
    final expires = data['expiresAt'];
    if (expires is num &&
        DateTime.now().isAfter(
          DateTime.fromMillisecondsSinceEpoch(expires.toInt()),
        )) {
      throw const PairException(PairFailure.expired);
    }

    final name = data['childName'] is String
        ? data['childName'] as String
        : 'Your child';

    // The child's own record names the parent; the parent's list names the
    // child. Both are written before the code is retired, so a half-finished
    // link is a retry rather than a lost pairing.
    await _guard(
      () => _db
          .collection('users')
          .doc(childUid)
          .collection('guardian')
          .doc('link')
          .set({
            'parentUid': me,
            'parentName': parentName,
            'linkedAt': DateTime.now().millisecondsSinceEpoch,
          }),
    );
    await _guard(
      () => _db
          .collection('users')
          .doc(me)
          .collection('children')
          .doc(childUid)
          .set({
            'name': name,
            'linkedAt': DateTime.now().millisecondsSinceEpoch,
            'focusOnly': false,
          }),
    );
    // A code is good once. Leaving it live would let a second parent claim the
    // same device for the rest of the window.
    unawaited(_guard(() => _db.collection('pairCodes').doc(code).delete()));

    return ChildLink(uid: childUid, name: name, linkedAt: DateTime.now());
  }

  @override
  Stream<List<ChildLink>> watchChildren(String parentUid) => _db
      .collection('users')
      .doc(parentUid)
      .collection('children')
      .snapshots()
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs)
            ?ChildLink.fromJson(doc.id, doc.data()),
        ],
      );

  @override
  Stream<GuardianLink?> watchGuardian(String uid) => _db
      .collection('users')
      .doc(uid)
      .collection('guardian')
      .doc('link')
      .snapshots()
      .map((doc) => doc.exists ? GuardianLink.fromJson(doc.data()) : null);

  @override
  Future<void> unlink(String uid) => _guard(
    () => _db
        .collection('users')
        .doc(uid)
        .collection('guardian')
        .doc('link')
        .delete(),
  );

  @override
  Future<void> publishProgress(String uid, ChildProgress progress) => _guard(
    () => _db
        .collection('users')
        .doc(uid)
        .collection('progress')
        .doc('current')
        .set(progress.toJson()),
  );

  @override
  Stream<ChildProgress?> watchProgress(String childUid) => _db
      .collection('users')
      .doc(childUid)
      .collection('progress')
      .doc('current')
      .snapshots()
      .map((doc) => doc.exists ? ChildProgress.fromJson(doc.data()) : null);

  @override
  Future<void> publishBlocks(String childUid, RemoteBlocks blocks) => _guard(
    () => _db
        .collection('users')
        .doc(childUid)
        .collection('remoteRules')
        .doc('current')
        .set(blocks.toJson()),
  );

  @override
  Stream<RemoteBlocks?> watchBlocks(String childUid) => _db
      .collection('users')
      .doc(childUid)
      .collection('remoteRules')
      .doc('current')
      .snapshots()
      .map((doc) => doc.exists ? RemoteBlocks.fromJson(doc.data()) : null);

  @override
  void dispose() {}
}

/// The stand-in everywhere there is no backend: the web preview, tests, and a
/// phone where Firebase could not start. Every method refuses rather than
/// pretending, so a screen can say what is missing.
class UnavailableParentService implements ParentService {
  const UnavailableParentService();

  @override
  bool get available => false;

  @override
  String? get uid => null;

  Never _refuse() => throw const PairException(PairFailure.noBackend);

  @override
  Future<PairCode> mintPairCode({required String childName}) async => _refuse();

  @override
  Future<ChildLink> linkChild(
    String code, {
    required String parentName,
  }) async => _refuse();

  @override
  Stream<List<ChildLink>> watchChildren(String parentUid) =>
      Stream.value(const []);

  @override
  Stream<GuardianLink?> watchGuardian(String uid) => Stream.value(null);

  @override
  Future<void> unlink(String uid) async => _refuse();

  @override
  Future<void> publishProgress(String uid, ChildProgress progress) async {}

  @override
  Stream<ChildProgress?> watchProgress(String childUid) => Stream.value(null);

  @override
  Future<void> publishBlocks(String childUid, RemoteBlocks blocks) async =>
      _refuse();

  @override
  Stream<RemoteBlocks?> watchBlocks(String childUid) => Stream.value(null);

  @override
  void dispose() {}
}
