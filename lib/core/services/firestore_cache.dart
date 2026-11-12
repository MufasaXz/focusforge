import 'package:cloud_firestore/cloud_firestore.dart';

/// FlutterFire freezes native settings on its first platform call. Set memory
/// persistence first, then clear any disk data left by an older app release.
///
/// Android can keep the process alive, as the blocking service does, while
/// the activity and its Flutter engine are thrown away and made again. The
/// Firestore instance the earlier engine started is then still running, and
/// refuses to clear a cache with `failed-precondition`. That is not a
/// failure: the running instance was started through this function with
/// persistence off, so it reads and writes no disk cache, and a cold start
/// clears the disk again. Treating it as one sent a signed-in account to the
/// guest-only fallback for the whole session.
///
/// Every other error still throws: the caller keeps cloud features closed.
Future<void> prepareFirestoreCache(FirebaseFirestore db) async {
  db.settings = const Settings(persistenceEnabled: false);
  try {
    await db.clearPersistence().timeout(const Duration(seconds: 8));
  } on FirebaseException catch (error) {
    if (error.code != 'failed-precondition') rethrow;
  }
}
