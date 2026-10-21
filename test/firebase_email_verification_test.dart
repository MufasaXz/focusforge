import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/services/auth_service.dart';
import 'package:focusforge/core/services/firebase_auth_service.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/study_backup_service.dart';

class _Backup implements StudyBackupBackend {
  StudyBackup? saved;
  bool failLoad = false;
  bool failSave = false;
  Object? loadFailure;
  int failuresLeft = 0;
  int loads = 0;
  int saves = 0;
  Completer<StudyBackup?>? delayedLoad;
  @override
  Future<StudyBackup?> load(String uid) async {
    loads++;
    if (failuresLeft-- > 0) throw loadFailure!;
    if (failLoad) throw StateError('offline');
    if (delayedLoad != null) return delayedLoad!.future;
    return saved;
  }

  @override
  Future<void> save(String uid, StudyBackup backup) async {
    saves++;
    if (failSave) throw StateError('offline');
    saved = backup;
  }
}

class _Info implements UserInfo {
  @override
  String get providerId => 'password';
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _User implements User {
  bool verified = false;
  bool anonymous = false;
  bool verifyOnReload = false;
  int emails = 0;
  Object? sendFailure;
  Object? reloadFailure;
  final events = <String>[];
  @override
  String get uid => 'email-account';
  @override
  String get email => 'person@example.com';
  @override
  String get displayName => 'Person';
  @override
  bool get emailVerified => verified;
  @override
  bool get isAnonymous => anonymous;
  @override
  List<UserInfo> get providerData => anonymous ? [] : [_Info()];
  @override
  Future<void> sendEmailVerification([ActionCodeSettings? settings]) async {
    if (sendFailure case final failure?) throw failure;
    emails++;
  }

  @override
  Future<void> reload() async {
    events.add('reload');
    if (reloadFailure case final failure?) throw failure;
    if (verifyOnReload) verified = true;
  }

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    events.add('refresh:$forceRefresh');
    return 'not-a-real-token';
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Credential implements UserCredential {
  _Credential(this.user);
  @override
  final User user;
  @override
  AdditionalUserInfo? get additionalUserInfo => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Auth implements FirebaseAuth {
  final user = _User();
  bool closed = false;
  Object? loginFailure;
  Object? resetFailure;
  String? resetEmail;
  Completer<void>? credentialDelay;
  final controller = StreamController<User?>.broadcast();
  @override
  User? get currentUser => closed ? null : user;
  @override
  Stream<User?> authStateChanges() => controller.stream;
  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    if (loginFailure case final failure?) throw failure;
    closed = false;
    controller.add(user);
    await credentialDelay?.future;
    return _Credential(user);
  }

  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) => signInWithEmailAndPassword(email: email, password: password);
  @override
  Future<void> signOut() async {
    closed = true;
    controller.add(null);
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    ActionCodeSettings? actionCodeSettings,
  }) async {
    resetEmail = email;
    if (resetFailure case final failure?) throw failure;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore store;
  late _Auth auth;
  late FirebaseAuthService service;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
    await store.clearAll();
    await store.setBool('achievements.linked.guest', false);
    await store.setMap(
      StoreKeys.user,
      const UserProfile(
        uid: 'guest',
        displayName: 'Ari',
        onboardingComplete: true,
      ).toJson(),
    );
    auth = _Auth();
    service = FirebaseAuthService(store, firebaseAuth: auth);
  });
  tearDown(() async {
    service.dispose();
    await auth.controller.close();
  });
  test(
    'password reset trims email and keeps unknown accounts private',
    () async {
      await service.sendPasswordReset(' person@example.com ');
      expect(auth.resetEmail, 'person@example.com');
      auth.resetFailure = FirebaseAuthException(code: 'user-not-found');
      await service.sendPasswordReset('unknown@example.com');
    },
  );
  test('password reset surfaces delivery and connection errors', () async {
    auth.resetFailure = FirebaseAuthException(code: 'network-request-failed');
    await expectLater(
      service.sendPasswordReset('person@example.com'),
      throwsA(
        isA<AuthException>().having(
          (error) => error.failure,
          'failure',
          AuthFailure.network,
        ),
      ),
    );
  });
  test(
    'unverified sign-in never adopts linked profile even through auth stream',
    () async {
      await expectLater(
        service.signInWithEmail('person@example.com', 'password'),
        throwsA(isA<AuthException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.signedIn, isFalse);
      expect(service.current, isNull);
      expect(store.getMap(StoreKeys.user)?['uid'], 'guest');
      expect(store.getMap(StoreKeys.user)?['isAnonymous'], isTrue);
    },
  );
  test('signup sends verification and leaves app account locked', () async {
    await expectLater(
      service.signUpWithEmail('person@example.com', 'password'),
      throwsA(isA<AuthException>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(auth.user.emails, 1);
    expect(service.signedIn, isFalse);
    expect(store.getMap(StoreKeys.user)?['uid'], 'guest');
  });
  test('relaunch cannot restore an unverified account as linked', () async {
    expect(await service.restore(), isNull);
    expect(service.signedIn, isFalse);
    expect(store.getMap(StoreKeys.user)?['uid'], 'guest');
  });
  test(
    'an app update keeps the existing session open during background sync',
    () async {
      service.dispose();
      auth.user.verified = true;
      await store.setMap(
        StoreKeys.user,
        const UserProfile(
          uid: 'email-account',
          displayName: 'Ari',
          isAnonymous: false,
          onboardingComplete: true,
        ).toJson(),
      );
      // A linked profile from an older release has no private-backup marker.
      await store.remove('achievements.linked.email-account');
      final backend = _Backup()..delayedLoad = Completer<StudyBackup?>();
      service = FirebaseAuthService(
        store,
        firebaseAuth: auth,
        studyBackup: StudyBackupService(store, backend),
      );
      expect(service.signedIn, isTrue);
      expect(service.current?.displayName, 'Ari');
      expect(service.restorationPending, isFalse);
      expect(service.recoveryState.value, isNull);
      final syncing = service.restore();
      await Future<void>.delayed(Duration.zero);
      expect(service.signedIn, isTrue);
      expect(service.recoveryState.value, isNull);
      backend.delayedLoad!.complete(null);
      await syncing;
      await service.signOut();
      backend.delayedLoad = Completer<StudyBackup?>();
      final signingIn = service.signInWithEmail(
        'person@example.com',
        'password',
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.recoveryState.value, isNotNull);
      backend.delayedLoad!.complete(null);
      await signingIn;
    },
  );
  test(
    'an older linked session stays signed in when background sync is offline',
    () async {
      service.dispose();
      auth.user.verified = true;
      await store.setMap(
        StoreKeys.user,
        const UserProfile(
          uid: 'email-account',
          isAnonymous: false,
          onboardingComplete: true,
        ).toJson(),
      );
      await store.remove('achievements.linked.email-account');
      await store.setInt(StoreKeys.dailyGoal, 480);
      final backend = _Backup()..failLoad = true;
      final backup = StudyBackupService(store, backend);
      service = FirebaseAuthService(
        store,
        firebaseAuth: auth,
        studyBackup: backup,
      );
      await service.restore();
      expect(service.signedIn, isTrue);
      expect(service.restorationPending, isFalse);
      expect(service.recoveryState.value, isNull);
      expect(store.getInt(StoreKeys.dailyGoal), 480);
      // The failed server read must still prevent uploading unmerged settings.
      await expectLater(backup.flush(), throwsStateError);
      expect(backend.saves, 0);
    },
  );
  for (final localName in ['Old name', '']) {
    test(
      'normalizing an upgraded profile ($localName) cannot outrank newer saved settings',
      () async {
        service.dispose();
        auth.user.verified = true;
        final legacy = {
          'uid': 'email-account',
          'displayName': localName,
          'isAnonymous': false,
          'onboardingComplete': true,
        };
        await store.setMap(StoreKeys.user, legacy);
        await store.remove('study.modified.email-account');
        await store.setInt(StoreKeys.dailyGoal, 180);
        final backend = _Backup()
          ..saved = StudyBackup(
            settings: {
              StoreKeys.user: jsonEncode({
                ...legacy,
                'displayName': 'Saved name',
              }),
              StoreKeys.dailyGoal: 480,
            },
            sessions: [],
            modifiedAt: 123,
          );
        final backup = StudyBackupService(store, backend);
        service = FirebaseAuthService(
          store,
          firebaseAuth: auth,
          studyBackup: backup,
        );
        await service.restore();
        await backup.flush();
        expect(store.getMap(StoreKeys.user)?['displayName'], 'Saved name');
        expect(store.getInt(StoreKeys.dailyGoal), 480);
        expect(backend.saved?.modifiedAt, 123);
        expect(backend.saved?.settings[StoreKeys.dailyGoal], 480);
      },
    );
  }
  test(
    'signout cancels a delayed background read before it completes',
    () async {
      service.dispose();
      auth.user.verified = true;
      await store.setMap(
        StoreKeys.user,
        const UserProfile(
          uid: 'email-account',
          isAnonymous: false,
          onboardingComplete: true,
        ).toJson(),
      );
      final delayed = Completer<StudyBackup?>();
      final backend = _Backup()..delayedLoad = delayed;
      final backup = StudyBackupService(store, backend);
      service = FirebaseAuthService(
        store,
        firebaseAuth: auth,
        studyBackup: backup,
      );
      final events = <UserProfile?>[];
      final subscription = service.changes.listen(events.add);
      addTearDown(subscription.cancel);
      final syncing = backup.flush().then<Object?>(
        (_) => null,
        onError: (Object error) => error,
      );
      await Future<void>.delayed(Duration.zero);
      expect(backend.loads, 1);
      final closing = service.signOut();
      var closed = false;
      unawaited(closing.then((_) => closed = true));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final closedBeforeRead = closed;
      delayed.complete(null);
      await closing;
      await syncing;
      await Future<void>.delayed(Duration.zero);
      expect(closedBeforeRead, isTrue);
      expect(auth.closed, isTrue);
      expect(service.signedIn, isFalse);
      expect(backend.saves, 0);
      expect(events.whereType<UserProfile>(), isEmpty);
      expect(store.getMap('study.account.email-account'), isNotNull);
    },
  );
  test('verified email account signs in and preserves setup', () async {
    auth.user.verified = true;
    final profile = await service.signInWithEmail(
      'person@example.com',
      'password',
    );
    expect(profile.isAnonymous, isFalse);
    expect(profile.onboardingComplete, isTrue);
    expect(profile.displayName, 'Ari');
    expect(service.signedIn, isTrue);
  });
  for (final accountState in [
    'linked',
    'signed-out',
    'legacy-signed-out',
    'session-only',
  ]) {
    test(
      'a different account cannot inherit the previous profile ($accountState)',
      () async {
        service.dispose();
        await store.clearAll();
        await store.setMap(
          StoreKeys.user,
          UserProfile(
            uid: 'previous-account',
            displayName: 'Private previous name',
            isAnonymous: accountState.endsWith('signed-out'),
            dailyGoalMinutes: 555,
          ).toJson(),
        );
        if (accountState != 'legacy-signed-out') {
          await store.setBool('achievements.linked.previous-account', true);
        }
        auth.user.verified = true;
        final backend = _Backup();
        if (accountState == 'session-only') {
          backend.saved = const StudyBackup(
            settings: {},
            sessions: [],
            modifiedAt: 0,
            hasSettings: false,
          );
        }
        final backup = StudyBackupService(store, backend);
        service = FirebaseAuthService(
          store,
          firebaseAuth: auth,
          studyBackup: backup,
        );
        final profile = await service.restore();
        expect(profile?.displayName, 'Person');
        expect(profile?.dailyGoalMinutes, isNot(555));
        await backup.flush();
        final saved = jsonDecode(
          backend.saved!.settings[StoreKeys.user] as String,
        ) as Map<String, dynamic>;
        expect(saved['displayName'], 'Person');
      },
    );
  }
  test(
    'a confirmed unlinked guest still promotes its own setup and name',
    () async {
      service.dispose();
      auth.user.verified = true;
      final backend = _Backup();
      final backup = StudyBackupService(store, backend);
      service = FirebaseAuthService(
        store,
        firebaseAuth: auth,
        studyBackup: backup,
      );
      final profile = await service.restore();
      expect(profile?.displayName, 'Ari');
      expect(profile?.onboardingComplete, isTrue);
      await backup.flush();
      final saved =
          jsonDecode(backend.saved!.settings[StoreKeys.user] as String) as Map;
      expect(saved['displayName'], 'Ari');
    },
  );
  for (final localFallback in [false, true]) {
    test(
      'Skip cannot turn an unknown previous account into a transferable guest (fallback: $localFallback)',
      () async {
        service.dispose();
        await store.clearAll();
        await store.setMap(
          StoreKeys.user,
          const UserProfile(
            uid: 'old-linked-account',
            displayName: 'Private previous name',
            isAnonymous: true,
          ).toJson(),
        );
        auth.closed = true;
        auth.user.verified = true;
        final backend = _Backup();
        final backup = StudyBackupService(store, backend);
        service = FirebaseAuthService(
          store,
          firebaseAuth: auth,
          studyBackup: backup,
        );
        if (localFallback) {
          final guestAuth = GuestOnlyAuthService(store);
          await guestAuth.signInAnonymously();
          guestAuth.dispose();
        } else {
          await service.signInAnonymously();
        }
        final profile = await service.signInWithEmail(
          'person@example.com',
          'password',
        );
        expect(profile.displayName, 'Person');
        await backup.flush();
        expect(
          backend.saved!.settings[StoreKeys.user],
          isNot(contains('Private previous name')),
        );
      },
    );
  }
  test('wrong password does not send mail or change local identity', () async {
    auth.loginFailure = FirebaseAuthException(code: 'invalid-credential');
    await expectLater(
      service.signInWithEmail('person@example.com', 'wrong'),
      throwsA(
        isA<AuthException>().having(
          (e) => e.failure,
          'failure',
          AuthFailure.wrongPassword,
        ),
      ),
    );
    expect(auth.user.emails, 0);
    expect(store.getMap(StoreKeys.user)?['uid'], 'guest');
  });
  test('verification refresh cannot unlock an unchanged email', () async {
    expect(await service.refreshEmailVerification(), isNull);
    expect(service.needsEmailVerification, isTrue);
    expect(service.signedIn, isFalse);
  });
  test(
    'mail link completion reloads and refreshes claim before linking',
    () async {
      auth.user.verifyOnReload = true;
      final profile = await service.refreshEmailVerification();
      expect(profile?.isAnonymous, isFalse);
      expect(profile?.onboardingComplete, isTrue);
      expect(auth.user.events, ['reload', 'refresh:true']);
      expect(service.needsEmailVerification, isFalse);
      expect(service.signedIn, isTrue);
    },
  );
  test('resend cooldown and send failures preserve pending identity', () async {
    auth.user.sendFailure = FirebaseAuthException(
      code: 'network-request-failed',
    );
    await expectLater(
      service.sendEmailVerification(),
      throwsA(
        isA<AuthException>().having(
          (e) => e.failure,
          'failure',
          AuthFailure.network,
        ),
      ),
    );
    expect(service.verificationResendAvailableAt, isNull);
    auth.user.sendFailure = null;
    await service.sendEmailVerification();
    await expectLater(
      service.sendEmailVerification(),
      throwsA(
        isA<AuthException>().having(
          (e) => e.failure,
          'failure',
          AuthFailure.tooManyRequests,
        ),
      ),
    );
    expect(auth.user.emails, 1);
    expect(service.signedIn, isFalse);
  });
  test('signout exits verification without losing local setup', () async {
    await service.signOut();
    expect(service.needsEmailVerification, isFalse);
    expect(service.current, isNull);
    expect(store.getMap(StoreKeys.user)?['onboardingComplete'], isTrue);
  });
  test(
    'canceled cloud recovery cannot reopen the gate after signout',
    () async {
      service.dispose();
      auth.user.verified = true;
      final backend = _Backup()..delayedLoad = Completer<StudyBackup?>();
      service = FirebaseAuthService(
        store,
        firebaseAuth: auth,
        studyBackup: StudyBackupService(store, backend),
      );
      final pending = service.restore().then(
        (_) => null,
        onError: (Object _) => null,
      );
      await Future<void>.delayed(Duration.zero);
      await service.signOut();
      backend.delayedLoad!.complete(null);
      await pending;
      expect(service.restorationPending, isFalse);
      expect(service.signedIn, isFalse);
      expect(await service.restore(), isNull);
      expect(service.restorationPending, isFalse);
    },
  );
  test(
    'offline signout closes credentials and keeps the pending local backup',
    () async {
      service.dispose();
      auth.user.verified = true;
      final backend = _Backup();
      final backup = StudyBackupService(store, backend);
      service = FirebaseAuthService(
        store,
        firebaseAuth: auth,
        studyBackup: backup,
      );
      await service.restore();
      await backup.flush();
      backend.failSave = true;
      await store.setInt(StoreKeys.dailyGoal, 480);
      await service.signOut();
      expect(auth.closed, isTrue);
      expect(service.current, isNull);
      expect(store.getMap('study.account.email-account'), isNotNull);
    },
  );
  test('failed account recovery stays retryable without replacing local or cloud data', () async {
    service.dispose();
    auth.user.verified = true;
    final backend = _Backup()..failLoad = true;
    service = FirebaseAuthService(
      store,
      firebaseAuth: auth,
      studyBackup: StudyBackupService(store, backend),
    );
    await expectLater(service.restore(), throwsA(isA<AuthException>()));
    expect(service.restorationPending, isTrue);
    expect(service.current, isNull);
    expect(service.signedIn, isFalse);
    expect(store.getMap(StoreKeys.user)?['uid'], 'guest');
    backend.failLoad = false;
    final recovered = await service.restore();
    expect(recovered?.uid, 'email-account');
    expect(service.restorationPending, isFalse);
    expect(service.signedIn, isTrue);
  });
  test(
    'temporary cloud failure automatically recovers without another sign-in',
    () async {
      service.dispose();
      auth.user.verified = true;
      final backend = _Backup()
        ..loadFailure = FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unavailable',
        )
        ..failuresLeft = 1;
      service = FirebaseAuthService(
        store,
        firebaseAuth: auth,
        studyBackup: StudyBackupService(store, backend),
      );
      final profile = await service.restore();
      expect(profile?.uid, 'email-account');
      expect(service.signedIn, isTrue);
      expect(backend.loads, 2);
    },
  );

  test(
    'cloud permission rejection refreshes credential before one retry',
    () async {
      service.dispose();
      auth.user.verified = true;
      final backend = _Backup()
        ..loadFailure = FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
        )
        ..failuresLeft = 1;
      service = FirebaseAuthService(
        store,
        firebaseAuth: auth,
        studyBackup: StudyBackupService(store, backend),
      );
      expect((await service.restore())?.uid, 'email-account');
      expect(auth.user.events, contains('refresh:true'));
      expect(service.signedIn, isTrue);
    },
  );

  test(
    'non-network recovery errors are not described as an internet failure',
    () async {
      service.dispose();
      auth.user.verified = true;
      final backend = _Backup()..failLoad = true;
      service = FirebaseAuthService(
        store,
        firebaseAuth: auth,
        studyBackup: StudyBackupService(store, backend),
      );
      await expectLater(
        service.restore(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.failure,
            'failure',
            isNot(AuthFailure.network),
          ),
        ),
      );
      expect(store.getMap(StoreKeys.user)?['uid'], 'guest');
      expect(service.restorationPending, isTrue);
    },
  );

  test('SDK event and explicit restore share a single account read', () async {
    service.dispose();
    auth.user.verified = true;
    final backend = _Backup()..delayedLoad = Completer<StudyBackup?>();
    service = FirebaseAuthService(
      store,
      firebaseAuth: auth,
      studyBackup: StudyBackupService(store, backend),
    );
    final first = service.restore();
    auth.controller.add(auth.user);
    final second = service.restore();
    await Future<void>.delayed(Duration.zero);
    expect(backend.loads, 1);
    backend.delayedLoad!.complete(null);
    expect((await first)?.uid, 'email-account');
    expect((await second)?.uid, 'email-account');
    expect(service.recoveryState.value, isNull);
  });

  test('same-account relogin starts a fresh recovery after signout', () async {
    service.dispose();
    auth.user.verified = true;
    final oldRead = Completer<StudyBackup?>();
    final backend = _Backup()..delayedLoad = oldRead;
    service = FirebaseAuthService(
      store,
      firebaseAuth: auth,
      studyBackup: StudyBackupService(store, backend),
    );
    final first = service.restore().then<Object?>(
      (value) => value,
      onError: (Object error) => error,
    );
    await Future<void>.delayed(Duration.zero);
    await service.signOut();
    backend.delayedLoad = null;
    final second = service
        .signInWithEmail('person@example.com', 'password')
        .then<Object?>((value) => value, onError: (Object error) => error);
    expect(
      await second.timeout(const Duration(seconds: 2)),
      isA<UserProfile>().having(
        (profile) => profile.uid,
        'uid',
        'email-account',
      ),
    );
    oldRead.complete(null);
    expect(
      await first,
      isA<AuthException>().having(
        (error) => error.failure,
        'failure',
        AuthFailure.cancelled,
      ),
    );
    expect(backend.loads, 2);
    expect(service.signedIn, isTrue);
    expect(service.restorationPending, isFalse);
    expect(service.recoveryState.value, isNull);
  });

  test(
    'guest skip works locally and survives the initial null SDK event',
    () async {
      auth.closed = true;
      final guest = await service.signInAnonymously();
      expect(guest.isAnonymous, isTrue);
      expect(service.current?.uid, guest.uid);
      auth.controller.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(service.current?.uid, guest.uid);
      expect(service.signedIn, isTrue);
    },
  );

  test('successful recovery refreshes token before cloud access', () async {
    service.dispose();
    auth.user.verified = true;
    final backend = _Backup();
    service = FirebaseAuthService(
      store,
      firebaseAuth: auth,
      studyBackup: StudyBackupService(store, backend),
    );
    await service.restore();
    expect(auth.user.events, contains('refresh:true'));
    expect(service.signedIn, isTrue);
  });

  test('stale anonymous edit cannot close a recovered account', () async {
    service.dispose();
    auth.user.verified = true;
    service = FirebaseAuthService(store, firebaseAuth: auth);
    final recovered = await service.restore();
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        authServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);
    container.read(userProvider.notifier).hydrate(recovered);
    await container
        .read(userProvider.notifier)
        .save(
          recovered!.copyWith(isAnonymous: true, displayName: 'Updated name'),
        );
    expect(container.read(userProvider).isAnonymous, isFalse);
    expect(container.read(accountUidProvider), 'email-account');
    expect(store.getMap(StoreKeys.user)?['isAnonymous'], isFalse);
    expect(container.read(userProvider).displayName, 'Updated name');
  });

  test(
    'early SDK sign-in event waits for the credential owner to recover',
    () async {
      service.dispose();
      auth.user.verified = true;
      auth.closed = true;
      auth.credentialDelay = Completer<void>();
      final backend = _Backup();
      service = FirebaseAuthService(
        store,
        firebaseAuth: auth,
        studyBackup: StudyBackupService(store, backend),
      );
      final signingIn = service.signInWithEmail(
        'person@example.com',
        'password',
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        backend.loads,
        0,
        reason: 'The SDK event must not start a competing recovery before credentials return',
      );
      auth.credentialDelay!.complete();
      expect((await signingIn).isAnonymous, isFalse);
      expect(backend.loads, 1);
      expect(service.restorationPending, isFalse);
      expect(service.recoveryState.value, isNull);
    },
  );
}
