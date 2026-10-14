import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:focusforge/core/services/firestore_account_cleanup.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/core/services/auth_service.dart';
import 'package:focusforge/core/services/firebase_auth_service.dart';
import 'package:focusforge/core/services/local_store.dart';

class _User implements User {
  _User(this.events);
  final List<String> events;
  Object? tokenFailure;
  Object? deleteFailure;
  bool anonymous = true;
  bool googleProvider = false;
  Object? reauthFailure;
  @override
  String get email => 'sam@example.com';
  @override
  Future<UserCredential> reauthenticateWithCredential(
    AuthCredential credential,
  ) async {
    events.add('reauthenticate:${credential.providerId}');
    if (reauthFailure case final error?) throw error;
    return _Credential(this);
  }

  @override
  List<UserInfo> get providerData => anonymous
      ? const []
      : [_Info(googleProvider ? 'google.com' : 'password')];
  @override
  UserMetadata get metadata => UserMetadata(0, 0);
  @override
  Future<void> delete() async {
    events.add('deleteAuth');
    if (deleteFailure case final error?) throw error;
  }

  @override
  String get uid => 'deletion-user';
  @override
  bool get isAnonymous => anonymous;
  @override
  String get displayName => 'Sam';
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    events.add('refresh:$forceRefresh');
    if (tokenFailure case final failure?) throw failure;
    return 'test-id-token';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Info implements UserInfo {
  _Info(this.providerId);
  @override
  final String providerId;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Credential implements UserCredential {
  _Credential(this.user);
  @override
  final User user;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements FirebaseAuth {
  _Auth(this.user, this.events);
  final _User user;
  final List<String> events;
  bool closed = false;
  Object? signOutFailure;
  Object? loginFailure;
  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    if (loginFailure case final error?) throw error;
    throw StateError('Unexpected login');
  }

  @override
  User? get currentUser => closed ? null : user;
  @override
  Stream<User?> authStateChanges() => const Stream.empty();
  @override
  Future<void> signOut() async {
    events.add('signOut');
    if (signOutFailure case final error?) throw error;
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Firestore implements FirebaseFirestore {
  _Firestore(this.events);
  final List<String> events;
  Object? pendingFailure;

  @override
  Future<void> terminate() async {
    events.add('terminateCache');
  }

  @override
  Future<void> clearPersistence() async {
    events.add('clearCache');
  }

  @override
  Future<void> waitForPendingWrites() async {
    events.add('pendingWrites');
    if (pendingFailure case final failure?) throw failure;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cleanup extends FirestoreAccountCleanup {
  _Cleanup(super.db, this.events);
  final List<String> events;
  Object? failure;
  @override
  Future<void> deleteUserData(String uid) async {
    events.add('deleteCloud:$uid');
    if (failure case final error?) throw error;
  }
}

class _Google implements GoogleSignIn {
  _Google(this.events);
  final List<String> events;
  Object? failure;
  bool cancelled = false;
  @override
  Future<GoogleSignInAccount?> signIn() async {
    events.add('googleSignIn');
    return cancelled ? null : _GoogleAccount();
  }

  @override
  Future<GoogleSignInAccount?> signOut() async {
    events.add('providerSignOut');
    if (failure case final error?) throw error;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GoogleAccount implements GoogleSignInAccount {
  @override
  Future<GoogleSignInAuthentication> get authentication async =>
      _GoogleTokens();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GoogleTokens implements GoogleSignInAuthentication {
  @override
  String get idToken => 'fake-test-token';
  @override
  String get accessToken => 'fake-test-access';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore store;
  late FirebaseAuthService service;
  late _Auth auth;
  late _Firestore firestore;
  late _Cleanup cleanup;
  late _Google google;
  late List<String> events;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
    await store.clearAll();
    await store.setList(StoreKeys.sessions, [
      {'id': 'keep-until-confirmed'},
    ]);
    events = [];
    auth = _Auth(_User(events), events);
    firestore = _Firestore(events);
    cleanup = _Cleanup(firestore, events);
    google = _Google(events);
    service = FirebaseAuthService(
      store,
      firebaseAuth: auth,
      firestore: firestore,
      accountCleanup: cleanup,
      googleSignIn: google,
    );
    await service.restore();
  });
  tearDown(() => service.dispose());

  Future<void> expectFailure(String name) async {
    await expectLater(
      service.deleteAccount(),
      throwsA(
        isA<AuthException>().having((e) => e.failure.name, 'failure', name),
      ),
    );
    expect(auth.closed, isFalse);
    expect(service.current?.uid, 'deletion-user');
    expect(store.getList(StoreKeys.sessions), [
      {'id': 'keep-until-confirmed'},
    ]);
  }

  test(
    'Firestore permission failure preserves Auth and local history',
    () async {
      cleanup.failure = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      await expectFailure('cleanupFailed');
      expect(events, [
        'pendingWrites',
        'refresh:true',
        'deleteCloud:deletion-user',
      ]);
    },
  );
  test(
    'Auth recent-login rejection keeps retryable identity and local data',
    () async {
      auth.user.deleteFailure = FirebaseAuthException(
        code: 'requires-recent-login',
      );
      await expectFailure('requiresRecentLogin');
      expect(events, [
        'pendingWrites',
        'refresh:true',
        'deleteCloud:deletion-user',
        'deleteAuth',
      ]);
    },
  );
  test('stale login cannot begin Firestore cleanup', () async {
    auth.user.anonymous = false;
    await expectFailure('requiresRecentLogin');
    expect(events, isEmpty);
  });

  test(
    'authentication-token network failure does not call deletion or erase data',
    () async {
      auth.user.tokenFailure = FirebaseAuthException(
        code: 'network-request-failed',
      );
      await expectFailure('network');
      expect(events, ['pendingWrites', 'refresh:true']);
    },
  );

  test(
    'pending-write timeout leaves deletion unstarted with sync guidance',
    () async {
      firestore.pendingFailure = TimeoutException('pending changes');
      await expectFailure('cloudSyncPending');
      expect(events, ['pendingWrites']);
    },
  );

  test('an interrupted cleanup remains retryable with local data until confirmation', () async {
    cleanup.failure = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'unavailable',
      message: 'Cleanup is not finished.',
    );
    await expectFailure('cleanupFailed');
    cleanup.failure = null;
    events.clear();
    await service.deleteAccount();
    expect(events, [
      'pendingWrites',
      'refresh:true',
      'deleteCloud:deletion-user',
      'deleteAuth',
      'signOut',
      'providerSignOut',
      'terminateCache',
      'clearCache',
    ]);
    expect(auth.closed, isTrue);
    expect(service.current, isNull);
    expect(store.getList(StoreKeys.sessions), isEmpty);
  });

  test('confirmed deletion erases history when Firebase credential-cache signout fails', () async {
    auth.signOutFailure = StateError('signout channel failure');
    await service.deleteAccount();
    expect(store.getList(StoreKeys.sessions), isEmpty);
    expect(service.current, isNull);
    expect(service.signedIn, isFalse);
    await service.restore();
    expect(service.current, isNull);
    expect(store.getMap(StoreKeys.user), isNull);
  });

  test(
    'a stale deleted credential cannot restore a profile after a restart',
    () async {
      auth.signOutFailure = StateError('signout channel failure');
      await service.deleteAccount();
      service.dispose();
      service = FirebaseAuthService(
        store,
        firebaseAuth: auth,
        firestore: firestore,
        accountCleanup: cleanup,
        googleSignIn: google,
      );
      expect(await service.restore(), isNull);
      expect(service.signedIn, isFalse);
      expect(store.getMap(StoreKeys.user), isNull);
    },
  );

  test('disabled email provider gives an actionable error before local profile changes', () async {
    auth.loginFailure = FirebaseAuthException(code: 'operation-not-allowed');
    await expectLater(
      service.signInWithEmail('sam@example.com', 'password'),
      throwsA(
        isA<AuthException>().having(
          (e) => e.failure,
          'failure',
          AuthFailure.providerUnavailable,
        ),
      ),
    );
    expect(store.getList(StoreKeys.sessions), isNotEmpty);
  });

  test(
    'email reauthentication permits data cleanup then Auth deletion',
    () async {
      auth.user.anonymous = false;
      await service.reauthenticate(password: 'secret-not-logged');
      await service.deleteAccount();
      expect(events.take(5), [
        'reauthenticate:password',
        'pendingWrites',
        'refresh:true',
        'deleteCloud:deletion-user',
        'deleteAuth',
      ]);
      expect(store.getList(StoreKeys.sessions), isEmpty);
    },
  );
  test('wrong password cannot authorise destructive cleanup', () async {
    auth.user.anonymous = false;
    auth.user.reauthFailure = FirebaseAuthException(code: 'invalid-credential');
    await expectLater(
      service.reauthenticate(password: 'incorrect'),
      throwsA(
        isA<AuthException>().having(
          (e) => e.failure,
          'failure',
          AuthFailure.wrongPassword,
        ),
      ),
    );
    await expectFailure('requiresRecentLogin');
    expect(events, ['reauthenticate:password']);
  });

  test(
    'Google account chooser reauthenticates before destructive cleanup',
    () async {
      auth.user.anonymous = false;
      auth.user.googleProvider = true;
      await service.reauthenticate();
      await service.deleteAccount();
      expect(events.take(7), [
        'providerSignOut',
        'googleSignIn',
        'reauthenticate:google.com',
        'pendingWrites',
        'refresh:true',
        'deleteCloud:deletion-user',
        'deleteAuth',
      ]);
    },
  );
  test('cancelled Google confirmation never authorises cleanup', () async {
    auth.user.anonymous = false;
    auth.user.googleProvider = true;
    google.cancelled = true;
    await expectLater(
      service.reauthenticate(),
      throwsA(
        isA<AuthException>().having(
          (e) => e.failure,
          'failure',
          AuthFailure.cancelled,
        ),
      ),
    );
    await expectFailure('requiresRecentLogin');
    expect(events, ['providerSignOut', 'googleSignIn']);
  });

  test('signed-out local erase leaves the remote account alone', () async {
    auth.closed = true;
    await service.deleteAccount();
    expect(events, isEmpty);
    expect(store.getList(StoreKeys.sessions), isEmpty);
    expect(service.current, isNull);
  });

  test(
    'provider-cache cleanup failure cannot undo confirmed deletion',
    () async {
      google.failure = StateError('provider cache unavailable');
      await service.deleteAccount();
      expect(auth.closed, isTrue);
      expect(service.current, isNull);
      expect(store.getList(StoreKeys.sessions), isEmpty);
    },
  );
}
