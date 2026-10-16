import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import 'firestore_account_cleanup.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';

import '../models/user.dart';
import 'auth_service.dart';
import 'local_store.dart';
import 'study_backup_service.dart';

/// The Firebase-backed implementation of [AuthService].
///
/// LocalStore supports offline study. Verified linked accounts privately back
/// up study settings and sessions before a restored profile is published.
/// Optional groups, leaderboard sharing and badge backups have separate services.
///
/// Constructed only after `Firebase.initializeApp()` has succeeded; see
/// `bootstrap()`, which falls back to [LocalAuthService] otherwise.
class FirebaseAuthService extends AuthService {
  @override
  bool get usesRemoteCredentials => true;

  FirebaseAuthService(
    this._store, {
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
    FirestoreAccountCleanup? accountCleanup,
    GoogleSignIn? googleSignIn,
    this.studyBackup,
  }) : _auth = firebaseAuth ?? FirebaseAuth.instance,
       _firestoreOverride = firestore,
       _cleanupOverride = accountCleanup,
       _googleClient = googleSignIn {
    final credential = _auth.currentUser;
    _credentialUid = credential?.uid;
    if (credential != null &&
        !credential.isAnonymous &&
        !_requiresEmailVerification(credential) &&
        !_isDeletedCredential(credential)) {
      final stored = _store.getMap(StoreKeys.user);
      if (stored?['uid'] == credential.uid && stored?['isAnonymous'] == false) {
        // An update/relaunch retains this credential and its local snapshot.
        // Reconcile quietly; it is not a new sign-in or an account switch.
        _current = UserProfile.fromJson(stored!);
        _returning = true;
        studyBackup?.resumeLocal(_current!);
      } else if (studyBackup != null) {
        _restorationPending = true;
        recoveryState.value = AccountRecoveryStage.connecting;
      }
    }
    studyBackup?.onReconciled = (profile) {
      if (!_disposed &&
          _auth.currentUser?.uid == profile.uid &&
          !_restorationPending &&
          !_requiresEmailVerification(_auth.currentUser!)) {
        _current = profile;
        _controller.add(profile);
      }
    };
    // `authStateChanges()` is the single source of stream events: it fires
    // both for sessions started through this class and for ones it never saw
    // — a session restored on launch, a sign-out from elsewhere. Re-keying
    // every event onto the stored record before emitting is what keeps
    // listeners from ever observing a profile with a defaulted persona,
    // name or goal.
    _authSub = _auth.authStateChanges().listen((user) {
      unawaited(
        _onAuthStateChanged(user).catchError((Object error) {
          debugPrint(
            '[auth] Session restoration will retry on the next sign-in.',
          );
        }),
      );
    });
  }

  final LocalStore _store;
  final FirebaseAuth _auth;
  final FirebaseFirestore? _firestoreOverride;
  final FirestoreAccountCleanup? _cleanupOverride;
  final StudyBackupService? studyBackup;
  Future<void> _profileWrites = Future.value();
  Future<UserProfile>? _profileRecovery;
  String? _profileRecoveryUid;
  String? _credentialUid;
  int _credentialGeneration = 0;
  bool _disposed = false;
  bool _restorationPending = false;
  @override
  bool get restorationPending => _restorationPending;

  final _controller = StreamController<UserProfile?>.broadcast();
  StreamSubscription<User?>? _authSub;
  UserProfile? _current;
  bool _returning = false;
  DateTime? _reauthenticatedAt;
  DateTime? _verificationSentAt;
  String? _verificationSentUid;

  bool _requiresEmailVerification(User user) =>
      !user.isAnonymous &&
      user.providerData.any((provider) => provider.providerId == 'password') &&
      !user.emailVerified;

  @override
  bool get needsEmailVerification =>
      _auth.currentUser != null &&
      _requiresEmailVerification(_auth.currentUser!);

  @override
  String? get verificationEmail =>
      needsEmailVerification ? _auth.currentUser?.email : null;

  @override
  DateTime? get verificationResendAvailableAt =>
      _verificationSentUid == _auth.currentUser?.uid
      ? _verificationSentAt?.add(const Duration(seconds: 60))
      : null;

  @override
  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null || !_requiresEmailVerification(user)) return;
    final next = verificationResendAvailableAt;
    if (next != null && DateTime.now().isBefore(next)) {
      throw const AuthException(AuthFailure.tooManyRequests);
    }
    await _guard(() => user.sendEmailVerification());
    _verificationSentAt = DateTime.now();
    _verificationSentUid = user.uid;
  }

  @override
  Future<UserProfile?> refreshEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    await _guard(user.reload);
    final refreshed = _auth.currentUser;
    if (refreshed == null ||
        refreshed.uid != user.uid ||
        _requiresEmailVerification(refreshed)) {
      return null;
    }
    // Firestore must see the updated email_verified claim before sync starts.
    await _guard(() => refreshed.getIdToken(true));
    return _persist(_profileFor(refreshed, email: refreshed.email));
  }

  Future<UserProfile> _acceptEmailCredential(
    UserCredential credential, {
    required bool newAccount,
  }) async {
    final user = credential.user!;
    if (_requiresEmailVerification(user)) {
      _current = null;
      _controller.add(null);
      if (newAccount) {
        try {
          await sendEmailVerification();
        } on AuthException {
          // Keep the pending credential so the verification screen can retry.
        }
      }
      throw const AuthException(AuthFailure.emailVerificationRequired);
    }
    return _persist(_profileFor(user, email: user.email));
  }

  @override
  bool get isReturningUser => _returning;

  @override
  bool get supportsPasswordReauthentication =>
      _auth.currentUser?.providerData.any((p) => p.providerId == 'password') ==
      true;

  void _recognise(UserCredential credential) {
    _reauthenticatedAt = null;
    _returning =
        credential.additionalUserInfo?.isNewUser == false &&
        !credential.user!.isAnonymous;
  }

  @override
  UserProfile? get current => _current;

  @override
  bool get signedIn =>
      (_auth.currentUser != null &&
          !_restorationPending &&
          _current?.uid == _auth.currentUser?.uid &&
          !_isDeletedCredential(_auth.currentUser!) &&
          !needsEmailVerification) ||
      (_auth.currentUser == null && _current?.isAnonymous == true);

  bool _isDeletedCredential(User user) =>
      _store.getString('auth.deletedCredential') == user.uid;

  @override
  Stream<UserProfile?> get changes => _controller.stream;

  @override
  Future<UserProfile?> restore() async {
    final user = _auth.currentUser;
    if (user != null && _requiresEmailVerification(user)) {
      _current = null;
      return null;
    }
    if (user == null || _isDeletedCredential(user)) {
      _restorationPending = false;
      if (user != null) {
        try {
          await _auth.signOut();
        } catch (_) {}
      }
      _current = null;
      return null;
    }
    _returning = !user.isAnonymous;
    return _persist(_profileFor(user));
  }

  /// Opens a device-only guest immediately, preserving local setup choices.
  @override
  Future<UserProfile> signInAnonymously() async {
    if (_auth.currentUser case final user?) {
      if (_requiresEmailVerification(user)) {
        throw const AuthException(AuthFailure.emailVerificationRequired);
      }
      return _persist(_profileFor(user));
    }
    // Guest study needs no network credential. A local identity is promoted
    // when the user later proves ownership of an email/Google account.
    _returning = false;
    final stored = _store.getMap(StoreKeys.user);
    final base = stored == null
        ? UserProfile(
            uid: 'local-${DateTime.now().microsecondsSinceEpoch}',
            createdAt: DateTime.now(),
          )
        : UserProfile.fromJson(stored).copyWith(isAnonymous: true);
    return _persist(base);
  }

  /// Signs in with an email credential, then applies the same merge as the
  /// local implementation: the stored profile is the base, and only the uid
  /// and `isAnonymous` change. A malformed address and an empty password fail
  /// before the round-trip, exactly as they do offline.
  @override
  Future<UserProfile> signInWithEmail(String email, String password) async {
    _validateEmail(email);
    if (password.isEmpty) {
      throw const AuthException(AuthFailure.wrongPassword);
    }
    final credential = await _guard(
      () => _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      ),
    );
    _recognise(credential);
    return _acceptEmailCredential(credential, newAccount: false);
  }

  /// Same base and same fill-only-what-is-missing rule as [signInWithEmail]:
  /// neither path may reset the profile the user built.
  @override
  Future<UserProfile> signUpWithEmail(String email, String password) async {
    _validateEmail(email);
    if (password.length < 8) {
      throw const AuthException(AuthFailure.weakPassword);
    }
    final credential = await _guard(
      () => _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      ),
    );
    _returning = false;
    return _acceptEmailCredential(credential, newAccount: true);
  }

  /// Google is live on Android: `google-services.json` carries the Android
  /// OAuth client and the web client its ID tokens are minted against.
  ///
  /// The platform check is what keeps this honest elsewhere. The plugin needs
  /// a client id from each platform's own configuration, and only Android has
  /// one — on iOS the button would be live and fail on tap, which is the exact
  /// defect the capability surface exists to prevent. A Dart-level check is
  /// deliberate: asking the plugin would cross a platform channel from a
  /// getter the sign-in screen reads during build.
  ///
  /// Apple stays out everywhere — there is no Apple developer configuration,
  /// and an id listed here renders a button that can only fail.
  @override
  Set<String> get supportedProviders => {
    'email',
    if (defaultTargetPlatform == TargetPlatform.android) 'google',
  };

  /// Upgrades the current session in place, preserving the uid the stored
  /// profile is keyed on.
  ///
  /// A stored profile with no Firebase session — a refresh token revoked by a
  /// password change elsewhere, or the user removed in the console — is a
  /// reachable state: `bootstrap()` hydrates the record from the store without
  /// restoring a session. Refusing there would leave the study-groups gate
  /// shut with no way through, so this mints an anonymous session and re-keys
  /// the stored record to it. Persona, name, goal and onboarding survive and
  /// only the uid changes — exactly what the local implementation promises.
  ///
  /// Providers outside [supportedProviders] have no credential this backend
  /// could mint — the contract carries no OAuth token — so they are refused
  /// rather than silently upgraded on the device. Google is the exception: it
  /// takes the interactive path below, and its ID token is the credential.
  @override
  Future<UserProfile> linkAccount({
    required String provider,
    String? displayName,
    String? email,
  }) async {
    // This API receives no password/OAuth credential for email or local.
    // Email uses signInWithEmail/signUpWithEmail through EmailAuthSheet.
    if (provider != 'google' || !supportedProviders.contains(provider)) {
      throw const AuthException(AuthFailure.providerUnavailable);
    }
    return _linkWithGoogle();
  }

  /// Runs the interactive Google round-trip and applies the credential it
  /// yields to the current session.
  ///
  /// `linkWithCredential` is the default path because it keeps the uid the
  /// profile record and the study-groups gate are keyed on. When Firebase
  /// refuses because the Google account already belongs to a different user,
  /// signing into that user is the honest recovery — the caller has just
  /// proved ownership of it — and [_profileFor] re-keys the stored record onto
  /// the resulting uid either way, so nothing the user built is orphaned.
  Future<UserProfile> _linkWithGoogle() async {
    final GoogleSignInAccount? account;
    try {
      account = await _googleSignIn().signIn();
    } on PlatformException catch (e) {
      throw _translateGoogle(e);
    }
    // The plugin's own cancellation signal: null, not an exception.
    if (account == null) {
      throw const AuthException(AuthFailure.cancelled);
    }

    final idToken = (await account.authentication).idToken;
    if (idToken == null || idToken.isEmpty) {
      // A completed round-trip with no ID token is the client configuration
      // failing to mint one, not the user backing out — cancellation arrives
      // as a null account above.
      throw const AuthException(
        AuthFailure.providerUnavailable,
        'Google returned no ID token',
      );
    }
    final credential = GoogleAuthProvider.credential(idToken: idToken);

    Future<UserProfile> apply(User user) => _persist(
      _profileFor(
        user,
        providerName: account!.displayName,
        email: account.email,
      ),
    );

    final user = _auth.currentUser;
    if (user == null) {
      final result = await _guard(() => _auth.signInWithCredential(credential));
      _recognise(result);
      return apply(result.user!);
    }

    try {
      final result = await user.linkWithCredential(credential);
      _returning = false;
      return await apply(result.user!);
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        // Already attached to this user: the requested end state is reached.
        case 'provider-already-linked':
          _returning = true;
          return apply(user);
        // The Google account belongs to a different Firebase user. Ownership
        // was just proven, so signing into it is what the user asked for; the
        // stored record follows the uid through _profileFor.
        case 'credential-already-in-use' || 'email-already-in-use':
          final result = await _guard(
            () => _auth.signInWithCredential(credential),
          );
          _recognise(result);
          return apply(result.user!);
      }
      throw _translate(e);
    }
  }

  /// The plugin client, built once and reused.
  ///
  /// Constructing it crosses no channel and starts no flow, so unlike the
  /// service itself it costs nothing to hold. No `clientId`: on Android the
  /// plugin reads both the app client and the server client from
  /// `google-services.json`, and passing one would override that.
  GoogleSignIn? _googleClient;

  GoogleSignIn _googleSignIn() => _googleClient ??= GoogleSignIn();

  @override
  Future<void> sendPasswordReset(String email) async {
    _validateEmail(email);
    await _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));
  }

  @override
  Future<void> signOut() async {
    _reauthenticatedAt = null;
    _invalidateRecovery();
    try {
      await studyBackup?.prepareSignOut();
    } catch (_) {
      // flush caches the latest account snapshot before attempting upload.
      // Offline backup must never prevent closing the credential.
    }
    studyBackup?.disconnect();
    await _guard(() => _auth.signOut());
    try {
      await _googleSignIn().signOut();
    } catch (_) {
      // The Firebase session is already closed. A provider cache error must
      // not report a failed sign-out after it succeeded.
    }
    _current = null;
    _restorationPending = false;
    _controller.add(null);
  }

  @override
  Future<void> reauthenticate({String? password}) async {
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) return;
    if (supportsPasswordReauthentication) {
      if (password == null || password.isEmpty) {
        throw const AuthException(AuthFailure.wrongPassword);
      }
      await _guard(
        () => user.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: user.email!, password: password),
        ),
      );
      _reauthenticatedAt = DateTime.now();
      return;
    }
    if (user.providerData.any((p) => p.providerId == 'google.com')) {
      try {
        await _googleSignIn().signOut();
        final account = await _googleSignIn().signIn();
        if (account == null) throw const AuthException(AuthFailure.cancelled);
        final tokens = await account.authentication;
        await _guard(
          () => user.reauthenticateWithCredential(
            GoogleAuthProvider.credential(
              idToken: tokens.idToken,
              accessToken: tokens.accessToken,
            ),
          ),
        );
        _reauthenticatedAt = DateTime.now();
        return;
      } on PlatformException catch (e) {
        throw _translateGoogle(e);
      }
    }
    throw const AuthException(AuthFailure.requiresRecentLogin);
  }

  @override
  Future<void> deleteAccount() async {
    studyBackup?.disconnect();
    final user = _auth.currentUser;
    if (user == null) {
      // Sign out leaves the cloud account intact. Erase only this device
      // when no remote credential is available and the profile is anonymous.
      if (_store.getMap(StoreKeys.user)?['isAnonymous'] == false) {
        throw const AuthException(AuthFailure.requiresRecentLogin);
      }
      await _store.clearAll();
      _current = null;
      _returning = false;
      _reauthenticatedAt = null;
      _controller.add(null);
      return;
    }
    final recentlyConfirmed =
        _reauthenticatedAt != null &&
        DateTime.now().difference(_reauthenticatedAt!) <
            const Duration(minutes: 5);
    if (!user.isAnonymous && !recentlyConfirmed) {
      throw const AuthException(AuthFailure.requiresRecentLogin);
    }
    final db = _firestoreOverride ?? FirebaseFirestore.instance;
    try {
      await db.waitForPendingWrites().timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const AuthException(AuthFailure.cloudSyncPending);
    } on FirebaseException catch (e) {
      throw AuthException(AuthFailure.cloudSyncPending, e.code);
    }
    try {
      await user.getIdToken(true);
      await (_cleanupOverride ?? FirestoreAccountCleanup(db)).deleteUserData(
        user.uid,
      );
      // Auth last: any unsuccessful cloud operation retains a credential for
      // retry. This is a client SDK operation, with no paid backend dependency.
      await user.delete();
    } on FirebaseAuthException catch (e) {
      _reauthenticatedAt = null;
      throw _translate(e);
    } on FirebaseException catch (e) {
      throw AuthException(
        e.code == 'resource-exhausted'
            ? AuthFailure.tooManyRequests
            : AuthFailure.cleanupFailed,
        e.code,
      );
    } catch (_) {
      throw const AuthException(AuthFailure.cleanupFailed);
    }
    // user.delete() invalidates the session. Retain a UID-only fence until
    // SDK signout succeeds, so a stale credential cannot restore the profile.
    await _store.setString('auth.deletedCredential', user.uid);
    try {
      await _auth.signOut();
    } catch (_) {}
    try {
      await _googleSignIn().signOut();
    } catch (_) {}
    // Startup already disables Firestore disk persistence. Terminate drops
    // the old in-memory instance; clearPersistence also erases older disk
    // caches. Android's FlutterFire plugin recreates an instance on next use.
    try {
      await db.terminate().timeout(const Duration(seconds: 10));
      await db.clearPersistence().timeout(const Duration(seconds: 10));
    } catch (_) {
      // Cloud deletion is confirmed. Never preserve app history because a
      // cache channel failed; startup repeats disk clearing before listeners.
    }
    await _store.clearAll();
    if (_auth.currentUser?.uid == user.uid) {
      await _store.setString('auth.deletedCredential', user.uid);
    }
    _current = null;
    _returning = false;
    _reauthenticatedAt = null;
    _controller.add(null);
  }

  @override
  Future<void> updateProfile(UserProfile profile) async {
    final userNow = _auth.currentUser;
    if (userNow != null && userNow.uid != profile.uid) return;
    await _persist(
      profile.copyWith(isAnonymous: userNow?.isAnonymous ?? true),
      profileEdit: true,
    );

    final user = _auth.currentUser;
    if (user == null ||
        profile.displayName.isEmpty ||
        user.displayName == profile.displayName) {
      return;
    }
    // Best effort: the device record above is the source of truth and a
    // rename must work offline. A failed push is retried on the next save.
    try {
      unawaited(
        user.updateDisplayName(profile.displayName).catchError((Object _) {}),
      );
    } on FirebaseAuthException {
      // Deliberately swallowed — see above.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _credentialGeneration++;
    recoveryState.dispose();
    studyBackup?.dispose();
    final sub = _authSub;
    if (sub != null) unawaited(sub.cancel());
    _controller.close();
  }

  Future<void> _onAuthStateChanged(User? user) async {
    if (_disposed || user?.uid != _auth.currentUser?.uid) return;
    _observeCredential();
    // A device-only guest has no Firebase credential. The SDK's initial null
    // event must not undo a completed local Skip action.
    if (user == null && _current?.isAnonymous == true) return;
    if (user == null ||
        _isDeletedCredential(user) ||
        _requiresEmailVerification(user)) {
      _current = null;
      _restorationPending = false;
      recoveryState.value = null;
      studyBackup?.disconnect();
      if (!_disposed) _controller.add(null);
      return;
    }
    await _persist(_profileFor(user));
  }

  /// Builds the device profile for [user].
  ///
  /// The *stored* record is authoritative for everything the user has edited
  /// — persona, name, daily goal, timezone, onboarding state — and Firebase
  /// contributes only the identity. Starting from a fresh [UserProfile] would
  /// silently reset the record the onboarding steps wrote, which is the exact
  /// failure `LocalAuthService._baseProfile` exists to prevent.
  ///
  /// Credential state comes from Firebase. Keeping a previously linked flag
  /// after sign-out would misrepresent a device-only session as authenticated.
  UserProfile _profileFor(
    User user, {
    String? displayName,
    String? email,
    String? providerName,
  }) {
    final stored = _store.getMap(StoreKeys.user);
    final base = stored == null
        ? UserProfile(createdAt: DateTime.now())
        : UserProfile.fromJson(stored);
    return base.copyWith(
      uid: user.uid,
      isAnonymous: user.isAnonymous,
      displayName: _displayNameFor(
        base,
        user,
        displayName: displayName,
        email: email,
        providerName: providerName,
      ),
    );
  }

  /// Fills the display name from the first source that has one: the explicit
  /// argument (a link caller), then the stored record, then the provider's own
  /// account name, then Firebase, then the email local-part. The stored record
  /// outranks both remote sources so a name the user typed is never
  /// overwritten by a provider default.
  static String _displayNameFor(
    UserProfile base,
    User user, {
    String? displayName,
    String? email,
    String? providerName,
  }) {
    final explicit = displayName?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    if (base.displayName.isNotEmpty) return base.displayName;
    final provider = providerName?.trim();
    if (provider != null && provider.isNotEmpty) return provider;
    final remote = user.displayName?.trim();
    if (remote != null && remote.isNotEmpty) return remote;
    return email == null ? '' : _nameFromEmail(email);
  }

  Future<UserProfile> _persist(
    UserProfile profile, {
    bool profileEdit = false,
  }) {
    _observeCredential();
    if (!profileEdit &&
        !profile.isAnonymous &&
        signedIn &&
        _current?.uid == profile.uid) {
      final stored = _store.getMap(StoreKeys.user);
      if (stored?['uid'] == profile.uid && stored?['isAnonymous'] == false) {
        // SDK startup/restore is hydration. Do not save provider-filled names
        // or onboarding defaults as edits before background reconciliation.
        _current = UserProfile.fromJson(stored!);
        return Future.value(_current!);
      }
    }
    final generation = _credentialGeneration;
    if (!profileEdit &&
        _profileRecoveryUid == profile.uid &&
        _profileRecovery != null) {
      return _profileRecovery!;
    }
    final next = _profileWrites
        .catchError((Object _) {})
        .then(
          (_) => _writeProfile(
            profile,
            profileEdit: profileEdit,
            generation: generation,
          ),
        );
    _profileWrites = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    if (!profileEdit) {
      _profileRecoveryUid = profile.uid;
      _profileRecovery = next;
      unawaited(
        next.then<void>(
          (_) {
            if (identical(_profileRecovery, next)) _profileRecovery = null;
          },
          onError: (Object _, StackTrace _) {
            if (identical(_profileRecovery, next)) _profileRecovery = null;
          },
        ),
      );
    }
    return next;
  }

  void _observeCredential() {
    final uid = _auth.currentUser?.uid;
    if (_credentialUid == uid) return;
    _invalidateRecovery();
    _credentialUid = uid;
  }

  void _invalidateRecovery() {
    _credentialGeneration++;
    _credentialUid = null;
    _profileRecovery = null;
    _profileRecoveryUid = null;
    // A canceled network read must not hold up the next credential session.
    // StudyBackupService separately fences its own in-flight reads/writes.
    _profileWrites = Future.value();
    _restorationPending = false;
    if (!_disposed) recoveryState.value = null;
  }

  Future<UserProfile> _writeProfile(
    UserProfile profile, {
    required bool profileEdit,
    required int generation,
  }) async {
    bool isCurrent() => !_disposed && generation == _credentialGeneration;
    void checkCurrent() {
      if (!isCurrent()) throw const AuthException(AuthFailure.cancelled);
    }

    checkCurrent();
    if (needsEmailVerification) {
      throw const AuthException(AuthFailure.emailVerificationRequired);
    }
    final credential = _auth.currentUser;
    if (_disposed ||
        (credential != null && credential.uid != profile.uid) ||
        (credential == null && !profile.isAnonymous)) {
      throw const AuthException(AuthFailure.cancelled);
    }
    profile = profile.copyWith(isAnonymous: credential?.isAnonymous ?? true);
    if (!profileEdit && credential != null) profile = _profileFor(credential);
    final backup = studyBackup;
    if (!profile.isAnonymous && backup != null) {
      final showRecovery = _current?.uid != profile.uid || _restorationPending;
      if (showRecovery) recoveryState.value = AccountRecoveryStage.connecting;
      if (_store.getMap(StoreKeys.user)?['uid'] != profile.uid) {
        _restorationPending = true;
        _current = null;
        if (!_disposed) _controller.add(null);
      }
      try {
        for (var attempt = 0; ; attempt++) {
          try {
            if (showRecovery) {
              recoveryState.value = AccountRecoveryStage.restoring;
            }
            profile = await backup.connect(profile);
            break;
          } catch (error) {
            if (!isCurrent() || _auth.currentUser?.uid != credential?.uid) {
              rethrow;
            }
            final code = error is FirebaseException ? error.code : '';
            final refreshCredential =
                attempt == 0 &&
                (code == 'permission-denied' || code == 'unauthenticated');
            final transient =
                error is TimeoutException ||
                const {
                  'unavailable',
                  'deadline-exceeded',
                  'aborted',
                  'network-request-failed',
                }.contains(code);
            if (attempt >= 2 || (!transient && !refreshCredential)) rethrow;
            if (showRecovery) {
              recoveryState.value = AccountRecoveryStage.retrying;
            }
            if (refreshCredential) await credential!.getIdToken(true);
            await Future<void>.delayed(
              Duration(milliseconds: 300 * (attempt + 1)),
            );
            if (!isCurrent() || _auth.currentUser?.uid != credential?.uid) {
              throw const AuthException(AuthFailure.cancelled);
            }
          }
        }
      } catch (error) {
        if (!isCurrent() || _auth.currentUser?.uid != credential?.uid) {
          throw const AuthException(AuthFailure.cancelled);
        }
        _restorationPending = true;
        if (!_disposed) _controller.add(null);
        final code = error is FirebaseException
            ? error.code
            : error.runtimeType.toString();
        debugPrint('[auth] Account recovery failed: $code');
        throw AuthException(AuthFailure.recoveryFailed, code);
      } finally {
        if (isCurrent()) recoveryState.value = null;
      }
    }
    if (!isCurrent() || _auth.currentUser?.uid != credential?.uid) {
      throw const AuthException(AuthFailure.cancelled);
    }
    if (_returning && !profile.isAnonymous && !profile.onboardingComplete) {
      profile = profile.copyWith(onboardingComplete: true);
    }
    await _store.prepareAchievementIdentity(profile.uid);
    checkCurrent();
    final key = 'achievements.linked.${profile.uid}';
    if (!profile.isAnonymous || _store.getBool(key) == null) {
      await _store.setBool(key, !profile.isAnonymous);
      checkCurrent();
    }
    final oldUid = _store.getMap(StoreKeys.user)?['uid'];
    if (oldUid is String && oldUid.isNotEmpty && oldUid != profile.uid) {
      await _store.setBool(StoreKeys.boardOptIn, false);
      checkCurrent();
    }
    await _store.setMap(StoreKeys.user, profile.toJson());
    if (!isCurrent() || _auth.currentUser?.uid != credential?.uid) {
      throw const AuthException(AuthFailure.cancelled);
    }
    _restorationPending = false;
    _current = profile;
    if (!_disposed) _controller.add(profile);
    return profile;
  }

  /// The same shape check the local implementation applies, kept so a
  /// malformed address fails instantly and identically offline rather than
  /// costing a round-trip.
  static void _validateEmail(String email) {
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim());
    if (!ok) throw const AuthException(AuthFailure.invalidEmail);
  }

  static String _nameFromEmail(String email) {
    final local = email.split('@').first.replaceAll(RegExp(r'[._\-]+'), ' ');
    return local
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  /// Runs a Firebase call, translating every [FirebaseAuthException] into the
  /// app's own [AuthException] so raw plugin errors never reach the UI — the
  /// screens show [AuthException.friendly] and nothing else.
  static Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on FirebaseAuthException catch (e) {
      throw _translate(e);
    }
  }

  /// The Firebase error vocabulary mapped onto [AuthFailure].
  ///
  /// `operation-not-allowed` is the provider being switched off in the Firebase
  /// console, which is a configuration state a developer hits constantly and a
  /// user can act on by using another method — so it maps to
  /// [AuthFailure.providerUnavailable] rather than the generic case. The raw
  /// [FirebaseAuthException.message] still rides along on the [AuthException]
  /// for diagnostics; [AuthException.friendly] is all the UI renders.
  ///
  /// `user-disabled` stays generic: only an administrator can undo it, so
  /// there is no action to name.
  static AuthException _translate(FirebaseAuthException e) {
    final failure = switch (e.code) {
      'invalid-email' => AuthFailure.invalidEmail,
      'weak-password' => AuthFailure.weakPassword,
      'email-already-in-use' => AuthFailure.emailInUse,
      'wrong-password' || 'invalid-credential' => AuthFailure.wrongPassword,
      'user-not-found' => AuthFailure.userNotFound,
      'network-request-failed' => AuthFailure.network,
      'too-many-requests' => AuthFailure.tooManyRequests,
      'requires-recent-login' => AuthFailure.requiresRecentLogin,
      'operation-not-allowed' => AuthFailure.providerUnavailable,
      _ => AuthFailure.unknown,
    };
    return AuthException(failure, e.message);
  }

  /// The Google plugin's error vocabulary mapped onto [AuthFailure].
  ///
  /// In this plugin generation every failure arrives as a [PlatformException]
  /// whose `code` is one of the `GoogleSignIn.kSignIn…Error` constants.
  /// `sign_in_failed` covers the configuration class — a missing or mismatched
  /// OAuth client, which has no user remedy — so it collapses into
  /// `providerUnavailable`, the one case the screen already has copy for.
  /// Anything unrecognised falls through to `unknown` rather than leaking the
  /// platform's text to the UI.
  static AuthException _translateGoogle(PlatformException e) {
    final failure = switch (e.code) {
      GoogleSignIn.kSignInCanceledError => AuthFailure.cancelled,
      GoogleSignIn.kSignInFailedError => AuthFailure.providerUnavailable,
      _ => AuthFailure.unknown,
    };
    return AuthException(failure, e.message);
  }
}
