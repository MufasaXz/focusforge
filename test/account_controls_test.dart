import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/router.dart';
import 'package:focusforge/app/bootstrap.dart';
import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/providers/social_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/services/auth_service.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/features/onboarding/auth_screen.dart';
import 'package:focusforge/features/settings/privacy_screen.dart';

class _FailingDeletion extends LocalAuthService {
  _FailingDeletion(super.store);
  int attempts = 0;
  @override
  Future<void> deleteAccount() async {
    attempts++;
    throw const AuthException(AuthFailure.network);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore store;
  late ProviderContainer container;
  late _FailingDeletion auth;
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
    auth = _FailingDeletion(store);
    await auth.updateProfile(profile);
    container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        authServiceProvider.overrideWithValue(auth),
        shieldServiceProvider.overrideWithValue(RecordingShieldService()),
      ],
    );
    container.read(userProvider.notifier).hydrate(profile);
  });
  tearDown(() {
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

  testWidgets(
    'account deletion is reachable at 320dp with large text and preserves data on failure',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await store.setList(StoreKeys.sessions, [
        {'id': 'kept'},
      ]);
      await tester.pumpWidget(wrap(const PrivacyScreen(), scale: 2));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Delete account'), 180);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(TextField),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Delete everything'),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete everything'));
      await tester.pumpAndSettle();
      expect(auth.attempts, 1);
      expect(store.getList(StoreKeys.sessions), [
        {'id': 'kept'},
      ]);
      expect(container.read(userProvider).uid, 'sam');
      expect(container.read(accountMutationProvider), isFalse);
      expect(
        find.text('No connection. Your data stays on device.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

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
    container.read(timerProvider.notifier).start();
    await resetPersistedState(container);
    expect(container.read(timerProvider).running, isFalse);
    expect(container.read(userProvider).uid, isEmpty);
    expect(container.read(boardOptInProvider), isFalse);
    expect(store.getBool(StoreKeys.boardOptIn), isNull);
  });
}
