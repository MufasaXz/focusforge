// Joining a group twice with the same invite: the second join, as after a
// lost reply, must keep the membership as it is rather than rewrite it.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:focusforge/core/services/study_group_service.dart';

class _User implements User {
  @override
  String get uid => 'sam';
  @override
  bool get isAnonymous => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements FirebaseAuth {
  @override
  User? get currentUser => _User();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('joining a group you are already in keeps your membership', () async {
    final db = FakeFirebaseFirestore();
    const code = 'ABCDEFGH23';
    await db.doc('groupInvites/$code').set({'groupId': 'g1'});
    await db.doc('studyGroups/g1').set({
      'name': 'Physics',
      'targetHours': 10,
      'createdAt': 1,
      'ownerUid': 'alex',
      'memberIds': ['alex'],
      'inviteCode': code,
    });
    final groups = FirebaseStudyGroupService(db: db, auth: _Auth());

    await groups.join(code, 'Sam');
    final row = db.doc('studyGroups/g1/members/sam');
    await row.update({'week': '2026-W45', 'minutes': 120});
    final joinedAt = (await row.get()).data()!['joinedAt'];

    await groups.join(code, 'Sam');

    final after = (await row.get()).data()!;
    expect(after['joinedAt'], joinedAt);
    expect(after['minutes'], 120);
    expect((await db.doc('studyGroups/g1').get()).data()!['memberIds'], [
      'alex',
      'sam',
    ]);
  });
}
