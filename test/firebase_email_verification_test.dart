import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/services/auth_service.dart';
import 'package:focusforge/core/services/firebase_auth_service.dart';
import 'package:focusforge/core/services/local_store.dart';

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
}
