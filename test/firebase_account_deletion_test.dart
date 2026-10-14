import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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

  @override
  String get uid => 'deletion-user';
  @override
  bool get isAnonymous => true;
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

class _Auth implements FirebaseAuth {
  _Auth(this.user, this.events);
  final _User user;
  final List<String> events;
  bool closed = false;
  Object? signOutFailure;

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
  Future<void> waitForPendingWrites() async {
    events.add('pendingWrites');
    if (pendingFailure case final failure?) throw failure;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Result<T> implements HttpsCallableResult<T> {
  _Result(this.data);
  @override
  final T data;
}

class _Callable implements HttpsCallable {
  _Callable(this.events);
  final List<String> events;
  Object? failure;
  Map<String, dynamic> result = {'deleted': true};

  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    events.add('deleteCloud');
    expect(
      parameters,
      isNull,
      reason: 'The server must derive the caller UID.',
    );
    if (failure case final error?) throw error;
    return _Result(result as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Functions implements FirebaseFunctions {
  _Functions(this.callable);
  final _Callable callable;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    expect(name, 'deleteFocusForgeAccount');
    return callable;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Google implements GoogleSignIn {
  _Google(this.events);
  final List<String> events;
  Object? failure;

  @override
  Future<GoogleSignInAccount?> signOut() async {
    events.add('providerSignOut');
    if (failure case final error?) throw error;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore store;
  late FirebaseAuthService service;
  late _Auth auth;
  late _Firestore firestore;
  late _Callable callable;
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
    callable = _Callable(events);
    google = _Google(events);
    service = FirebaseAuthService(
      store,
      firebaseAuth: auth,
      firestore: firestore,
      functions: _Functions(callable),
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
    'missing deletion endpoint gives a support error and preserves local data',
    () async {
      callable.failure = FirebaseFunctionsException(
        code: 'not-found',
        message: 'NOT FOUND',
      );
      await expectFailure('deletionUnavailable');
      expect(events, ['pendingWrites', 'refresh:true', 'deleteCloud']);
    },
  );

  test('server recent-login rejection stays actionable instead of becoming cleanup failure', () async {
    callable.failure = FirebaseFunctionsException(
      code: 'failed-precondition',
      message: 'recent login required',
    );
    await expectFailure('requiresRecentLogin');
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

  test(
    'a partial or unconfirmed server result never wipes the device',
    () async {
      callable.result = {'deleted': false};
      await expectFailure('cleanupFailed');
    },
  );

  test('an interrupted cleanup remains retryable with local data until confirmation', () async {
    callable.failure = FirebaseFunctionsException(
      code: 'unavailable',
      message: 'Cleanup is not finished.',
    );
    await expectFailure('cleanupFailed');
    callable.failure = null;
    events.clear();
    await service.deleteAccount();
    expect(events, [
      'pendingWrites',
      'refresh:true',
      'deleteCloud',
      'signOut',
      'providerSignOut',
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
        functions: _Functions(callable),
        googleSignIn: google,
      );
      expect(await service.restore(), isNull);
      expect(service.signedIn, isFalse);
      expect(store.getMap(StoreKeys.user), isNull);
    },
  );

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
