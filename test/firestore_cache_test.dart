import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_platform_interface/src/pigeon/messages.pigeon.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:focusforge/core/services/firestore_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('first native cache operation receives persistence disabled', () async {
    setupFirebaseCoreMocks();
    final app = await Firebase.initializeApp(
      name: 'cache-regression',
      options: const FirebaseOptions(
        apiKey: 'test',
        appId: 'test',
        messagingSenderId: 'test',
        projectId: 'test',
      ),
    );
    bool? nativePersistence;
    const codec = FirebaseFirestoreHostApi.codec;
    final channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.clearPersistence',
      codec,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(channel, (
          Object? message,
        ) async {
          final args = message! as List<Object?>;
          nativePersistence = (args.first! as FirestorePigeonFirebaseApp)
              .settings
              .persistenceEnabled;
          return <Object?>[null];
        });
    final db = FirebaseFirestore.instanceFor(app: app);
    await prepareFirestoreCache(db);
    expect(
      nativePersistence,
      isFalse,
      reason: 'Settings must precede the first Pigeon call, otherwise disk cache remains enabled.',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(channel, null);
  });
}
