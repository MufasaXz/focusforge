// The device question and the parent's navigation bar.
//
// WHAT INVARIANT: "How will you use this phone?" is a parent's question. A student's
// setup goes from the persona straight to the profile, forward and back, and
// never inherits a parent answer from an earlier pass through the flow. And a
// parent's app is three destinations — Home, Shield, You — while everyone
// else keeps the four.
//
// WHY IT MATTERS: the page exists to decide which half of Parent control
// opens first, and that is only a real question for a parent. A student who
// sees it is being asked to answer something that cannot apply to them, and
// answering it wrongly marks their own phone as a parent's — which moves a
// tab and changes what the app asks them for. Neither mistake is visible in
// the code that causes it; both are one tap away in the flow.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/app.dart';
import 'package:focusforge/app/router.dart';
import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/providers/usage_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/features/onboarding/onboarding_flow.dart';
import 'package:focusforge/features/onboarding/complete_step.dart';
import 'package:focusforge/features/onboarding/subjects_step.dart';
import 'package:focusforge/features/onboarding/permissions_step.dart';
import 'package:focusforge/features/onboarding/profile_step.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStore store;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
  });

  setUp(() async {
    await store.clearAll();
  });

  ProviderContainer freshContainer() {
    final container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// The splash holds for 1.1 s and loops a ticker, so nothing here can use
  /// `pumpAndSettle` while it is on screen — the frames never stop.
  Future<void> pastSplash(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> tapAndSettle(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
  }

  /// Lets every [Stagger] timer that is still pending fire before the test
  /// ends — the framework fails a test with a live timer in the tree.
  Future<void> drain(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
  }

  /// Walks from the splash to the persona step through the auth screen's
  /// "skip" path, which is what a device-only account takes.
  Future<void> reachPersona(WidgetTester tester) async {
    await pastSplash(tester);
    await tapAndSettle(tester, 'Skip for now');
    expect(find.text('I am a...'), findsOneWidget);
  }

  testWidgets('a student never sees the device question', (tester) async {
    final container = freshContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const OnboardingFlow(),
        ),
      ),
    );

    await reachPersona(tester);
    await tapAndSettle(tester, 'Student');
    await tapAndSettle(tester, 'Continue');

    expect(find.text('How will you use this phone?'), findsNothing);
    expect(find.text('Set up your profile'), findsOneWidget);
    expect(container.read(userProvider).isGuardian, isFalse);

    // Back is the same journey in reverse: a student must not be walked into
    // the page the flow chose not to ask them.
    await tester.tap(find.byTooltip('Back'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('How will you use this phone?'), findsNothing);
    expect(find.text('I am a...'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('a parent is asked whose device this is', (tester) async {
    final container = freshContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const OnboardingFlow(),
        ),
      ),
    );

    await reachPersona(tester);
    await tapAndSettle(tester, 'Parent');
    await tapAndSettle(tester, 'Continue');

    // The page is the question; the answer is what Continue on it records.
    expect(find.text('How will you use this phone?'), findsOneWidget);
    expect(container.read(userProvider).isGuardian, isFalse);

    await tapAndSettle(tester, 'Continue');
    expect(container.read(userProvider).isGuardian, isTrue);
    expect(find.text('Set up your profile'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('a profile draft survives going back to the persona', (
    tester,
  ) async {
    final container = freshContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const OnboardingFlow(),
        ),
      ),
    );
    await reachPersona(tester);
    await tapAndSettle(tester, 'Continue');
    final name = find.descendant(
      of: find.byType(ProfileStep),
      matching: find.byType(TextField),
    );
    await tester.enterText(name, 'Aarav');
    await tester.tap(find.byTooltip('Back'));
    await drain(tester);
    await tapAndSettle(tester, 'Continue');
    expect(tester.widget<TextField>(name).controller!.text, 'Aarav');
    await drain(tester);
  });

  testWidgets('guardian setup goes from profile to pairing review', (
    tester,
  ) async {
    final container = freshContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const OnboardingFlow(),
        ),
      ),
    );
    await reachPersona(tester);
    await tapAndSettle(tester, 'Parent');
    await tapAndSettle(tester, 'Continue');
    await tapAndSettle(tester, 'Continue');
    expect(container.read(userProvider).isGuardian, isTrue);
    await tapAndSettle(tester, 'Continue');
    expect(find.byType(CompleteStep), findsOneWidget);
    expect(find.byType(SubjectsStep), findsNothing);
    expect(find.byType(PermissionsStep), findsNothing);
    expect(find.text('Link a child’s phone'), findsOneWidget);
    expect(find.text('5 of 5'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await drain(tester);
    expect(find.text('Set up your profile'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('a parent studying here keeps the study setup', (tester) async {
    final container = freshContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const OnboardingFlow(),
        ),
      ),
    );
    await reachPersona(tester);
    await tapAndSettle(tester, 'Parent');
    await tapAndSettle(tester, 'Continue');
    await tapAndSettle(tester, 'Focus on this phone');
    await tapAndSettle(tester, 'Continue');
    expect(container.read(userProvider).isGuardian, isFalse);
    await tapAndSettle(tester, 'Continue');
    expect(find.byType(SubjectsStep), findsOneWidget);
    expect(find.text('5 of 8'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('a parent who changes their mind does not keep the answer', (
    tester,
  ) async {
    final container = freshContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const OnboardingFlow(),
        ),
      ),
    );

    await reachPersona(tester);
    await tapAndSettle(tester, 'Parent');
    await tapAndSettle(tester, 'Continue');
    await tapAndSettle(tester, 'Continue');
    expect(container.read(userProvider).isGuardian, isTrue);

    // Back to the persona — two pages, because the device question sits
    // between them — and this time the answer is "student".
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byTooltip('Back'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
    }
    expect(find.text('I am a...'), findsOneWidget);
    await tapAndSettle(tester, 'Student');
    await tapAndSettle(tester, 'Continue');

    expect(find.text('How will you use this phone?'), findsNothing);
    expect(container.read(userProvider).isGuardian, isFalse);
    await drain(tester);
  });

  testWidgets('the bar drops the Focus tab for a parent', (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final engine = RecordingShieldService();
    addTearDown(engine.dispose);

    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        shieldServiceProvider.overrideWithValue(engine),
        installedAppsProvider.overrideWith((ref) async => const []),
        appUsageTodayProvider.overrideWith((ref) async => const {}),
        usageAccessProvider.overrideWith((ref) async => false),
        shieldEnabledProvider.overrideWith((ref) async => false),
      ],
    );
    addTearDown(container.dispose);

    Future<void> pumpApp(UserProfile profile) async {
      container.read(userProvider.notifier).save(profile);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const FocusForgeApp(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
    }

    await pumpApp(
      const UserProfile(
        uid: 'student-1',
        displayName: 'Ravi',
        persona: Persona.student,
        onboardingComplete: true,
      ),
    );
    expect(find.text('Focus'), findsOneWidget, reason: 'a student keeps it');

    await pumpApp(
      const UserProfile(
        uid: 'parent-1',
        displayName: 'Amma',
        persona: Persona.parent,
        onboardingComplete: true,
        isGuardian: true,
      ),
    );
    expect(find.text('Focus'), findsNothing, reason: 'a parent loses it');
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Shield'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);

    // The branch is still reachable, and the bar does not fall over when it
    // is the current one.
    container.read(routerProvider).go('/focus');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
