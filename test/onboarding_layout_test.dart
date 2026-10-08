import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/features/onboarding/auth_screen.dart';
import 'package:focusforge/features/onboarding/goal_step.dart';
import 'package:focusforge/features/onboarding/onboarding_chrome.dart';
import 'package:focusforge/features/onboarding/permissions_step.dart';
import 'package:focusforge/features/onboarding/setup_choice_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
  });

  Widget wrap(Widget child, {double scale = 1, bool dark = false}) =>
      ProviderScope(
        overrides: [localStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          theme: dark ? AppTheme.dark(amoled: true) : AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
          home: Scaffold(body: child),
        ),
      );

  void viewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  for (final dark in [false, true]) {
    testWidgets(
      'account actions remain reachable with large text, dark=$dark',
      (tester) async {
        viewport(tester, const Size(320, 480));
        await tester.pumpWidget(
          wrap(const AuthScreen(embedded: true), scale: 2, dark: dark),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.text('Skip for now'), 160);
        expect(find.text('Skip for now').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('short setup layouts keep their action in the scroll surface', (
    tester,
  ) async {
    viewport(tester, const Size(320, 280));
    var completed = false;
    await tester.pumpWidget(
      wrap(
        StepScaffold(
          title: 'Your profile',
          subtitle: 'Set up the details you want to use.',
          onPrimary: () => completed = true,
          children: const [SizedBox(height: 350, child: Text('Details'))],
        ),
        scale: 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Continue'), 180);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
  });

  testWidgets(
    'a pending setup save refuses repeated taps and recovers from failure',
    (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        wrap(
          StepScaffold(
            title: 'Save setup',
            onPrimary: () {
              calls++;
              return pending.future;
            },
            children: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pump();
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
      expect(calls, 1);
      pending.completeError(StateError('storage unavailable'));
      await tester.pumpAndSettle();
      expect(find.text('Could not save this step. Try again.'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('goal suggestions fit narrow screens with enlarged text', (
    tester,
  ) async {
    viewport(tester, const Size(320, 640));
    await tester.pumpWidget(wrap(GoalStep(onNext: () {}), scale: 2));
    await tester.pumpAndSettle();
    final suggested = find.widgetWithText(FilterChip, 'Recommended');
    await tester.scrollUntilVisible(suggested, 160);
    await tester.pumpAndSettle();
    await tester.tap(suggested);
    await tester.pumpAndSettle();
    expect(suggested.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsupported platforms have no irrelevant enable buttons', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    var continued = false;
    try {
      await tester.pumpWidget(
        wrap(PermissionsStep(onNext: () => continued = true)),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('No extra permissions are needed on this device.'),
        findsOneWidget,
      );
      expect(find.text('Enable'), findsNothing);
      await tester.tap(find.text('Review setup'));
      await tester.pumpAndSettle();
      expect(continued, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'setup choices announce checked state and respect reduced motion',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          wrap(
            SetupChoiceCard(
              title: 'Student',
              description: 'Study on this phone.',
              icon: Icons.school_outlined,
              color: Colors.blue,
              selected: true,
              onTap: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(find.byType(SetupChoiceCard)),
          matchesSemantics(
            label: 'Student. Study on this phone.',
            hasCheckedState: true,
            isChecked: true,
            isInMutuallyExclusiveGroup: true,
            hasTapAction: true,
          ),
        );
        expect(
          tester
              .widget<AnimatedContainer>(find.byType(AnimatedContainer))
              .duration,
          Duration.zero,
        );
      } finally {
        semantics.dispose();
      }
    },
  );
}
