import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_platform_interface/src/pigeon/messages.pigeon.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:focusforge/core/services/firestore_cache.dart';

// The Firestore cache is made safe before any account code runs.
//
// WHAT INVARIANT: the first native call carries persistence off; a Firestore
// instance that is already running in this process, because Android kept the
// process and remade the Flutter engine, is accepted as it is; any other
// failure to clear still stops cloud features from opening.
//
// WHY IT MATTERS: bootstrap falls back to a guest-only account service when
// this step throws. Throwing for an instance that was merely still running
// left a signed-in account without its backup, sign-out or deletion for the
// whole session, every time the app was reopened in a live process.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const clearChannel = BasicMessageChannel<Object?>(
    'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.clearPersistence',
    FirebaseFirestoreHostApi.codec,
  );

  /// A Firestore whose native clearPersistence answers with [code], the way
  /// the Android plugin reports an error.
  Future<FirebaseFirestore> refusing(String name, String code) async {
    setupFirebaseCoreMocks();
    final app = await Firebase.initializeApp(
      name: name,
      options: const FirebaseOptions(
        apiKey: 'test',
        appId: 'test',
        messagingSenderId: 'test',
        projectId: 'test',
      ),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(
          clearChannel,
          (message) async => <Object?>[
            'firebase_firestore',
            'refused',
            <String, String>{'code': code, 'message': 'refused'},
          ],
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(clearChannel, null),
    );
    return FirebaseFirestore.instanceFor(app: app);
  }

  test(
    'an instance still running from an earlier engine is accepted',
    () async {
      // "Persistence cannot be cleared while the firestore instance is
      // running" arrives as failed-precondition.
      final db = await refusing('cache-running', 'failed-precondition');
      await expectLater(prepareFirestoreCache(db), completes);
      expect(db.settings.persistenceEnabled, isFalse);
    },
  );

  test(
    'any other failure to clear still keeps cloud features closed',
    () async {
      final db = await refusing('cache-broken', 'unavailable');
      await expectLater(
        prepareFirestoreCache(db),
        throwsA(
          isA<FirebaseException>().having((e) => e.code, 'code', 'unavailable'),
        ),
      );
    },
  );

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
