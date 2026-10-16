import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/router.dart';
import 'package:focusforge/app/bootstrap.dart';
import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/models/focus_goal.dart';
import 'package:focusforge/core/models/study.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/goal_planner_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/providers/social_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/services/auth_service.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/features/onboarding/auth_screen.dart';
import 'package:focusforge/features/settings/privacy_screen.dart';
import 'package:focusforge/shared/widgets/app_page.dart';

/// Keeps real local authentication/storage behaviour while replacing the
/// external credential check and remote deletion response at the UI boundary.
class _AccountDeletionAuth extends LocalAuthService {
  _AccountDeletionAuth(super.store);

  bool remote = true;
  bool passwordProvider = true;
  bool rejectPassword = false;
  bool cancelGoogle = false;
  final operations = <String>[];
  final failures = <AuthFailure>[];
  Completer<void>? deletionGate;

  @override
  bool get usesRemoteCredentials => remote;
  @override
  bool get supportsPasswordReauthentication => passwordProvider;

  @override
  Future<void> reauthenticate({String? password}) async {
    operations.add(passwordProvider ? 'password:$password' : 'google');
    if (rejectPassword) {
      throw const AuthException(AuthFailure.wrongPassword);
    }
    if (cancelGoogle) throw const AuthException(AuthFailure.cancelled);
  }

  @override
  Future<void> deleteAccount() async {
    operations.add('delete');
    if (failures.isNotEmpty) throw AuthException(failures.removeAt(0));
    await deletionGate?.future;
    await super.deleteAccount();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore store;
  late ProviderContainer container;
  late _AccountDeletionAuth auth;
  GoRouter? testRouter;
  const profile = UserProfile(
    uid: 'sam',
    displayName: 'Sam Rivera',
    isAnonymous: false,
    onboardingComplete: true,
    dailyGoalMinutes: 45,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
    await store.clearAll();
    auth = _AccountDeletionAuth(store);
    await auth.updateProfile(profile);
    container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        authServiceProvider.overrideWithValue(auth),
        shieldServiceProvider.overrideWithValue(RecordingShieldService()),
      ],
    );
    container.read(userProvider.notifier).hydrate(profile);
    await store.setList(StoreKeys.sessions, [
      {'id': 'kept'},
    ]);
  });
  tearDown(() {
    testRouter?.dispose();
    testRouter = null;
    container.dispose();
    auth.dispose();
  });

  Widget wrap(Widget child, {double scale = 1}) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: child,
    ),
  );

  Widget routed({double scale = 1, bool pushed = false}) {
    testRouter = GoRouter(
      initialLocation: pushed ? '/profile/privacy' : '/privacy',
      routes: [
        GoRoute(path: '/privacy', builder: (_, _) => const PrivacyScreen()),
        GoRoute(
          path: '/profile',
          builder: (_, _) => const Scaffold(body: Text('Profile')),
          routes: [
            GoRoute(path: 'privacy', builder: (_, _) => const PrivacyScreen()),
          ],
        ),
        GoRoute(
          path: '/onboarding',
          name: AppRoutes.onboarding,
          builder: (_, _) => const Scaffold(body: Text('Welcome')),
        ),
      ],
    );
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: testRouter,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    );
  }

  Future<void> openDeletion(WidgetTester tester) async {
    expect(find.text('Delete account'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Delete account'),
      180,
      scrollable: find
          .descendant(
            of: find.byType(AppPage).last,
            matching: find.byType(Scrollable),
          )
          .last,
    );
    await tester.ensureVisible(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
  }

  Future<void> confirmDeletion(WidgetTester tester) async {
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Delete account'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
    await tester.pumpAndSettle();
  }

  Future<void> submitPassword(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), 'secure password');
    await tester.pump();
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Verify and delete'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Verify and delete'));
    await tester.pump();
  }

  testWidgets('cancelling confirmation keeps all records and credentials', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const PrivacyScreen()));
    await openDeletion(tester);
    expect(
      find.text(
        'This action is irreversible and will delete your profile, achievements, and all progress.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(auth.operations, isEmpty);
    expect(auth.signedIn, isTrue);
    expect(store.getList(StoreKeys.sessions), [
      {'id': 'kept'},
    ]);
    expect(container.read(accountMutationProvider), isFalse);
  });

  testWidgets('cancelling password verification never starts deletion', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const PrivacyScreen()));
    await openDeletion(tester);
    await confirmDeletion(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(auth.operations, isEmpty);
    expect(store.getList(StoreKeys.sessions), [
      {'id': 'kept'},
    ]);
    expect(container.read(accountMutationProvider), isFalse);
  });

  testWidgets('password verification precedes deletion and resets live state', (
    tester,
  ) async {
    await container.read(boardOptInProvider.notifier).set(true);
    container.read(timerProvider.notifier).start();
    await store.setMap('achievements.accounts', {
      'sam': {'first-focus': 1234},
    });
    await tester.pumpWidget(routed());
    await openDeletion(tester);
    await confirmDeletion(tester);
    final password = tester.widget<TextField>(find.byType(TextField));
    expect(password.obscureText, isTrue);
    expect(password.enableSuggestions, isFalse);
    expect(password.autocorrect, isFalse);
    await submitPassword(tester);
    await tester.pumpAndSettle();
    expect(auth.operations, ['password:secure password', 'delete']);
    expect(auth.signedIn, isFalse);
    expect(store.getList(StoreKeys.sessions), isEmpty);
    expect(store.getMap('achievements.accounts'), isNull);
    expect(container.read(userProvider).uid, isEmpty);
    expect(container.read(timerProvider).running, isFalse);
    expect(container.read(boardOptInProvider), isFalse);
    expect(container.read(accountMutationProvider), isFalse);
    expect(testRouter!.routeInformationProvider.value.uri.path, '/onboarding');
    expect(find.text('Welcome'), findsOneWidget);
  });

  testWidgets('incorrect password keeps history and permits a new attempt', (
    tester,
  ) async {
    auth.rejectPassword = true;
    await tester.pumpWidget(wrap(const PrivacyScreen()));
    await openDeletion(tester);
    await confirmDeletion(tester);
    await submitPassword(tester);
    await tester.pumpAndSettle();
    expect(find.text('Incorrect password. Try again.'), findsOneWidget);
    expect(auth.operations, ['password:secure password']);
    expect(store.getList(StoreKeys.sessions), [
      {'id': 'kept'},
    ]);
    expect(container.read(userProvider).uid, 'sam');
    expect(container.read(accountMutationProvider), isFalse);
    await openDeletion(tester);
    expect(find.text('Delete your account?'), findsOneWidget);
  });

  testWidgets('Google account rechecks ownership before cleanup', (
    tester,
  ) async {
    auth.passwordProvider = false;
    await tester.pumpWidget(routed());
    await openDeletion(tester);
    await confirmDeletion(tester);
    await tester.pumpAndSettle();
    expect(auth.operations, ['google', 'delete']);
    expect(find.byType(TextField), findsNothing);
    expect(testRouter!.routeInformationProvider.value.uri.path, '/onboarding');
  });

  testWidgets('Google cancellation leaves account and progress intact', (
    tester,
  ) async {
    auth.passwordProvider = false;
    auth.cancelGoogle = true;
    await tester.pumpWidget(wrap(const PrivacyScreen()));
    await openDeletion(tester);
    await confirmDeletion(tester);
    await tester.pumpAndSettle();
    expect(auth.operations, ['google']);
    expect(auth.signedIn, isTrue);
    expect(store.getList(StoreKeys.sessions), [
      {'id': 'kept'},
    ]);
    expect(container.read(accountMutationProvider), isFalse);
  });

  testWidgets('cleanup failure preserves history and allows deletion retry', (
    tester,
  ) async {
    auth.passwordProvider = false;
    auth.failures.add(AuthFailure.cleanupFailed);
    await tester.pumpWidget(routed());
    await openDeletion(tester);
    await confirmDeletion(tester);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('some cloud records may already be removed'),
      findsOneWidget,
    );
    expect(store.getList(StoreKeys.sessions), [
      {'id': 'kept'},
    ]);
    expect(container.read(userProvider).uid, 'sam');
    expect(container.read(accountMutationProvider), isFalse);
    await openDeletion(tester);
    await confirmDeletion(tester);
    await tester.pumpAndSettle();
    expect(auth.operations, ['google', 'delete', 'google', 'delete']);
    expect(find.text('Welcome'), findsOneWidget);
  });

  testWidgets('expired authentication triggers one fresh verification retry', (
    tester,
  ) async {
    auth.passwordProvider = false;
    auth.failures.addAll([
      AuthFailure.requiresRecentLogin,
      AuthFailure.requiresRecentLogin,
    ]);
    await tester.pumpWidget(wrap(const PrivacyScreen()));
    await openDeletion(tester);
    await confirmDeletion(tester);
    await tester.pumpAndSettle();
    expect(auth.operations, ['google', 'delete', 'google', 'delete']);
    expect(auth.signedIn, isTrue);
    expect(store.getList(StoreKeys.sessions), [
      {'id': 'kept'},
    ]);
    expect(container.read(accountMutationProvider), isFalse);
  });

  testWidgets('expired password verification opens a new password prompt', (
    tester,
  ) async {
    auth.failures.add(AuthFailure.requiresRecentLogin);
    await tester.pumpWidget(routed());
    await openDeletion(tester);
    await confirmDeletion(tester);
    await submitPassword(tester);
    await tester.pumpAndSettle();
    expect(auth.operations, ['password:secure password', 'delete']);
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(store.getList(StoreKeys.sessions), [
      {'id': 'kept'},
    ]);
    await submitPassword(tester);
    await tester.pumpAndSettle();
    expect(auth.operations, [
      'password:secure password',
      'delete',
      'password:secure password',
      'delete',
    ]);
    expect(find.text('Welcome'), findsOneWidget);
  });

  testWidgets('cancelling fresh verification explains partial cloud deletion', (
    tester,
  ) async {
    auth.failures.add(AuthFailure.requiresRecentLogin);
    await tester.pumpWidget(wrap(const PrivacyScreen()));
    await openDeletion(tester);
    await confirmDeletion(tester);
    await submitPassword(tester);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('some cloud records may already be removed'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Deletion paused.'), findsOneWidget);
    expect(auth.operations, ['password:secure password', 'delete']);
    expect(auth.signedIn, isTrue);
    expect(store.getList(StoreKeys.sessions), [
      {'id': 'kept'},
    ]);
    expect(container.read(accountMutationProvider), isFalse);
  });

  testWidgets('deletion loading blocks navigation and other data mutations', (
    tester,
  ) async {
    auth.passwordProvider = false;
    auth.deletionGate = Completer<void>();
    await tester.pumpWidget(routed(pushed: true));
    await openDeletion(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Deleting your account…'), findsOneWidget);
    expect(container.read(accountMutationProvider), isTrue);
    expect(find.byTooltip('Back').hitTestable(), findsNothing);
    expect(
      find.widgetWithText(ListTile, 'Sign out').hitTestable(),
      findsNothing,
    );
    await tester.pump();
    expect(
      testRouter!.routeInformationProvider.value.uri.path,
      '/profile/privacy',
    );
    final signOut = tester.widget<ListTile>(
      find.ancestor(of: find.text('Sign out'), matching: find.byType(ListTile)),
    );
    expect(signOut.onTap, isNull);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(
      testRouter!.routeInformationProvider.value.uri.path,
      '/profile/privacy',
    );
    auth.deletionGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Welcome'), findsOneWidget);
  });

  testWidgets('local-only erase needs no external credential check', (
    tester,
  ) async {
    auth.remote = false;
    await tester.pumpWidget(routed());
    await openDeletion(tester);
    await confirmDeletion(tester);
    await tester.pumpAndSettle();
    expect(auth.operations, ['delete']);
    expect(find.text('Welcome'), findsOneWidget);
  });

  testWidgets(
    'badge publishers suspend during cleanup and resume after failure',
    (tester) async {
      auth.passwordProvider = false;
      auth.deletionGate = Completer<void>();
      container.read(achievementsProvider.notifier).hydrate({});
      await tester.pumpWidget(routed());
      await openDeletion(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      container.read(sessionsProvider.notifier).hydrate([
        FocusSession(
          id: 'completed-during-cleanup',
          subjectId: 'math',
          startedAt: DateTime(2026, 1, 1, 12),
          minutes: 25,
          completed: true,
          ownerUid: 'sam',
        ).toJson(),
      ]);
      await container.read(achievementsProvider.notifier).refresh();
      expect(
        container
            .read(achievementsProvider)
            .singleWhere((badge) => badge.id == 'first_focus')
            .unlocked,
        isFalse,
      );
      auth.deletionGate!.completeError(
        const AuthException(AuthFailure.cleanupFailed),
      );
      await tester.pumpAndSettle();
      await container.read(achievementsProvider.notifier).flushLocal();
      expect(
        container
            .read(achievementsProvider)
            .singleWhere((badge) => badge.id == 'first_focus')
            .unlocked,
        isTrue,
      );
      expect(container.read(accountMutationProvider), isFalse);
      expect(
        store.getMap(StoreKeys.achievementAccounts)?['sam'],
        contains('first_focus'),
      );
    },
  );

  testWidgets('deletion dialogs remain usable on small screens at large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(const PrivacyScreen(), scale: 2));
    await openDeletion(tester);
    await confirmDeletion(tester);
    expect(tester.takeException(), isNull);
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.obscureText, isTrue);
    await tester.ensureVisible(find.widgetWithText(TextButton, 'Cancel'));
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(auth.operations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('real app router returns deleted users to the welcome flow', (
    tester,
  ) async {
    auth.passwordProvider = false;
    auth.deletionGate = Completer<void>();
    final router = container.read(routerProvider);
    router.goNamed(AppRoutes.privacy);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openDeletion(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Home').hitTestable(), findsNothing);
    expect(find.text('Shield').hitTestable(), findsNothing);
    expect(find.text('Focus').hitTestable(), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(router.routeInformationProvider.value.uri.path, '/profile/privacy');
    auth.deletionGate!.complete();
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/onboarding');
    expect(container.read(userProvider).onboardingComplete, isFalse);
    expect(store.getList(StoreKeys.sessions), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'completed profiles can open sign-in without repeating onboarding',
    (tester) async {
      final router = container.read(routerProvider);
      router.goNamed(AppRoutes.auth);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AuthScreen), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/auth');
      expect(container.read(userProvider).dailyGoalMinutes, 45);
    },
  );

  test('deletion reset clears live timer and sharing consent', () async {
    await container.read(boardOptInProvider.notifier).set(true);
    await container
        .read(focusGoalPlannerProvider.notifier)
        .save(
          FocusGoalPlan(
            scope: FocusGoalScope.day,
            date: DateTime.now(),
            totalMinutes: 480,
            subjectMinutes: const {'math': 480},
          ),
        );
    expect(container.read(activeFocusGoalProvider), isNotNull);
    container.read(timerProvider.notifier).start();
    await store.setString('auth.deletedCredential', 'stale-deleted-uid');
    await resetPersistedState(container);
    expect(store.getString('auth.deletedCredential'), 'stale-deleted-uid');
    expect(container.read(timerProvider).running, isFalse);
    expect(container.read(userProvider).uid, isEmpty);
    expect(container.read(boardOptInProvider), isFalse);
    expect(store.getBool(StoreKeys.boardOptIn), isNull);
    expect(container.read(activeFocusGoalProvider), isNull);
    expect(container.read(focusGoalPlannerProvider).week, isNull);
    expect(store.getMap(FocusGoalPlannerNotifier.storageKey), isNull);
  });
}
