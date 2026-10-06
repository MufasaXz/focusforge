// Widget smoke tests for the two screens this change rebuilt from scratch:
// the Shield tab (lib/features/shield/shield_screen.dart) and the dashboard
// (lib/features/dashboard/dashboard_screen.dart).
//
// WHAT INVARIANT: both screens build and lay out in every state they can be
// opened in — nothing armed, rules armed, Android present, Android absent —
// and the first-run tips measure a real widget instead of pointing at a
// hardcoded fraction of the screen.
//
// WHY IT MATTERS: neither screen is reachable from the model tests, and both
// are dense enough that a mistake in them is a layout exception at runtime
// rather than a compile error. The tips in particular are drawn in an overlay
// outside the page's own tree, so a missing Material ancestor or a hole
// measured in the wrong coordinate space would only ever show up on a device.
//
// The platform is overridden rather than assumed: `defaultTargetPlatform`
// follows the host OS in a test, so the Android-only branches — the
// permission gate, the app picker — are exercised by pinning it.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/shield.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/coach_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/providers/usage_providers.dart';
import 'package:focusforge/core/services/app_catalog.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/features/dashboard/dashboard_screen.dart';
import 'package:focusforge/features/onboarding/coach_marks.dart';
import 'package:focusforge/features/shield/shield_screen.dart';

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

  /// A container with the platform reads pinned.
  ///
  /// The three usage providers are overridden rather than left to run: a
  /// platform channel with no handler never replies in the test binding, so
  /// the futures stay pending forever and every screen behind them renders a
  /// spinner for the rest of the test. Pinning them is also what makes the
  /// assertions about *which* state is drawn meaningful.
  ProviderContainer freshContainer({
    List<InstalledApp> apps = const [],
    Map<String, int> usage = const {},
    bool usageAccess = false,
    bool shieldEnabled = false,
  }) {
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        installedAppsProvider.overrideWith((ref) async => apps),
        appUsageTodayProvider.overrideWith((ref) async => usage),
        usageAccessProvider.overrideWith((ref) async => usageAccess),
        shieldEnabledProvider.overrideWith((ref) async => shieldEnabled),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Widget wrap(ProviderContainer container, Widget child) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: child),
        ),
      );

  /// A tall phone viewport.
  ///
  /// The default test window is 800x600 — shorter than any phone this app runs
  /// on — and both of these screens are long scroll views. A card below the
  /// fold is not built at all, so an assertion about it would fail for a
  /// reason that has nothing to do with the layout being wrong.
  void useTallPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Pumps past the stagger entrance and the tab fade.
  ///
  /// [Stagger] schedules its entrance with a bare `Future.delayed`, which
  /// schedules no frame — `pumpAndSettle` alone returns with the timer still
  /// pending and the framework then fails the test on teardown.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  /// Runs [body] with the platform pinned to Android.
  Future<void> onAndroid(WidgetTester tester, Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  group('Shield screen', () {
    testWidgets('an empty rule list renders its designed state', (tester) async {
      useTallPhone(tester);
      await tester.pumpWidget(wrap(freshContainer(), const ShieldScreen()));
      await settle(tester);

      expect(find.text('Nothing is armed yet'), findsOneWidget);
      expect(find.text('Add apps'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a rule renders with its tier and its name', (tester) async {
      useTallPhone(tester);
      final container = freshContainer();
      await container.read(whitelistProvider.notifier).addInstalledApp(
        packageId: 'com.example.blocked',
        name: 'Blocked App',
        tier: WhitelistTier.blocked,
      );
      await container.read(whitelistProvider.notifier).addInstalledApp(
        packageId: 'com.example.budget',
        name: 'Budgeted App',
        tier: WhitelistTier.budgeted,
        budgetMinutes: 30,
      );

      await tester.pumpWidget(wrap(container, const ShieldScreen()));
      await settle(tester);

      expect(find.text('Blocked App'), findsOneWidget);
      expect(find.text('Budgeted App'), findsOneWidget);
      // "Blocked" twice: the section heading and the row's chip. The budgeted
      // heading reads "Time budgeted", so only the chip carries "Budgeted".
      expect(find.text('Blocked'), findsNWidgets(2));
      expect(find.text('Time budgeted'), findsOneWidget);
      expect(find.text('Budgeted'), findsOneWidget);
      expect(
        find.text('Closes when opened'),
        findsOneWidget,
        reason: 'a rule says what it will do, not just which tier it is in',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a budgeted rule shows today\'s real usage', (tester) async {
      useTallPhone(tester);
      final container = freshContainer(
        usage: const {'com.example.budget': 12},
        usageAccess: true,
      );
      await container.read(whitelistProvider.notifier).addInstalledApp(
        packageId: 'com.example.budget',
        name: 'Budgeted App',
        tier: WhitelistTier.budgeted,
        budgetMinutes: 30,
      );

      await tester.pumpWidget(wrap(container, const ShieldScreen()));
      await settle(tester);

      expect(find.text('12m of 30m used today'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a budget with no usage access says it is not counting', (
      tester,
    ) async {
      useTallPhone(tester);
      await onAndroid(tester, () async {
        final container = freshContainer(shieldEnabled: true, usageAccess: false);
        await container.read(whitelistProvider.notifier).addInstalledApp(
          packageId: 'com.example.budget',
          name: 'Budgeted App',
          tier: WhitelistTier.budgeted,
          budgetMinutes: 30,
        );

        await tester.pumpWidget(wrap(container, const ShieldScreen()));
        await settle(tester);

        expect(find.text('Time budgets are not counting'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('Android without accessibility access shows the gate', (
      tester,
    ) async {
      useTallPhone(tester);
      await onAndroid(tester, () async {
        await tester.pumpWidget(wrap(freshContainer(), const ShieldScreen()));
        await settle(tester);

        expect(find.text('Turn on app blocking'), findsOneWidget);
        expect(
          find.text('Open accessibility settings'),
          findsOneWidget,
          reason: 'a rule that cannot fire has to say what is missing',
        );
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('the YouTube tab names both surfaces', (tester) async {
      useTallPhone(tester);
      await tester.pumpWidget(wrap(freshContainer(), const ShieldScreen()));
      await settle(tester);
      await tester.tap(find.text('YouTube'));
      await settle(tester);

      expect(find.text('Block Shorts'), findsOneWidget);
      expect(find.text('Block home & search'), findsOneWidget);
      expect(
        find.textContaining('not by reading what is on them'),
        findsOneWidget,
        reason: 'the detection is a heuristic and the screen must say so',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Activity tab renders its empty log', (tester) async {
      useTallPhone(tester);
      await tester.pumpWidget(wrap(freshContainer(), const ShieldScreen()));
      await settle(tester);
      await tester.tap(find.text('Activity'));
      await settle(tester);

      expect(find.text('Nothing blocked yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Dashboard screen', () {
    testWidgets('a first run renders the empty state and the live cards', (
      tester,
    ) async {
      useTallPhone(tester);
      await tester.pumpWidget(wrap(freshContainer(), const DashboardScreen()));
      await settle(tester);

      expect(find.text('No sessions yet'), findsOneWidget);
      // Section headers are set in small caps, so the rendered text is the
      // uppercased title rather than the string the caller passes in.
      expect(
        find.text('SCREEN TIME TODAY'),
        findsOneWidget,
        reason: 'screen time is about the phone, not the session log, so it '
            'is worth showing before the first session',
      );
      expect(find.text('APP SHIELDS'), findsOneWidget);
      expect(
        find.text('No apps shielded yet'),
        findsOneWidget,
        reason: 'the summary has to say what to do, not just show nothing',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('real usage and a real rule both reach the page', (
      tester,
    ) async {
      useTallPhone(tester);
      final container = freshContainer(
        apps: const [
          InstalledApp(
            packageId: 'com.example.scroll',
            name: 'Endless Scroll',
            isSystem: false,
          ),
        ],
        usage: const {'com.example.scroll': 96},
        usageAccess: true,
      );
      await container.read(whitelistProvider.notifier).addInstalledApp(
        packageId: 'com.example.scroll',
        name: 'Endless Scroll',
        tier: WhitelistTier.blocked,
      );

      await tester.pumpWidget(wrap(container, const DashboardScreen()));
      await settle(tester);

      expect(find.text('Endless Scroll'), findsNWidgets(2));
      expect(
        find.text('1h 36m'),
        findsWidgets,
        reason: '96 minutes of real usage is the headline',
      );
      expect(find.text('Closes when opened'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('screen time says so when Android will not share usage', (
      tester,
    ) async {
      useTallPhone(tester);
      await tester.pumpWidget(wrap(freshContainer(), const DashboardScreen()));
      await settle(tester);

      expect(
        find.textContaining('is not sharing app usage'),
        findsOneWidget,
        reason: 'an empty chart would read as "nothing used today"',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('First-run tips', () {
    testWidgets('a tip measures its target and draws the spotlight', (
      tester,
    ) async {
      useTallPhone(tester);
      final targets = CoachTargets();

      await tester.pumpWidget(
        wrap(
          freshContainer(),
          CoachMarks(
            spots: [
              CoachSpot(
                target: targets.emptyCta,
                icon: Icons.play_arrow_rounded,
                title: 'Start here',
                body: 'This button is measured, not guessed at.',
              ),
            ],
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 120,
                height: 48,
                child: FilledButton(
                  key: targets.emptyCta,
                  onPressed: () {},
                  child: const Text('Go'),
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester);

      expect(find.text('Start here'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tip whose target is not on screen is dropped', (
      tester,
    ) async {
      useTallPhone(tester);
      final targets = CoachTargets();

      await tester.pumpWidget(
        wrap(
          freshContainer(),
          CoachMarks(
            spots: [
              CoachSpot(
                target: targets.focusTab,
                icon: Icons.timer_rounded,
                title: 'Never shown',
                body: 'This target is not in the tree.',
              ),
            ],
            child: const SizedBox.expand(),
          ),
        ),
      );
      await settle(tester);

      expect(
        find.text('Never shown'),
        findsNothing,
        reason: 'a spotlight over empty space points at nothing',
      );
      expect(tester.takeException(), isNull);
    });
  });
}
