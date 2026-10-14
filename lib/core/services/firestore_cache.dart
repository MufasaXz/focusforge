import 'package:cloud_firestore/cloud_firestore.dart';

/// FlutterFire freezes native settings on its first platform call. Set memory
/// persistence first, then clear any disk data left by an older app release.
Future<void> prepareFirestoreCache(FirebaseFirestore db) async {
  db.settings = const Settings(persistenceEnabled: false);
  await db.clearPersistence().timeout(const Duration(seconds: 8));
}
