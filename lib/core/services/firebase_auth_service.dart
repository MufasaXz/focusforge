import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';

import '../models/user.dart';
import 'auth_service.dart';
import 'local_store.dart';

/// The Firebase-backed implementation of [AuthService].
///
/// Firebase holds only the credential. The profile record — persona, name,
/// daily goal, onboarding state — stays in [LocalStore], which is the app's
/// privacy position. Optional study groups and achievement backups have separate services;
/// detailed logs stay local and the timer keeps working without a network.
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
    FirebaseFunctions? functions,
    GoogleSignIn? googleSignIn,
  }) : _auth = firebaseAuth ?? FirebaseAuth.instance,
       _firestoreOverride = firestore,
       _functionsOverride = functions,
       _googleClient = googleSignIn {
    // `authStateChanges()` is the single source of stream events: it fires
    // both for sessions started through this class and for ones it never saw
    // — a session restored on launch, a sign-out from elsewhere. Re-keying
    // every event onto the stored record before emitting is what keeps
    // listeners from ever observing a profile with a defaulted persona,
    // name or goal.
    _authSub = _auth.authStateChanges().listen((user) {
      unawaited(_onAuthStateChanged(user));
    });
  }

  final LocalStore _store;
  final FirebaseAuth _auth;
  final FirebaseFirestore? _firestoreOverride;
  final FirebaseFunctions? _functionsOverride;

  final _controller = StreamController<UserProfile?>.broadcast();
  StreamSubscription<User?>? _authSub;
  UserProfile? _current;
  bool _returning = false;
  DateTime? _reauthenticatedAt;

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
      _auth.currentUser != null && !_isDeletedCredential(_auth.currentUser!);

  bool _isDeletedCredential(User user) =>
      _store.getString('auth.deletedCredential') == user.uid;

  @override
  Stream<UserProfile?> get changes => _controller.stream;

  @override
  Future<UserProfile?> restore() async {
    final user = _auth.currentUser;
    if (user == null || _isDeletedCredential(user)) {
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

  /// Signs in anonymously, then re-keys the stored profile to the new uid.
  ///
  /// Firebase mints a fresh anonymous user on every call, so unlike the local
  /// implementation a second "Skip for now" produces a new uid. The stored
  /// record is still the base: persona, name, goal and timezone survive, and
  /// only the uid changes. Starting from a fresh [UserProfile] instead would
  /// silently reset everything the user edited during onboarding.
  @override
  Future<UserProfile> signInAnonymously() async {
    if (_auth.currentUser case final user?) {
      return _persist(_profileFor(user));
    }
    _returning = false;
    final credential = await _guard(() => _auth.signInAnonymously());
    return _persist(_profileFor(credential.user!));
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
    return _persist(_profileFor(credential.user!, email: email));
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
    return _persist(_profileFor(credential.user!, email: email));
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
    await _guard(() => _auth.signOut());
    try {
      await _googleSignIn().signOut();
    } catch (_) {
      // The Firebase session is already closed. A provider cache error must
      // not report a failed sign-out after it succeeded.
    }
    _current = null;
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
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException(AuthFailure.requiresRecentLogin);
    }
    {
      // Group rows must be removed while the credential can still authorise
      // writes. Check login age first, before changing any cloud membership.
      final recentlyConfirmed =
          _reauthenticatedAt != null &&
          DateTime.now().difference(_reauthenticatedAt!) <
              const Duration(minutes: 5);
      if (!user.isAnonymous &&
          !recentlyConfirmed &&
          (user.metadata.lastSignInTime == null ||
              DateTime.now().difference(user.metadata.lastSignInTime!) >
                  const Duration(minutes: 5))) {
        throw const AuthException(AuthFailure.requiresRecentLogin);
      }
      try {
        // Finish queued sharing writes before removing their records. The UI
        // suspends publishers for the duration of this operation.
        await (_firestoreOverride ?? FirebaseFirestore.instance)
            .waitForPendingWrites()
            .timeout(const Duration(seconds: 20));
      } on TimeoutException {
        throw const AuthException(AuthFailure.cloudSyncPending);
      } on FirebaseException catch (e) {
        throw AuthException(AuthFailure.cloudSyncPending, e.code);
      }
      try {
        // The callable uses the verified caller UID, blocks new cloud writes,
        // removes records from every device and deletes Auth last.
        await user.getIdToken(true);
        final result =
            await (_functionsOverride ??
                    FirebaseFunctions.instanceFor(region: 'us-central1'))
                .httpsCallable(
                  'deleteFocusForgeAccount',
                  options: HttpsCallableOptions(
                    timeout: const Duration(minutes: 5),
                  ),
                )
                .call<Map<String, dynamic>>();
        if (result.data['deleted'] != true) {
          throw const AuthException(AuthFailure.cleanupFailed);
        }
      } on AuthException {
        rethrow;
      } on FirebaseAuthException catch (e) {
        throw _translate(e);
      } on FirebaseFunctionsException catch (e) {
        final failure = switch (e.code) {
          'not-found' ||
          'unimplemented' ||
          'permission-denied' => AuthFailure.deletionUnavailable,
          'unauthenticated' ||
          'failed-precondition' => AuthFailure.requiresRecentLogin,
          'resource-exhausted' => AuthFailure.tooManyRequests,
          _ => AuthFailure.cleanupFailed,
        };
        // Retain a non-sensitive code for diagnostics; never surface the
        // server's raw response or misreport a missing endpoint as bad rules.
        throw AuthException(failure, e.code);
      } catch (_) {
        throw const AuthException(AuthFailure.cleanupFailed);
      }
      // Confirmation makes device erasure mandatory even if an SDK cache
      // cannot sign out. A UID-only fence prevents that stale credential from
      // restoring a deleted profile after a restart; no profile data is kept.
      await _store.setString('auth.deletedCredential', user.uid);
      try {
        await _auth.signOut();
      } catch (_) {
        // The account was deleted by the server. Continue the local erase.
      }
      try {
        await _googleSignIn().signOut();
      } catch (_) {
        // The server has confirmed deletion. A provider cache failure must
        // not leave the device's history after that success.
      }
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
    await _persist(profile);

    final user = _auth.currentUser;
    if (user == null ||
        profile.displayName.isEmpty ||
        user.displayName == profile.displayName) {
      return;
    }
    // Best effort: the device record above is the source of truth and a
    // rename must work offline. A failed push is retried on the next save.
    try {
      await user.updateDisplayName(profile.displayName);
    } on FirebaseAuthException {
      // Deliberately swallowed — see above.
    }
  }

  @override
  void dispose() {
    final sub = _authSub;
    if (sub != null) unawaited(sub.cancel());
    _controller.close();
  }

  Future<void> _onAuthStateChanged(User? user) async {
    if (user == null || _isDeletedCredential(user)) {
      _current = null;
      _controller.add(null);
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

  Future<UserProfile> _persist(UserProfile profile) async {
    await _store.prepareAchievementIdentity(profile.uid);
    final key = 'achievements.linked.${profile.uid}';
    if (!profile.isAnonymous || _store.getBool(key) == null) {
      await _store.setBool(key, !profile.isAnonymous);
    }
    final oldUid = _store.getMap(StoreKeys.user)?['uid'];
    if (oldUid is String && oldUid.isNotEmpty && oldUid != profile.uid) {
      await _store.setBool(StoreKeys.boardOptIn, false);
    }
    _current = profile;
    await _store.setMap(StoreKeys.user, profile.toJson());
    _controller.add(profile);
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
