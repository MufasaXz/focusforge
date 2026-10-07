// The link-account flow on the profile tab.
//
// WHAT INVARIANT: linking is a sign-in. The card opens a provider choice, the
// chosen provider is the one that gets called, and the account only stops
// being anonymous once a credential has actually been presented.
//
// WHY IT MATTERS: the card used to call `linkAccount(provider: 'local')` — a
// provider with no credential behind it — and report "Account linked" on the
// spot. The profile flipped to linked without anyone signing in, which left
// the study-groups and leaderboard gates open against an account that did not
// exist. Nothing else in the suite reaches this card, so the regression had
// nowhere to fail.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/providers/usage_providers.dart';
import 'package:focusforge/core/services/auth_service.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/features/profile/profile_screen.dart';

/// The real local backend with the link call recorded.
///
/// The provider id is the whole point — the card used to link `'local'`, which
/// has no credential to mint — and the local backend forgets which id it was
/// handed as soon as it returns, so the call is captured on the way through
/// rather than inferred from the result.
class _RecordingAuth extends AuthService {
  _RecordingAuth(this._inner);

  final LocalAuthService _inner;

  /// Every provider id [linkAccount] was asked for, in order.
  final calls = <String>[];

  @override
  UserProfile? get current => _inner.current;

  @override
  bool get signedIn => _inner.signedIn;

  @override
  Stream<UserProfile?> get changes => _inner.changes;

  @override
  Set<String> get supportedProviders => _inner.supportedProviders;

  @override
  Future<UserProfile?> restore() => _inner.restore();

  @override
  Future<UserProfile> signInAnonymously() => _inner.signInAnonymously();

  @override
  Future<UserProfile> signInWithEmail(String email, String password) =>
      _inner.signInWithEmail(email, password);

  @override
  Future<UserProfile> signUpWithEmail(String email, String password) =>
      _inner.signUpWithEmail(email, password);

  @override
  Future<UserProfile> linkAccount({
    required String provider,
    String? displayName,
    String? email,
  }) {
    calls.add(provider);
    return _inner.linkAccount(
      provider: provider,
      displayName: displayName,
      email: email,
    );
  }

  @override
  Future<void> sendPasswordReset(String email) =>
      _inner.sendPasswordReset(email);

  @override
  Future<void> signOut() => _inner.signOut();

  @override
  Future<void> deleteAccount() => _inner.deleteAccount();

  @override
  Future<void> updateProfile(UserProfile profile) =>
      _inner.updateProfile(profile);

  @override
  void dispose() => _inner.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStore store;
  late _RecordingAuth auth;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
  });

  setUp(() async {
    await store.clearAll();
    auth = _RecordingAuth(LocalAuthService(store));
    addTearDown(auth.dispose);
  });

  ProviderContainer freshContainer() {
    final engine = RecordingShieldService();
    addTearDown(engine.dispose);

    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        authServiceProvider.overrideWithValue(auth),
        shieldServiceProvider.overrideWithValue(engine),
        installedAppsProvider.overrideWith((ref) async => const []),
        appUsageTodayProvider.overrideWith((ref) async => const {}),
        usageAccessProvider.overrideWith((ref) async => false),
        shieldEnabledProvider.overrideWith((ref) async => false),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// The profile tab, with the router it reads its rows against.
  ///
  /// A tall window because the card sits in a scroll view and a widget below
  /// the fold is never built — an assertion about it would fail for a reason
  /// that has nothing to do with linking.
  Widget harness(ProviderContainer container) {
    final router = GoRouter(
      initialLocation: '/me',
      routes: [
        // The tab is a branch body inside the shell's Scaffold, and the
        // confirmation is a snackbar — so the Scaffold is part of the harness
        // rather than scaffolding around the subject.
        GoRoute(
          path: '/me',
          builder: (context, state) => const Scaffold(body: ProfileScreen()),
        ),
      ],
    );
    addTearDown(router.dispose);
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
      ),
    );
  }

  void useTallPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Pumps past the stagger entrance.
  ///
  /// [Stagger] schedules its entrance with a bare `Future.delayed`, which
  /// schedules no frame — `pumpAndSettle` alone returns with the timer still
  /// pending and the framework then fails the test on teardown.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  bool storedIsAnonymous() {
    final json = store.getMap(StoreKeys.user);
    if (json == null) return true;
    return UserProfile.fromJson(json).isAnonymous;
  }

  testWidgets('the link button asks who to sign in as, and claims nothing', (
    tester,
  ) async {
    useTallPhone(tester);
    await tester.pumpWidget(harness(freshContainer()));
    await settle(tester);

    expect(
      find.text('Local account'),
      findsOneWidget,
      reason: 'a cold install is device-only',
    );

    await tester.tap(find.text('Link an account'));
    await settle(tester);

    expect(
      find.text('Continue with Google'),
      findsNothing,
      reason: 'the on-device backend has no OAuth client, so the row would be '
          'an inert control — this branch does not render it at all',
    );
    expect(find.text('Continue with Email'), findsOneWidget);
    expect(
      storedIsAnonymous(),
      isTrue,
      reason: 'opening the choice is not a sign-in',
    );
    expect(
      auth.calls,
      isEmpty,
      reason: 'no credential has been presented yet',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the email path opens the form, and the form is the sign-in', (
    tester,
  ) async {
    final container = freshContainer();
    useTallPhone(tester);
    await tester.pumpWidget(harness(container));
    await settle(tester);

    await tester.tap(find.text('Link an account'));
    await settle(tester);
    await tester.tap(find.text('Continue with Email'));
    await settle(tester);

    expect(find.text('Sign in with email'), findsOneWidget);
    expect(
      storedIsAnonymous(),
      isTrue,
      reason: 'an opened form is not a credential',
    );

    await tester.enterText(find.byType(TextField).first, 'sam@example.com');
    await tester.enterText(find.byType(TextField).last, 'correct-horse');
    await settle(tester);
    await tester.tap(find.text('Sign in'));
    await settle(tester);

    expect(container.read(userProvider).isAnonymous, isFalse);
    expect(storedIsAnonymous(), isFalse);
    expect(
      find.text('Local account'),
      findsNothing,
      reason: 'the card goes away once there is a credential behind it',
    );
    expect(
      auth.calls,
      isEmpty,
      reason: 'email is a credential of its own, not a provider link',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('backing out of the sheet leaves the account alone', (
    tester,
  ) async {
    final container = freshContainer();
    useTallPhone(tester);
    await tester.pumpWidget(harness(container));
    await settle(tester);

    await tester.tap(find.text('Link an account'));
    await settle(tester);

    // The barrier above the sheet: a tap on it dismisses without choosing.
    await tester.tapAt(const Offset(210, 40));
    await settle(tester);

    expect(container.read(userProvider).isAnonymous, isTrue);
    expect(storedIsAnonymous(), isTrue);
    expect(auth.calls, isEmpty);
    expect(find.text('Local account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
