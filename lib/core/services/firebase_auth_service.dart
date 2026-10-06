import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import '../models/user.dart';
import 'auth_service.dart';
import 'local_store.dart';

/// The Firebase-backed implementation of [AuthService].
///
/// Firebase holds only the credential. The profile record — persona, name,
/// daily goal, onboarding state — stays in [LocalStore], which is the app's
/// privacy position: nothing about how the app is used is uploaded, and the
/// rest of the app keeps working with no network.
///
/// Constructed only after `Firebase.initializeApp()` has succeeded; see
/// `bootstrap()`, which falls back to [LocalAuthService] otherwise.
class FirebaseAuthService extends AuthService {
  FirebaseAuthService(this._store) {
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
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final _controller = StreamController<UserProfile?>.broadcast();
  StreamSubscription<User?>? _authSub;
  UserProfile? _current;

  @override
  UserProfile? get current => _current;

  @override
  bool get signedIn => _current != null;

  @override
  Stream<UserProfile?> get changes => _controller.stream;

  @override
  Future<UserProfile?> restore() async {
    final user = _auth.currentUser;
    if (user == null) {
      _current = null;
      return null;
    }
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
    return _persist(_profileFor(credential.user!, email: email));
  }

  /// Google and Apple need an OAuth client the Firebase project does not have
  /// registered yet; email and the device-local upgrade are what this backend
  /// can actually honour today.
  @override
  Set<String> get supportedProviders => const {'email', 'local'};

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
  /// rather than silently upgraded on the device.
  @override
  Future<UserProfile> linkAccount({
    required String provider,
    String? displayName,
    String? email,
  }) async {
    if (!supportedProviders.contains(provider)) {
      throw const AuthException(AuthFailure.providerUnavailable);
    }
    final user =
        _auth.currentUser ??
        (await _guard(() => _auth.signInAnonymously())).user!;
    return _persist(
      _profileFor(user, displayName: displayName, email: email)
          .copyWith(isAnonymous: false),
    );
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    _validateEmail(email);
    await _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));
  }

  @override
  Future<void> signOut() async {
    await _guard(() => _auth.signOut());
    _current = null;
    _controller.add(null);
  }

  @override
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user != null) {
      // Delete the credential first. If Firebase wants a fresh login
      // (`requires-recent-login`), the local record must survive so the user
      // can try again instead of losing their data to a half-completed
      // deletion — and the failure surfaces as an [AuthException], never as a
      // raw Firebase error.
      await _guard(() => user.delete());
    }
    await _store.clearAll();
    _current = null;
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
    if (user == null) {
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
  /// `isAnonymous` is monotonic: it clears when Firebase reports a
  /// credential-backed user, and otherwise inherits the stored flag. That way
  /// a link performed on the device cannot be undone by a later anonymous
  /// session, which would silently re-lock study groups.
  UserProfile _profileFor(
    User user, {
    String? displayName,
    String? email,
  }) {
    final stored = _store.getMap(StoreKeys.user);
    final base = stored == null
        ? UserProfile(createdAt: DateTime.now())
        : UserProfile.fromJson(stored);
    return base.copyWith(
      uid: user.uid,
      isAnonymous: base.isAnonymous && user.isAnonymous,
      displayName: _displayNameFor(
        base,
        user,
        displayName: displayName,
        email: email,
      ),
    );
  }

  /// Fills the display name from the first source that has one: the explicit
  /// argument (a link caller), then the stored record, then Firebase, then the
  /// email local-part. The stored record outranks Firebase so a name the user
  /// typed is never overwritten by a provider default.
  static String _displayNameFor(
    UserProfile base,
    User user, {
    String? displayName,
    String? email,
  }) {
    final explicit = displayName?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    if (base.displayName.isNotEmpty) return base.displayName;
    final remote = user.displayName?.trim();
    if (remote != null && remote.isNotEmpty) return remote;
    return email == null ? '' : _nameFromEmail(email);
  }

  Future<UserProfile> _persist(UserProfile profile) async {
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
  /// `user-disabled` and `operation-not-allowed` share the generic case: a
  /// disabled account and a provider the console never enabled have no user
  /// remedy, so the plugin's text is no more useful than fixed copy. The raw
  /// [FirebaseAuthException.message] still rides along on the [AuthException]
  /// for diagnostics; [AuthException.friendly] is all the UI renders.
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
      'user-disabled' || 'operation-not-allowed' => AuthFailure.unknown,
      _ => AuthFailure.unknown,
    };
    return AuthException(failure, e.message);
  }
}
