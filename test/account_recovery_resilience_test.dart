import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/bootstrap.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/services/auth_service.dart';
import 'package:focusforge/core/services/firebase_auth_service.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/study_backup_service.dart';

class _User implements User {
  _User({this.refreshFails = false});

  /// A forced token refresh fails, as it does on a weak connection.
  final bool refreshFails;
  @override
  String get uid => 'alex';
  @override
  String get displayName => 'Alex';
  @override
  String get email => 'alex@example.com';
  @override
  bool get isAnonymous => false;
  @override
  bool get emailVerified => true;
  @override
  List<UserInfo> get providerData => [];
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    if (refreshFails && forceRefresh) {
      throw FirebaseAuthException(code: 'network-request-failed');
    }
    return 'token';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements FirebaseAuth {
  _Auth(this.user);
  User? user;
  final controller = StreamController<User?>.broadcast();
  @override
  User? get currentUser => user;
  @override
  Stream<User?> authStateChanges() => controller.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Backend implements StudyBackupBackend {
  Completer<StudyBackup?>? held;
  @override
  Future<StudyBackup?> load(String uid) async => held?.future;
  @override
  Future<void> save(String uid, StudyBackup backup) async {}
}

typedef _Launch = ({
  FirebaseAuthService auth,
  ProviderContainer container,
  _Auth firebase,
  LocalStore store,
});

/// Opens the app the way bootstrap() does, with [storedUid]'s profile on the
/// device and [user] as the credential Firebase holds at start.
Future<_Launch> _launch({
  String storedUid = 'alex',
  bool storedSignedOut = false,
  User? user,
  _Backend? backend,
}) async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();
  await store.clearAll();
  await store.setMap(
    StoreKeys.user,
    UserProfile(
      uid: storedUid,
      displayName: 'Alex',
      isAnonymous: storedSignedOut,
      onboardingComplete: true,
    ).toJson(),
  );
  await store.setBool('achievements.linked.$storedUid', true);
  final firebase = _Auth(user);
  final auth = FirebaseAuthService(
    store,
    firebaseAuth: firebase,
    studyBackup: StudyBackupService(store, backend ?? _Backend()),
  );
  final container = ProviderContainer(
    overrides: [
      localStoreProvider.overrideWithValue(store),
      authServiceProvider.overrideWithValue(auth),
    ],
  );
  container
      .read(userProvider.notifier)
      .hydrate(UserProfile.fromJson(store.getMap(StoreKeys.user)!));
  void closeGates() {
    final local = container.read(userProvider);
    if (!local.isAnonymous) {
      container
          .read(userProvider.notifier)
          .hydrate(local.copyWith(isAnonymous: true));
    }
  }

  // The same bridge bootstrap() installs.
  final bridge = auth.changes.listen((profile) {
    if (profile != null) {
      if (auth.current?.uid != profile.uid) return;
      hydrateStudyAccount(container, store);
      container.read(userProvider.notifier).hydrate(profile);
    } else if (!auth.signedIn) {
      closeGates();
    }
  });
  if (!auth.signedIn) closeGates();
  addTearDown(() async {
    await bridge.cancel();
    container.dispose();
    auth.dispose();
    await firebase.controller.close();
  });
  return (auth: auth, container: container, firebase: firebase, store: store);
}

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a failed token refresh keeps this phone\'s own account signed in',
    () async {
      // An earlier interruption left the account stored as signed out, so this
      // launch runs the full recovery, and the network then fails.
      final app = await _launch(
        storedSignedOut: true,
        user: _User(refreshFails: true),
      );
      await app.auth.restore();
      await _settle();
      expect(app.auth.signedIn, isTrue);
      expect(app.auth.restorationPending, isFalse);
      expect(app.container.read(userProvider).isAnonymous, isFalse);
      expect(app.store.getMap(StoreKeys.user)?['isAnonymous'], isFalse);
    },
  );

  test('an account Firebase reports late survives a failed refresh', () async {
    final app = await _launch();
    expect(app.container.read(userProvider).isAnonymous, isTrue);
    app.firebase.user = _User(refreshFails: true);
    app.firebase.controller.add(app.firebase.user);
    await _settle();
    expect(app.auth.signedIn, isTrue);
    expect(app.container.read(userProvider).isAnonymous, isFalse);
  });

  test(
    'another account\'s failed recovery keeps its features locked',
    () async {
      final app = await _launch(
        storedUid: 'someone-else',
        user: _User(refreshFails: true),
      );
      await expectLater(
        app.auth.restore(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.failure,
            'failure',
            AuthFailure.recoveryFailed,
          ),
        ),
      );
      expect(app.auth.signedIn, isFalse);
      expect(app.auth.restorationPending, isTrue);
      expect(app.container.read(userProvider).isAnonymous, isTrue);
    },
  );

  test(
    'an edit during recovery does not store the account as signed out',
    () async {
      final backend = _Backend()..held = Completer<StudyBackup?>();
      final app = await _launch(
        storedSignedOut: true,
        user: _User(),
        backend: backend,
      );
      final restoring = app.auth.restore();
      await _settle();
      expect(app.auth.restorationPending, isTrue);
      expect(app.container.read(userProvider).isAnonymous, isTrue);

      await app.container.read(userProvider.notifier).setDailyGoal(90);
      expect(app.store.getMap(StoreKeys.user)?['isAnonymous'], isFalse);

      backend.held!.complete(null);
      await restoring;
      await _settle();
      expect(app.auth.signedIn, isTrue);
      expect(app.container.read(userProvider).isAnonymous, isFalse);
    },
  );
}
