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

  /// Breaks both sides of the link. The child confirms its security code;
  /// the linked parent may also retire a device from its dashboard.
  Future<void> unlink(String uid);

  /// Publishes the child's summary for the parent to read.
  Future<void> publishProgress(String uid, ChildProgress progress);

  /// The child's summary, as the parent sees it.
  Stream<ChildProgress?> watchProgress(String childUid);

  /// Publishes the block list a parent set for a child.
  Future<void> publishBlocks(String childUid, RemoteBlocks blocks);

  /// Sets, or with null clears, the four-digit code that guards [childUid]'s
  /// link. Written by the parent, checked by the child's device.
  Future<void> publishCode(String childUid, ParentCode? code);

  /// The block list a parent set for this device, if any.
  Stream<RemoteBlocks?> watchBlocks(String childUid);

  /// Publishes the apps installed on this device, so a parent can pick from
  /// them rather than typing a package name.
  Future<void> publishCatalog(String uid, List<CatalogApp> apps);

  /// The apps on the child's device, as the parent's picker sees them.
  Stream<List<CatalogApp>> watchCatalog(String childUid);

  void dispose();
}

/// Why a pairing attempt failed, in a form the screen can say out loud.
enum PairFailure {
  badCode,
  expired,
  alreadyLinked,

  /// The server refused the request itself — the usual cause is a project
  /// whose security rules have not been published yet, which is a fact the
  /// user can act on rather than a dead end.
  refused,

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
    PairFailure.refused =>
      'The server refused the change. If this project\'s security rules have '
          'not been published yet, that is why.',
    PairFailure.noBackend => 'This build has no backend to pair over.',
    PairFailure.offline => 'The change could not be confirmed. Check your connection; pending changes may still finish.',
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

  /// Firestore's own failures, mapped to something a screen can say.
  ///
  /// A denial means the rules refused. For a pairing attempt that is the
  /// "already linked" case, which is why it is the default; a rule change or a
  /// code is denied for a different reason — usually that the project's rules
  /// have not been published — so those callers name [PairFailure.refused].
  Future<T> _guard<T>(
    Future<T> Function() body, {
    PairFailure denied = PairFailure.alreadyLinked,
  }) async {
    try {
      return await body().timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const PairException(PairFailure.offline);
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw PairException(denied, error.message);
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
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = List.generate(6, (_) => _random.nextInt(10)).join();
      final expires = DateTime.now().add(PairCode.lifetime);
      final created = await _guard(
        () => _db.runTransaction((tx) async {
          final doc = _db.collection('pairCodes').doc(code);
          if ((await tx.get(doc)).exists) return false;
          tx.set(doc, {
            'childUid': me,
            'childName': childName.trim().substring(
              0,
              min(childName.trim().length, 60),
            ),
            'createdAt': DateTime.now().millisecondsSinceEpoch,
            'expiresAt': expires.millisecondsSinceEpoch,
          });
          return true;
        }),
        denied: PairFailure.refused,
      );
      if (created) return PairCode(code: code, expiresAt: expires);
    }
    throw const PairException(PairFailure.unknown);
  }

  @override
  Future<ChildLink> linkChild(String code, {required String parentName}) async {
    final me = _requireUid();
    final clean = code.trim();
    if (!PairCode.looksValid(clean)) {
      throw const PairException(PairFailure.badCode);
    }
    final codeDoc = _db.collection('pairCodes').doc(clean);
    final doc = await _guard(
      () => codeDoc.get(const GetOptions(source: Source.server)),
    );
    final data = doc.data();
    if (data == null || data['childUid'] is! String || data['childUid'] == me) {
      throw const PairException(PairFailure.badCode);
    }
    if (data['claimedBy'] != null) {
      throw const PairException(PairFailure.alreadyLinked);
    }
    final expires = data['expiresAt'];
    if (expires is! num || expires <= DateTime.now().millisecondsSinceEpoch) {
      throw const PairException(PairFailure.expired);
    }
    final childUid = data['childUid'] as String;
    final name = data['childName'] as String? ?? 'Your child';
    final now = DateTime.now();
    // A valid code and all three writes are checked together by the rules.
    final batch = _db.batch();
    batch.set(_db.doc('users/$childUid/guardian/link'), {
      'parentUid': me,
      'parentName': parentName.trim().substring(
        0,
        min(parentName.trim().length, 60),
      ),
      'linkedAt': now.millisecondsSinceEpoch,
      'pairCode': clean,
    });
    batch.set(_db.doc('users/$me/children/$childUid'), {
      'name': name,
      'linkedAt': now.millisecondsSinceEpoch,
    });
    batch.update(codeDoc, {'claimedBy': me});
    await _guard(batch.commit);
    return ChildLink(uid: childUid, name: name, linkedAt: now);
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
      .doc('users/$uid/guardian/link')
      .snapshots(includeMetadataChanges: true)
      .where((doc) => doc.exists || !doc.metadata.isFromCache)
      .map((doc) => doc.exists ? GuardianLink.fromJson(doc.data()) : null);

  @override
  Future<void> unlink(String uid) => _guard(() async {
    final doc = _db.doc('users/$uid/guardian/link');
    final link = await doc.get(const GetOptions(source: Source.server));
    final parentUid = link.data()?['parentUid'];
    if (parentUid is! String) return;
    final batch = _db.batch();
    batch.delete(doc);
    batch.delete(_db.doc('users/$parentUid/children/$uid'));
    batch.delete(_db.doc('users/$uid/remoteRules/current'));
    await batch.commit();
  }, denied: PairFailure.refused);

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
    denied: PairFailure.refused,
  );

  @override
  Future<void> publishCode(String childUid, ParentCode? code) => _guard(
    // The link record carries the code, because it is the record the code
    // protects: whoever can read the link can check a code against it, and the
    // child's own device is the one that has to. A merge keeps the link itself
    // — the parent's name, the date — exactly as it was.
    () => _db
        .doc('users/$childUid/guardian/link')
        .set(
          code == null
              ? {
                  'codeSalt': FieldValue.delete(),
                  'codeHash': FieldValue.delete(),
                }
              : {'codeSalt': code.salt, 'codeHash': code.hash},
          SetOptions(merge: true),
        ),
    denied: PairFailure.refused,
  );

  @override
  Stream<RemoteBlocks?> watchBlocks(String childUid) => _db
      .collection('users')
      .doc(childUid)
      .collection('remoteRules')
      .doc('current')
      .snapshots(includeMetadataChanges: true)
      .where((doc) => doc.exists || !doc.metadata.isFromCache)
      .map((doc) => doc.exists ? RemoteBlocks.fromJson(doc.data()) : null);

  @override
  Future<void> publishCatalog(String uid, List<CatalogApp> apps) => _guard(
    () => _db
        .collection('users')
        .doc(uid)
        .collection('catalog')
        .doc('current')
        .set({
          'apps': apps.map((a) => a.toJson()).toList(growable: false),
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        }),
  );

  @override
  Stream<List<CatalogApp>> watchCatalog(String childUid) => _db
      .collection('users')
      .doc(childUid)
      .collection('catalog')
      .doc('current')
      .snapshots()
      .map((doc) {
        final apps = doc.data()?['apps'];
        if (apps is! List) return const <CatalogApp>[];
        return [for (final row in apps) ?CatalogApp.fromJson(row)];
      });

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
  Future<void> publishCode(String childUid, ParentCode? code) async =>
      _refuse();

  @override
  Stream<RemoteBlocks?> watchBlocks(String childUid) => Stream.value(null);

  @override
  Future<void> publishCatalog(String uid, List<CatalogApp> apps) async {}

  @override
  Stream<List<CatalogApp>> watchCatalog(String childUid) =>
      Stream.value(const []);

  @override
  void dispose() {}
}
