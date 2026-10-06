// Tests for what the Deep Breath Gate does when it closes — the hand-off back
// to the app the user chose to open anyway.
//
// WHAT INVARIANT: the two exits do opposite things and neither is ambiguous.
// "Go back" records a decision and hands nothing over; "Continue anyway"
// records a decision, grants the grace, and only then brings the app forward.
//
// WHY IT MATTERS: this is the one path in the app where a mistake is invisible
// in every other test. Granting the grace *after* the launch looks identical in
// Dart — both futures complete — but on a device it means the accessibility
// service covers the app again the instant it opens, so the user is returned to
// the block screen they just sat through. The order is the whole fix, and the
// only way to pin it is to record the calls.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/features/shield/breath_gate.dart';

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

  /// A tall phone viewport.
  ///
  /// The default test window is 800x600 — shorter than any phone this app runs
  /// on — and the completion panel's second button sits below that fold. A tap
  /// on an off-screen button is silently swallowed, which would make the tests
  /// that assert *nothing happened* pass for the wrong reason.
  void useTallPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Pumps the gate one route deep, so both of its exits have somewhere to go
  /// back to.
  ///
  /// The gate is pushed rather than used as the initial location on purpose: a
  /// route with nothing under it takes the deep-link branch instead, which is
  /// a different code path from the one a real interception reaches.
  Future<ProviderContainer> pumpGate(
    WidgetTester tester, {
    String? packageId = 'com.example.scroll',
    int graceSeconds = ShieldConfig.defaultGraceSeconds,
  }) async {
    useTallPhone(tester);

    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        // The engine is stubbed rather than left to the provider's default:
        // in a widget test `defaultTargetPlatform` is Android, so the default
        // would be the real MethodChannel, whose calls never reply and would
        // leave the gate awaiting a hand-off that never finishes.
        shieldServiceProvider.overrideWithValue(RecordingShieldService()),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Center(child: Text('behind'))),
        ),
        GoRoute(
          path: '/gate',
          builder: (_, _) => BreathGateScreen(
            args: BreathGateArgs(
              appName: 'Endless Scroll',
              packageId: packageId,
              graceSeconds: graceSeconds,
            ),
          ),
        ),
      ],
    );

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
    router.push('/gate');
    await tester.pumpAndSettle();
    return container;
  }

  /// Runs the 4-7-8 protocol out and lands on the completion panel.
  ///
  /// One pump past the 57-second protocol rather than 57 seconds of frames:
  /// the controller's value is what the screen reads, and it reaches 1.0 in a
  /// single step.
  Future<void> breatheThrough(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 58));
    await tester.pumpAndSettle();
    expect(
      find.text('Continue anyway'),
      findsOneWidget,
      reason: 'the protocol has to finish before either exit is offered',
    );
  }

  RecordingShieldService serviceOf(ProviderContainer container) =>
      container.read(shieldServiceProvider) as RecordingShieldService;

  /// Taps one of the two exits, scrolling it into view first.
  ///
  /// A tap on a widget below the fold is swallowed without an error, which
  /// would make every assertion of the form "nothing was handed over" pass for
  /// entirely the wrong reason.
  Future<void> tapExit(WidgetTester tester, String label) async {
    final button = find.text(label);
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('the second exit grants the grace before it opens the app', (
    tester,
  ) async {
    final container = await pumpGate(tester, graceSeconds: 120);
    await breatheThrough(tester);

    await tapExit(tester, 'Continue anyway');

    expect(
      serviceOf(container).calls,
      ['grant:com.example.scroll@120', 'open:com.example.scroll'],
      reason: 'the grace has to be in place before the launch, or the block '
          'screen the user just sat through comes straight back',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the second exit logs the decision as going in', (tester) async {
    final container = await pumpGate(tester);
    await breatheThrough(tester);

    await tapExit(tester, 'Continue anyway');

    final log = container.read(breathEventsProvider);
    expect(log, hasLength(1));
    expect(log.single.appName, 'Endless Scroll');
    expect(
      log.single.walkedAway,
      isFalse,
      reason: '"open it anyway" is the number that says the pause did not '
          'change your mind',
    );
  });

  testWidgets('the first exit hands nothing over', (tester) async {
    final container = await pumpGate(tester);
    await breatheThrough(tester);

    await tapExit(tester, 'Go back');

    expect(
      serviceOf(container).calls,
      isEmpty,
      reason: 'walking away means the app stays closed',
    );
    expect(container.read(breathEventsProvider).single.walkedAway, isTrue);
  });

  testWidgets('a preview hands nothing over and writes nothing', (tester) async {
    final container = await pumpGate(tester, packageId: null);
    await breatheThrough(tester);

    await tapExit(tester, 'Continue anyway');

    expect(
      serviceOf(container).calls,
      isEmpty,
      reason: 'there is no interception behind a preview, so there is no app '
          'to bring forward',
    );
    expect(
      container.read(breathEventsProvider),
      isEmpty,
      reason: 'a decision the user did not make has no place in the numbers '
          'the Shield screen reports',
    );
    expect(tester.takeException(), isNull);
  });
}
