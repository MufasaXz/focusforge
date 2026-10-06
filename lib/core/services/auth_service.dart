import 'dart:async';

import '../models/user.dart';
import 'local_store.dart';

/// What went wrong, in a form the UI can act on without string-matching.
enum AuthFailure {
  invalidEmail,
  weakPassword,
  emailInUse,
  wrongPassword,
  userNotFound,
  cancelled,
  network,
  tooManyRequests,
  requiresRecentLogin,
  providerUnavailable,
  unknown,
}

class AuthException implements Exception {
  const AuthException(this.failure, [this.message]);

  final AuthFailure failure;

  /// The backend's own error text, for diagnostics only — [friendly] never
  /// renders it, because plugin copy is not app copy.
  final String? message;

  String get friendly => switch (failure) {
    AuthFailure.invalidEmail => 'That email address does not look right.',
    AuthFailure.weakPassword => 'Use at least 8 characters.',
    AuthFailure.emailInUse => 'An account already exists for that email.',
    AuthFailure.wrongPassword => 'Incorrect password. Try again.',
    AuthFailure.userNotFound => 'No account found for that email.',
    AuthFailure.cancelled => 'Sign-in was cancelled.',
    AuthFailure.network => 'No connection. Your data stays on device.',
    AuthFailure.tooManyRequests =>
      'Too many attempts. Wait a few minutes and try again.',
    AuthFailure.requiresRecentLogin =>
      'For security, sign out and back in, then retry.',
    AuthFailure.providerUnavailable =>
      'That sign-in method is not connected yet.',
    AuthFailure.unknown => 'Something went wrong.',
  };

  @override
  String toString() => 'AuthException($failure): $message';
}

/// Account handling — the seam every screen talks to.
///
/// The surface is deliberately shaped like `firebase_auth` — a `changes`
/// stream, an anonymous-first flow, and a `linkWith…` upgrade path — so the
/// backend behind it is an implementation detail. `bootstrap()` picks one
/// before the first frame: the Firebase-backed service when
/// `Firebase.initializeApp()` succeeds, [LocalAuthService] when it does not
/// (offline, web, or a build with no Firebase project).
///
/// Whichever backend runs, the profile record lives in [LocalStore]. Only the
/// credential is remote; how the app is used never leaves the device.
abstract class AuthService {
  /// The signed-in profile, or null while no session has been established.
  UserProfile? get current;

  /// True once a session is held.
  bool get signedIn;

  /// Emits on every sign-in, sign-out and profile edit.
  Stream<UserProfile?> get changes;

  /// The provider ids [linkAccount] can honour on this backend.
  ///
  /// A screen must render a sign-in option only when its id is in this set:
  /// a backend with no OAuth client registered reports the id as absent
  /// rather than accepting a tap it cannot fulfil.
  Set<String> get supportedProviders;

  /// Reads the persisted session.
  Future<UserProfile?> restore();

  /// Starts an anonymous session. The stored profile is the base, so a
  /// second skip does not mint a second identity over the user's edits.
  Future<UserProfile> signInAnonymously();

  /// Signs in with an email credential, keeping the stored profile as the
  /// base so an anonymous session only gains a credential.
  Future<UserProfile> signInWithEmail(String email, String password);

  /// Creates an email account, then applies the same
  /// fill-only-what-is-missing profile merge as [signInWithEmail].
  Future<UserProfile> signUpWithEmail(String email, String password);

  /// Upgrades the current session in place. The uid is preserved so nothing
  /// the user already did is orphaned.
  Future<UserProfile> linkAccount({
    required String provider,
    String? displayName,
    String? email,
  });

  /// Sends a password-reset mail to [email].
  Future<void> sendPasswordReset(String email);

  /// Ends the session. The profile record stays on the device.
  Future<void> signOut();

  /// Deletes the credential and wipes every local record.
  Future<void> deleteAccount();

  /// Persists [profile]; the record on the device is the source of truth.
  Future<void> updateProfile(UserProfile profile);

  /// Releases the [changes] stream.
  void dispose();
}

/// The on-device implementation of [AuthService].
///
/// "Accounts" are rows in [LocalStore]: nothing leaves the device, which is
/// also the app's stated privacy position for anonymous users. This is what
/// `bootstrap()` falls back to whenever Firebase cannot initialise — offline,
/// on web, or in a build with no Firebase project — and its surface is
/// deliberately shaped like `firebase_auth` so the two implementations are
/// interchangeable.
class LocalAuthService extends AuthService {
  LocalAuthService(this._store);

  final LocalStore _store;

  final _controller = StreamController<UserProfile?>.broadcast();
  UserProfile? _current;

  @override
  UserProfile? get current => _current;

  @override
  bool get signedIn => _current != null;

  /// Emits on every sign-in, sign-out and profile edit.
  @override
  Stream<UserProfile?> get changes => _controller.stream;

  /// Every id the UI knows. The local backend mints a record for all of them,
  /// so no sign-in option is ever disabled.
  ///
  /// Apple is deliberately absent: the app no longer offers it, and a provider
  /// listed here but not on any screen is a row waiting to be re-added by
  /// accident.
  @override
  Set<String> get supportedProviders => const {'google', 'email', 'local'};

  /// Reads the persisted session. Called once during bootstrap.
  @override
  Future<UserProfile?> restore() async {
    final json = _store.getMap(StoreKeys.user);
    _current = json == null ? null : UserProfile.fromJson(json);
    return _current;
  }

  Future<UserProfile> _persist(UserProfile profile) async {
    _current = profile;
    await _store.setMap(StoreKeys.user, profile.toJson());
    _controller.add(profile);
    return profile;
  }

  /// The "Skip for now" path. Everything works except study groups and the
  /// leaderboard, and the account can be upgraded later without losing data.
  ///
  /// With a profile already stored this returns it unchanged rather than
  /// minting a second identity: the user may have edited their persona, name
  /// and goal since the first skip, and a fresh uid would silently orphan all
  /// of it.
  @override
  Future<UserProfile> signInAnonymously() async =>
      _persist(await _baseProfile());

  /// Signs in — or, since the local build keeps no account registry, upgrades
  /// whatever profile is on the device. The stored record is the base either
  /// way, so an anonymous session keeps everything the user chose and only
  /// gains a credential.
  @override
  Future<UserProfile> signInWithEmail(String email, String password) async {
    _validateEmail(email);
    if (password.isEmpty) {
      throw const AuthException(AuthFailure.wrongPassword);
    }
    return _persist(_withCredential(await _baseProfile(), email: email));
  }

  /// Same base and same fill-only-what-is-missing rule as [signInWithEmail]:
  /// until a real backend exists, "create" and "sign in" differ only in
  /// password validation, and neither may reset the profile the user built.
  @override
  Future<UserProfile> signUpWithEmail(String email, String password) async {
    _validateEmail(email);
    if (password.length < 8) {
      throw const AuthException(AuthFailure.weakPassword);
    }
    return _persist(_withCredential(await _baseProfile(), email: email));
  }

  /// Upgrades the current session in place. The stored profile is the base and
  /// the uid is preserved so nothing the user already did is orphaned — the
  /// same guarantee Firebase's `linkWithCredential` gives. [provider] is part
  /// of the firebase-shaped surface; the local build has none to record.
  @override
  Future<UserProfile> linkAccount({
    required String provider,
    String? displayName,
    String? email,
  }) async {
    final base = await _baseProfile();
    return _persist(
      _withCredential(base, displayName: displayName, email: email),
    );
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    _validateEmail(email);
    // No mail transport in the local build; the screen reports success either
    // way so the flow is exercisable end to end.
  }

  @override
  Future<void> signOut() async {
    _current = null;
    _controller.add(null);
  }

  @override
  Future<void> deleteAccount() async {
    await _store.clearAll();
    _current = null;
    _controller.add(null);
  }

  @override
  Future<void> updateProfile(UserProfile profile) => _persist(profile);

  /// The record every credential operation starts from.
  ///
  /// The *stored* profile is authoritative, not the in-memory [current] cache:
  /// the onboarding steps after the auth screen edit the profile through
  /// `UserNotifier`, which writes the store directly and never tells this
  /// service. Starting a credential write from anything else — a fresh
  /// [UserProfile] in particular — makes it a whole-record copy of pre-edit
  /// defaults, silently resetting persona, name and daily goal.
  ///
  /// Only a genuinely empty store mints an identity, so a fresh install still
  /// produces a sane anonymous default.
  Future<UserProfile> _baseProfile() async {
    final stored = _store.getMap(StoreKeys.user);
    if (stored != null) return UserProfile.fromJson(stored);
    return UserProfile(
      uid: 'local-${DateTime.now().microsecondsSinceEpoch}',
      isAnonymous: true,
      createdAt: DateTime.now(),
    );
  }

  /// Flips [base] to a credential-backed account, filling only what is unset.
  ///
  /// `isAnonymous` flips so the study-groups gate opens, while the uid and
  /// every field the user has already set are inherited untouched. The display
  /// name falls back to [email] only when neither the caller nor the stored
  /// profile supplies one.
  static UserProfile _withCredential(
    UserProfile base, {
    String? displayName,
    String? email,
  }) {
    final explicit = displayName?.trim();
    final name = explicit != null && explicit.isNotEmpty
        ? explicit
        : base.displayName.isNotEmpty
        ? base.displayName
        : (email == null ? '' : _nameFromEmail(email));
    return base.copyWith(isAnonymous: false, displayName: name);
  }

  void _validateEmail(String email) {
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

  @override
  void dispose() => _controller.close();
}
