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
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/providers/usage_providers.dart';
import 'package:focusforge/core/services/app_catalog.dart';
import 'package:focusforge/core/models/study.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/features/dashboard/dashboard_screen.dart';
import 'package:focusforge/features/dashboard/widgets/study_tracker.dart';
import 'package:focusforge/features/focus/fullscreen_clock.dart';
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
    Set<String> protectedPackages = const {},
  }) {
    final engine = RecordingShieldService()..protectedSet = protectedPackages;
    addTearDown(engine.dispose);

    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        // The engine is replaced rather than reached: `NativeShieldService`
        // reads `defaultTargetPlatform`, which *is* android inside a widget
        // test, so the real one would call a platform channel that never
        // answers and the protected set would stay pending forever.
        shieldServiceProvider.overrideWithValue(engine),
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

  /// Marks the first-run tips as already seen.
  ///
  /// The tips draw a full-screen scrim over the dashboard, so a test that
  /// taps anything on the page has to get them out of the way first — without
  /// this the tap lands on the spotlight rather than on the widget under test.
  /// The tips themselves are covered by their own group below, which wants
  /// them *not* seen.
  Future<void> tipsSeen() => store.setBool(StoreKeys.coachSeen, true);

  /// Runs [body] with the platform pinned to Android.
  Future<void> onAndroid(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  group('Shield screen', () {
    testWidgets('the list is the apps the user installed, with no add step', (
      tester,
    ) async {
      useTallPhone(tester);
      final container = freshContainer(
        apps: const [
          InstalledApp(
            packageId: 'com.example.social',
            name: 'Social App',
            isSystem: false,
          ),
          InstalledApp(
            packageId: 'com.example.vendor',
            name: 'Vendor Browser',
            isSystem: true,
          ),
        ],
      );

      await tester.pumpWidget(wrap(container, const ShieldScreen()));
      await settle(tester);

      expect(find.text('Social App'), findsOneWidget);
      expect(
        find.text('Vendor Browser'),
        findsNothing,
        reason:
            'system apps are most of the device and none of the intent — they '
            'buried the apps the user chose to install',
      );
      // There is no picker to open: the list *is* the device.
      expect(find.text('Add apps'), findsNothing);
      expect(find.text('All apps'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a system app that already carries a rule stays visible', (
      tester,
    ) async {
      useTallPhone(tester);
      final container = freshContainer(
        apps: const [
          InstalledApp(
            packageId: 'com.example.vendor',
            name: 'Vendor Browser',
            isSystem: true,
          ),
        ],
      );
      await container
          .read(whitelistProvider.notifier)
          .addInstalledApp(
            packageId: 'com.example.vendor',
            name: 'Vendor Browser',
            tier: WhitelistTier.blocked,
          );

      await tester.pumpWidget(wrap(container, const ShieldScreen()));
      await settle(tester);

      expect(
        find.text('Vendor Browser'),
        findsOneWidget,
        reason: 'a rule with no row is a restriction the user cannot turn off',
      );
      expect(find.text('System'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a rule shows on the app it applies to', (tester) async {
      useTallPhone(tester);
      final container = freshContainer(
        apps: const [
          InstalledApp(
            packageId: 'com.example.blocked',
            name: 'Blocked App',
            isSystem: false,
          ),
          InstalledApp(
            packageId: 'com.example.budget',
            name: 'Budgeted App',
            isSystem: false,
          ),
        ],
      );
      await container
          .read(whitelistProvider.notifier)
          .addInstalledApp(
            packageId: 'com.example.blocked',
            name: 'Blocked App',
            tier: WhitelistTier.blocked,
          );
      await container
          .read(whitelistProvider.notifier)
          .addInstalledApp(
            packageId: 'com.example.budget',
            name: 'Budgeted App',
            tier: WhitelistTier.budgeted,
            budgetMinutes: 30,
          );

      await tester.pumpWidget(wrap(container, const ShieldScreen()));
      await settle(tester);

      expect(find.text('Blocked App'), findsOneWidget);
      expect(find.text('Budgeted App'), findsOneWidget);
      expect(
        find.text('Closes when opened'),
        findsOneWidget,
        reason: 'a rule says what it will do, not just which tier it is in',
      );
      expect(find.text('0m of 30m used today'), findsOneWidget);
      // Both rows are switched on, and neither carries a tier chip any more —
      // the switch and the sentence under the name are the whole state.
      expect(find.byType(Switch), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a budgeted rule shows today\'s real usage', (tester) async {
      useTallPhone(tester);
      final container = freshContainer(
        apps: const [
          InstalledApp(
            packageId: 'com.example.budget',
            name: 'Budgeted App',
            isSystem: false,
          ),
        ],
        usage: const {'com.example.budget': 12},
        usageAccess: true,
      );
      await container
          .read(whitelistProvider.notifier)
          .addInstalledApp(
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

    testWidgets('usage shows on the row, not in a suggestion strip', (
      tester,
    ) async {
      useTallPhone(tester);
      final container = freshContainer(
        apps: const [
          InstalledApp(
            packageId: 'com.example.busy',
            name: 'Busy App',
            isSystem: false,
          ),
        ],
        usage: const {'com.example.busy': 90},
        usageAccess: true,
      );

      await tester.pumpWidget(wrap(container, const ShieldScreen()));
      await settle(tester);

      expect(find.text('Busy App'), findsOneWidget);
      expect(find.text('1h 30m today'), findsOneWidget);
      expect(
        find.text('Most used today'),
        findsNothing,
        reason: 'the list is the whole page; nothing is lifted above it',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('an app the engine will never cover is left out of the list', (
      tester,
    ) async {
      useTallPhone(tester);
      // The keyboard, the launcher, the settings app, the status bar and this
      // app are what the engine refuses to cover. They are dropped from the
      // list rather than shown with a switch that could never act — and the
      // set is asked of the engine itself, not guessed at here.
      final container = freshContainer(
        apps: const [
          InstalledApp(
            packageId: 'com.example.social',
            name: 'Social App',
            isSystem: false,
          ),
          InstalledApp(
            packageId: 'com.example.launcher',
            name: 'Third-party Launcher',
            isSystem: false,
          ),
        ],
        protectedPackages: const {'com.example.launcher'},
      );

      await tester.pumpWidget(wrap(container, const ShieldScreen()));
      await settle(tester);

      expect(find.text('Social App'), findsOneWidget);
      expect(
        find.text('Third-party Launcher'),
        findsNothing,
        reason: 'a row whose switch can never act is not a row',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a budget with no usage access says it is not counting', (
      tester,
    ) async {
      useTallPhone(tester);
      await onAndroid(tester, () async {
        final container = freshContainer(
          shieldEnabled: true,
          usageAccess: false,
        );
        await container
            .read(whitelistProvider.notifier)
            .addInstalledApp(
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
      await tipsSeen();
      await tester.pumpWidget(wrap(freshContainer(), const DashboardScreen()));
      await settle(tester);

      expect(find.text('No sessions yet'), findsOneWidget);
      // Section headers are set in small caps, so the rendered text is the
      // uppercased title rather than the string the caller passes in.
      expect(
        find.text('SCREEN TIME TODAY'),
        findsOneWidget,
        reason:
            'screen time is about the phone, not the session log, so it '
            'is worth showing before the first session',
      );
      // The shield summary used to live here too. It answers a question about
      // the phone that the Shield tab already answers with the rules behind
      // it, so it is not on the dashboard at all any more.
      expect(find.text('APP SHIELDS'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a logged session reaches the tracker, and a bar opens its '
        'day', (tester) async {
      useTallPhone(tester);
      final container = freshContainer();
      final now = DateTime.now();

      await tipsSeen();
      await container
          .read(sessionsProvider.notifier)
          .record(
            FocusSession(
              id: 's-test',
              subjectId: 'math',
              startedAt: DateTime(now.year, now.month, now.day, 9),
              minutes: 50,
            ),
          );

      await tester.pumpWidget(wrap(container, const DashboardScreen()));
      await settle(tester);

      expect(
        find.text('50m'),
        findsWidgets,
        reason: 'the ring, the breakdown and the day all agree',
      );
      expect(find.text('WEEKLY PROGRESS'), findsOneWidget);

      // The tracker opens on the week; the month is the other window onto the
      // same log.
      await tester.tap(find.text('Month'));
      await settle(tester);
      expect(find.text('MONTHLY PROGRESS'), findsOneWidget);
      await tester.tap(find.text('Week'));
      await settle(tester);

      // Tapping a bar opens that day's breakdown. Today is the last bar, so
      // the tap goes to the right-hand end of the tracker rather than to a
      // label that appears in three other places on the page.
      final tracker = tester.getRect(find.byType(StudyTracker));
      await tester.tapAt(Offset(tracker.right - 12, tracker.center.dy));
      await settle(tester);
      expect(
        find.text('Today'),
        findsWidgets,
        reason: 'the tracker labels the bar and the sheet names the day',
      );
      expect(find.text('Math'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('screen time says so when Android will not share usage', (
      tester,
    ) async {
      useTallPhone(tester);
      await tipsSeen();
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

    testWidgets('the spotlight follows a target that moves after it opens', (
      tester,
    ) async {
      useTallPhone(tester);
      final targets = CoachTargets();

      Widget app(double top) => wrap(
        freshContainer(),
        CoachMarks(
          spots: [
            CoachSpot(
              target: targets.emptyCta,
              icon: Icons.play_arrow_rounded,
              title: 'Start here',
              body: 'The hole has to stay on the button.',
            ),
          ],
          child: Stack(
            children: [
              Positioned(
                top: top,
                left: 40,
                child: SizedBox(
                  width: 140,
                  height: 48,
                  child: FilledButton(
                    key: targets.emptyCta,
                    onPressed: () {},
                    child: const Text('Go'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      // The tip opens while the target is near the bottom of the screen —
      // and then the page slides it up, which is what the dashboard's
      // entrance does. A hole measured once would stay where the button used
      // to be, pointing at empty space.
      await tester.pumpWidget(app(1400));
      await tester.pump();
      await tester.pump();
      await tester.pumpWidget(app(120));
      await tester.pump();
      await settle(tester);

      final target = tester.getRect(find.byKey(targets.emptyCta));
      final bubble = tester.getRect(find.byType(Card));
      expect(
        bubble.top,
        inInclusiveRange(target.bottom, target.bottom + 240),
        reason: 'the bubble hangs off the hole the button is actually in',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Full-screen clock', () {
    /// The radial wash of phase colour behind the clock.
    Iterable<DecoratedBox> washes(WidgetTester tester) =>
        tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).where((d) {
          final decoration = d.decoration;
          return decoration is BoxDecoration &&
              decoration.gradient is RadialGradient;
        });

    Future<void> pumpClock(
      WidgetTester tester,
      ProviderContainer container, {
      required bool amoled,
    }) async {
      useTallPhone(tester);
      // Set, not merely turned on: true black ships on, so a test that wants
      // the tinted surface has to say so.
      await container.read(themeSettingsProvider.notifier).setAmoled(amoled);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const FullscreenClock(),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('the wash is drawn when true black is off', (tester) async {
      final container = freshContainer();
      await pumpClock(tester, container, amoled: false);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(
        scaffold.backgroundColor,
        isNot(const Color(0xFF000000)),
        reason: 'the wash is what says which phase is running',
      );
      expect(washes(tester), isNotEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('true black leaves the whole screen off', (tester) async {
      final container = freshContainer();
      await pumpClock(tester, container, amoled: true);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(
        scaffold.backgroundColor,
        const Color(0xFF000000),
        reason:
            'this is the one screen that is left on for an hour, and a tint '
            'over black is the thing the setting exists to avoid',
      );
      expect(
        washes(tester),
        isEmpty,
        reason: 'a gradient over pure black is not pure black',
      );
      expect(tester.takeException(), isNull);
    });
  });
}
