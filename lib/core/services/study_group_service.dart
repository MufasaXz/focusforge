import 'dart:math';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/social.dart';
import '../models/icon_registry.dart';

abstract class StudyGroupService {
  bool get available;
  Stream<List<StudyGroup>> watchGroups(String uid);
  Stream<List<GroupMember>> watchMembers(String groupId);
  Future<void> create(String name, int targetHours, String displayName);
  Future<void> join(String code, String displayName);
  Future<void> leave(StudyGroup group);
  Future<void> publish(
    String groupId,
    String week,
    int minutes,
    String displayName,
    DateTime? focusUntil,
  );
}

class GroupException implements Exception {
  const GroupException(this.message);
  final String message;
  @override
  String toString() => message;
}

class FirebaseStudyGroupService implements StudyGroupService {
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  String get _uid {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw const GroupException('Sign in to use study groups.');
    }
    return user.uid;
  }

  @override
  bool get available => true;
  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action().timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const GroupException(
        'Sync is taking longer than expected. Check your connection; pending changes may still complete.',
      );
    } on FirebaseException catch (error) {
      throw GroupException(switch (error.code) {
        'unavailable' => 'No connection. Try again when you are online.',
        'permission-denied' => 'The group could not be changed. Check the invite, member limit and Firebase rules.',
        _ => 'Could not sync the group. Please try again.',
      });
    }
  }

  @override
  Stream<List<StudyGroup>> watchGroups(String uid) => _db
      .collection('studyGroups')
      .where('memberIds', arrayContains: uid)
      .snapshots()
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs)
            StudyGroup(
              id: doc.id,
              name: doc.data()['name'] as String,
              icon: AppIcons.resolve('groups'),
              targetHours: (doc.data()['targetHours'] as num).toDouble(),
              createdAt: DateTime.fromMillisecondsSinceEpoch(
                doc.data()['createdAt'] as int,
              ),
              inviteCode: doc.data()['inviteCode'] as String,
              ownerUid: doc.data()['ownerUid'] as String,
              memberIds: List<String>.from(doc.data()['memberIds'] as List),
            ),
        ],
      );
  Future<List<StudyGroup>> groupsForDeletion(String uid) async {
    final snapshot = await _db
        .collection('studyGroups')
        .where('memberIds', arrayContains: uid)
        .get(const GetOptions(source: Source.server));
    return [
      for (final doc in snapshot.docs)
        StudyGroup(
          id: doc.id,
          name: doc.data()['name'] as String,
          icon: AppIcons.resolve('groups'),
          targetHours: (doc.data()['targetHours'] as num).toDouble(),
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            doc.data()['createdAt'] as int,
          ),
          inviteCode: doc.data()['inviteCode'] as String,
          ownerUid: doc.data()['ownerUid'] as String,
          memberIds: List<String>.from(doc.data()['memberIds'] as List),
        ),
    ];
  }

  @override
  Stream<List<GroupMember>> watchMembers(String groupId) => _db
      .collection('studyGroups/$groupId/members')
      .snapshots()
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs)
            GroupMember.fromJson(doc.id, doc.data()),
        ],
      );
  Map<String, dynamic> _member(String name) => {
    'name': name.trim().isEmpty
        ? 'A student'
        : name.trim().substring(0, min(name.trim().length, 60)),
    'joinedAt': DateTime.now().millisecondsSinceEpoch,
    'week': '',
    'minutes': 0,
    'focusUntil': 0,
    'updatedAt': FieldValue.serverTimestamp(),
  };
  @override
  Future<void> create(String name, int targetHours, String displayName) =>
      _guard(() async {
        final uid = _uid;
        final group = _db.collection('studyGroups').doc();
        const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        final random = Random.secure();
        final code = List.generate(
          10,
          (_) => alphabet[random.nextInt(alphabet.length)],
        ).join();
        final batch = _db.batch();
        batch.set(group, {
          'name': name.trim(),
          'targetHours': targetHours,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'ownerUid': uid,
          'memberIds': [uid],
          'inviteCode': code,
        });
        batch.set(_db.doc('groupInvites/$code'), {'groupId': group.id});
        batch.set(group.collection('members').doc(uid), {
          ..._member(displayName),
          'inviteCode': code,
        });
        await batch.commit();
      });
  @override
  Future<void> join(String code, String displayName) => _guard(() async {
    final uid = _uid;
    final clean = code.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (!RegExp(r'^[A-Z2-9]{10}$').hasMatch(clean)) {
      throw const GroupException(
        'Use the ten-character code your friend shared.',
      );
    }
    final invite = await _db
        .doc('groupInvites/$clean')
        .get(const GetOptions(source: Source.server));
    final groupId = invite.data()?['groupId'];
    if (groupId is! String) {
      throw const GroupException('That invite no longer exists.');
    }
    final batch = _db.batch();
    batch.update(_db.doc('studyGroups/$groupId'), {
      'memberIds': FieldValue.arrayUnion([uid]),
    });
    batch.set(_db.doc('studyGroups/$groupId/members/$uid'), {
      ..._member(displayName),
      'inviteCode': clean,
    });
    await batch.commit();
  });
  @override
  Future<void> leave(StudyGroup group) => _guard(() async {
    final uid = _uid;
    final doc = _db.doc('studyGroups/${group.id}');
    await _db.runTransaction((tx) async {
      final snapshot = await tx.get(doc);
      final data = snapshot.data();
      if (data == null) return;
      final ids = List<String>.from(data['memberIds'] as List)..remove(uid);
      if (ids.isEmpty) {
        tx.delete(doc);
        tx.delete(_db.doc('groupInvites/${data['inviteCode']}'));
      } else {
        tx.update(doc, {
          'memberIds': ids,
          if (data['ownerUid'] == uid) 'ownerUid': ids.first,
        });
      }
      tx.delete(doc.collection('members').doc(uid));
    });
  });
  @override
  Future<void> publish(
    String groupId,
    String week,
    int minutes,
    String displayName,
    DateTime? focusUntil,
  ) => _guard(() async {
    final row = _member(displayName)..remove('joinedAt');
    row.addAll({
      'week': week,
      'minutes': minutes,
      'focusUntil': focusUntil?.millisecondsSinceEpoch ?? 0,
    });
    await _db.doc('studyGroups/$groupId/members/$_uid').update(row);
  });
}

class UnavailableStudyGroupService implements StudyGroupService {
  const UnavailableStudyGroupService();
  @override
  bool get available => false;
  @override
  Stream<List<StudyGroup>> watchGroups(String uid) => Stream.value([]);
  @override
  Stream<List<GroupMember>> watchMembers(String groupId) => Stream.value([]);
  Never _fail() => throw const GroupException(
    'Study groups need a connected Firebase build.',
  );
  @override
  Future<void> create(String name, int targetHours, String displayName) async =>
      _fail();
  @override
  Future<void> join(String code, String displayName) async => _fail();
  @override
  Future<void> leave(StudyGroup group) async => _fail();
  @override
  Future<void> publish(
    String groupId,
    String week,
    int minutes,
    String displayName,
    DateTime? focusUntil,
  ) async => _fail();
}
