import 'package:cloud_firestore/cloud_firestore.dart';

/// Spark-compatible cleanup. All reads are server reads; Auth stays available
/// until every batch has been acknowledged. The one-time schema migration
/// inventories legacy/nested data that a mobile SDK cannot enumerate.
class FirestoreAccountCleanup {
  FirestoreAccountCleanup(this.db);
  final FirebaseFirestore db;
  static const _networkWait = Duration(seconds: 30);
  static const _server = GetOptions(source: Source.server);
  // Leave room below Firestore's 500-write batch limit.
  static const _pageSize = 200;
  static const _privateCollections = [
    'achievements',
    'stats',
    'appStats',
    'preferences',
    'sessions',
    'sessionData',
    'guardian',
    'children',
    'remoteRules',
    'progress',
    'catalog',
  ];

  Future<void> deleteUserData(String uid) async {
    if (uid.isEmpty || uid.contains('/')) throw ArgumentError.value(uid, 'uid');
    final schema = await db
        .doc('accountCleanup/schema')
        .get(_server)
        .timeout(_networkWait);
    if (schema.data()?['version'] != 2) {
      throw StateError('Account cleanup schema migration is required');
    }
    final marker = db.doc('accountDeletions/$uid');
    await db
        .runTransaction((tx) async {
          final previous = await tx.get(marker);
          if (!previous.exists) {
            tx.set(marker, {'requestedAt': FieldValue.serverTimestamp()});
          }
        })
        .timeout(_networkWait);
    // The immutable marker blocks stale clients from recreating records while
    // permitting the owner to read/delete for retry, even after a restart.
    await _leaveGroups(uid);
    await _deleteQuery(
      db.collectionGroup('entries').where('ownerUid', isEqualTo: uid),
    );
    await _deleteQuery(
      db.collectionGroup('members').where('ownerUid', isEqualTo: uid),
      pageSize: 8,
    );

    // Manifest entries cover arbitrary legacy nested paths. Delete each path
    // and its manifest together so interruption cannot lose the inventory.
    final refs = db.collection('users/$uid/deletionRefs');
    while (true) {
      final page = await refs
          .limit(_pageSize)
          .get(_server)
          .timeout(_networkWait);
      if (page.docs.isEmpty) break;
      final batch = db.batch();
      for (final record in page.docs) {
        final path = record.data()['path'];
        if (path is! String ||
            !path.startsWith('users/$uid/') ||
            path.split('/').length.isOdd ||
            path.contains('//')) {
          throw StateError('Invalid private cleanup inventory');
        }
        batch.delete(db.doc(path));
        batch.delete(record.reference);
      }
      await batch.commit().timeout(_networkWait);
    }
    for (final collection in _privateCollections) {
      await _deleteQuery(db.collection('users/$uid/$collection'));
    }
    await db.doc('users/$uid').delete().timeout(_networkWait);
  }

  Future<void> _deleteQuery(
    Query<Map<String, dynamic>> query, {
    int pageSize = _pageSize,
  }) async {
    while (true) {
      final page = await query
          .limit(pageSize)
          .get(_server)
          .timeout(_networkWait);
      if (page.docs.isEmpty) return;
      final batch = db.batch();
      for (final doc in page.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit().timeout(_networkWait);
    }
  }

  Future<void> _leaveGroups(String uid) async {
    final query = db
        .collection('studyGroups')
        .where('memberIds', arrayContains: uid);
    while (true) {
      // Groups have multiple dependent rule reads: one transaction per group
      // avoids exhausting the batch-wide security-rule access-call budget.
      final groups = await query.limit(50).get(_server).timeout(_networkWait);
      if (groups.docs.isEmpty) return;
      for (final group in groups.docs) {
        await db
            .runTransaction((tx) async {
              final latest = await tx.get(group.reference);
              final data = latest.data();
              if (data == null) return;
              final ids = List<String>.from(data['memberIds'] as List)
                ..remove(uid);
              if (ids.isEmpty) {
                tx.delete(group.reference);
                tx.delete(db.doc('groupInvites/${data['inviteCode']}'));
              } else {
                tx.update(group.reference, {
                  'memberIds': ids,
                  if (data['ownerUid'] == uid) 'ownerUid': ids.first,
                });
              }
              tx.delete(group.reference.collection('members').doc(uid));
            })
            .timeout(_networkWait);
      }
    }
  }
}
