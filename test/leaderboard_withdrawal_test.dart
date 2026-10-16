import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusforge/core/services/leaderboard_service.dart';

void main() {
  test(
    'explicit opt-out removes every owned week and preserves other accounts',
    () async {
      final db = FakeFirebaseFirestore();
      for (var i = 0; i < 405; i++) {
        await db.doc('leaderboard/week-$i/entries/alice').set({
          'ownerUid': 'alice',
          'minutes': i,
        });
      }
      await db.doc('leaderboard/2026-10-12/entries/alice').set({
        'ownerUid': 'alice',
        'minutes': 60,
      });
      await db.doc('leaderboard/2026-10-05/entries/bob').set({
        'ownerUid': 'bob',
        'minutes': 120,
      });
      await db.doc('leaderboard/2026-10-05/entries/legacy').set({
        'minutes': 30,
      });
      await db.doc('otherFeature/items/entries/owned').set({
        'ownerUid': 'alice',
        'minutes': 15,
      });
      final service = FirebaseLeaderboardService(firestore: db);
      await service.withdraw('2026-10-12', 'alice');
      await service.withdraw('2026-10-12', 'alice');
      expect(
        (await db
                .collectionGroup('entries')
                .where('ownerUid', isEqualTo: 'alice')
                .get())
            .docs
            .where((doc) => doc.reference.path.startsWith('leaderboard/')),
        isEmpty,
      );
      expect(
        (await db.doc('leaderboard/2026-10-05/entries/bob').get()).exists,
        isTrue,
      );
      expect(
        (await db.doc('leaderboard/2026-10-05/entries/legacy').get()).exists,
        isTrue,
      );
      expect(
        (await db.doc('otherFeature/items/entries/owned').get()).exists,
        isTrue,
      );
    },
  );
}
