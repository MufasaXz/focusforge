import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusforge/core/services/firestore_account_cleanup.dart';

void main() {
  late FakeFirebaseFirestore db;
  setUp(() async {
    db = FakeFirebaseFirestore();
    await db.doc('accountCleanup/schema').set({'version': 2});
  });
  test('removes profile, private data, historical board and manifests; preserves other users', () async {
    await db.doc('users/sam').set({'name': 'Sam'});
    await db.doc('users/sam/achievements/earned').set({'first_focus': 1});
    await db.doc('users/sam/preferences/current').set({'theme': 'dark'});
    await db.doc('users/sam/archive/year/nested/session').set({'minutes': 90});
    await db.doc('users/sam/deletionRefs/old').set({
      'path': 'users/sam/archive/year/nested/session',
    });
    await db.doc('users/other/achievements/earned').set({'first_focus': 2});
    await db.doc('leaderboard/2025-01-06/entries/sam').set({
      'ownerUid': 'sam',
      'minutes': 10,
    });
    await db.doc('leaderboard/2025-01-06/entries/other').set({
      'ownerUid': 'other',
      'minutes': 20,
    });
    await FirestoreAccountCleanup(db).deleteUserData('sam');
    expect((await db.doc('users/sam').get()).exists, isFalse);
    expect(
      (await db.doc('users/sam/achievements/earned').get()).exists,
      isFalse,
    );
    expect(
      (await db.doc('users/sam/preferences/current').get()).exists,
      isFalse,
    );
    expect(
      (await db.doc('users/sam/archive/year/nested/session').get()).exists,
      isFalse,
    );
    expect((await db.collection('users/sam/deletionRefs').get()).docs, isEmpty);
    expect(
      (await db
              .collectionGroup('entries')
              .where('ownerUid', isEqualTo: 'sam')
              .get())
          .docs,
      isEmpty,
    );
    expect(
      (await db.doc('users/other/achievements/earned').get()).exists,
      isTrue,
    );
    expect(
      (await db.doc('leaderboard/2025-01-06/entries/other').get()).exists,
      isTrue,
    );
    expect((await db.doc('accountDeletions/sam').get()).exists, isTrue);
  });
  test(
    'owner departure transfers group and last member removes invite',
    () async {
      await db.doc('studyGroups/shared').set({
        'memberIds': ['sam', 'other'],
        'ownerUid': 'sam',
        'inviteCode': 'SHARED2345',
      });
      await db.doc('studyGroups/shared/members/sam').set({'ownerUid': 'sam'});
      await db.doc('studyGroups/shared/members/other').set({
        'ownerUid': 'other',
      });
      await db.doc('studyGroups/alone').set({
        'memberIds': ['sam'],
        'ownerUid': 'sam',
        'inviteCode': 'ALONE23456',
      });
      await db.doc('studyGroups/alone/members/sam').set({'ownerUid': 'sam'});
      await db.doc('groupInvites/ALONE23456').set({'groupId': 'alone'});
      await db.doc('studyGroups/orphan/members/sam').set({'ownerUid': 'sam'});
      await FirestoreAccountCleanup(db).deleteUserData('sam');
      expect(
        (await db.doc('studyGroups/shared').get()).data()?['ownerUid'],
        'other',
      );
      expect((await db.doc('studyGroups/shared').get()).data()?['memberIds'], [
        'other',
      ]);
      expect(
        (await db.doc('studyGroups/shared/members/other').get()).exists,
        isTrue,
      );
      expect(
        (await db.doc('studyGroups/shared/members/sam').get()).exists,
        isFalse,
      );
      expect((await db.doc('studyGroups/alone').get()).exists, isFalse);
      expect((await db.doc('groupInvites/ALONE23456').get()).exists, isFalse);
      expect(
        (await db.doc('studyGroups/orphan/members/sam').get()).exists,
        isFalse,
      );
    },
  );
  test(
    'pages more than a batch of sessions and retries idempotently',
    () async {
      for (var i = 0; i < 503; i++) {
        await db.doc('users/sam/sessions/$i').set({'minutes': i});
      }
      final cleanup = FirestoreAccountCleanup(db);
      await cleanup.deleteUserData('sam');
      await cleanup.deleteUserData('sam');
      expect((await db.collection('users/sam/sessions').get()).docs, isEmpty);
    },
  );
  test(
    'unmigrated database fails before creating a marker or erasing data',
    () async {
      await db.doc('accountCleanup/schema').delete();
      await db.doc('users/sam').set({'name': 'Sam'});
      await expectLater(
        FirestoreAccountCleanup(db).deleteUserData('sam'),
        throwsA(isA<StateError>()),
      );
      expect((await db.doc('users/sam').get()).exists, isTrue);
      expect((await db.doc('accountDeletions/sam').get()).exists, isFalse);
    },
  );
  test('a corrupted manifest never deletes someone else data', () async {
    await db.doc('users/other').set({'name': 'Other'});
    await db.doc('users/sam/deletionRefs/bad').set({'path': 'users/other'});
    await expectLater(
      FirestoreAccountCleanup(db).deleteUserData('sam'),
      throwsA(isA<StateError>()),
    );
    expect((await db.doc('users/other').get()).exists, isTrue);
  });
}
