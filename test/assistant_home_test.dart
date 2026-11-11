// Pip on the home screen.
//
// WHAT INVARIANT: Pip stands on Home and says hello once per launch, a hello
// that takes turns with what Pip has noticed; its tips
// are rare — none within three hours of the last, none with tips paused; left
// alone it sits, thinks and falls asleep, and a touch wakes it; every
// animation ends, so the page settles; a tap opens the chat.
//
// WHY IT MATTERS: a character that talks too often gets ignored or resented,
// and one that never stops animating drains the battery and hangs any screen
// that waits for the page to be still.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/app.dart';
import 'package:focusforge/app/router.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/providers/usage_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/features/assistant/assistant_memory.dart';
import 'package:focusforge/features/assistant/mascot/mascot.dart';
import 'package:focusforge/features/assistant/mascot/mascot_rig.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStore store;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
  });

  setUp(() async => store.clearAll());

  const intro = 'Hi! I’m Pip, your study buddy. Tap me anytime.';
  const planTip = 'Want me to plan today’s study?';
  final dock = find.byKey(const ValueKey('pip-dock'));

  Future<ProviderContainer> pumpHome(
    WidgetTester tester, {
    AssistantMemory memory = const AssistantMemory(),
  }) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await store.setBool(StoreKeys.coachSeen, true);
    await store.setMap(StoreKeys.assistant, memory.toJson());
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
    await container.read(userProvider.notifier).completeOnboarding();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const FocusForgeApp(),
      ),
    );
    return container;
  }

  Future<void> wait(WidgetTester tester, Duration length) async {
    for (var t = 0; t < length.inMilliseconds; t += 100) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  MascotRig rigOf(WidgetTester tester) => tester
      .widget<Mascot>(find.descendant(of: dock, matching: find.byType(Mascot)))
      .rig;

  testWidgets('Pip says hello once per launch, and a tap opens the chat', (
    tester,
  ) async {
    final container = await pumpHome(tester);
    await wait(tester, const Duration(seconds: 3));
    expect(dock, findsOneWidget);
    expect(find.text(intro), findsOneWidget);
    expect(container.read(assistantMemoryProvider).lastSeen, isNotNull);

    // Away to another tab and back: no second hello.
    container.read(routerProvider).go('/shield');
    await wait(tester, const Duration(seconds: 1));
    container.read(routerProvider).go('/dashboard');
    await wait(tester, const Duration(seconds: 3));
    expect(find.text(intro), findsNothing);

    await tester.tap(dock);
    // Long enough for Pip to finish typing its introduction.
    await wait(tester, const Duration(seconds: 8));
    expect(find.text('Message Pip'), findsOneWidget);
    expect(find.text('Hi, I’m Pip, your study buddy.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('left alone, Pip sits, thinks and sleeps; a touch wakes it', (
    tester,
  ) async {
    await pumpHome(
      tester,
      memory: AssistantMemory(
        lastSeen: DateTime.now(),
        lastTipAt: DateTime.now(),
      ),
    );
    await wait(tester, const Duration(seconds: 25));
    expect(rigOf(tester).sitting, isTrue);
    await wait(tester, const Duration(seconds: 45));
    expect(rigOf(tester).sleeping, isTrue);

    // Asleep is still: the page can settle.
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Scrollable).first, warnIfMissed: false);
    await wait(tester, const Duration(seconds: 2));
    expect(rigOf(tester).sleeping, isFalse);
    expect(rigOf(tester).sitting, isFalse);
  });

  testWidgets('tips are rare: none within three hours, none when paused', (
    tester,
  ) async {
    // Seen a minute ago, so no hello either; a tip an hour ago.
    await pumpHome(
      tester,
      memory: AssistantMemory(
        lastSeen: DateTime.now().subtract(const Duration(minutes: 1)),
        lastTipAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
    );
    await wait(tester, const Duration(seconds: 45));
    expect(find.text(planTip), findsNothing);
    expect(find.text(intro), findsNothing);
  });

  testWidgets('after a quiet spell Pip offers one useful tip', (tester) async {
    final container = await pumpHome(
      tester,
      memory: AssistantMemory(
        lastSeen: DateTime.now().subtract(const Duration(minutes: 1)),
        lastTipAt: DateTime.now().subtract(const Duration(hours: 4)),
      ),
    );
    await wait(tester, const Duration(seconds: 40));
    expect(find.text(planTip), findsOneWidget);
    expect(container.read(assistantMemoryProvider).lastTipAt, isNotNull);
    expect(
      DateTime.now().difference(
        container.read(assistantMemoryProvider).lastTipAt!,
      ),
      lessThan(const Duration(hours: 1)),
    );
  });

  testWidgets('a hello takes turns with a thought, which is the only one', (
    tester,
  ) async {
    // Back after four hours, with one hello already said: this launch opens
    // with something Pip noticed instead of the same greeting.
    final container = await pumpHome(
      tester,
      memory: AssistantMemory(
        lastSeen: DateTime.now().subtract(const Duration(hours: 4)),
        helloTurn: 1,
        lastSaid: 'Welcome back!',
      ),
    );
    await wait(tester, const Duration(seconds: 3));
    expect(find.text(planTip), findsOneWidget);
    final memory = container.read(assistantMemoryProvider);
    expect(memory.helloTurn, 2);
    expect(memory.lastSaid, planTip);
    expect(memory.lastTipAt, isNotNull);

    // The thought was this visit's tip: the idle think brings no second one.
    await wait(tester, const Duration(seconds: 8));
    expect(find.text(planTip), findsNothing);
    await wait(tester, const Duration(seconds: 34));
    expect(find.text(planTip), findsNothing);
    expect(container.read(assistantMemoryProvider).tipTurn, 1);
  });

  testWidgets('with tips paused Pip still waves but stays silent', (
    tester,
  ) async {
    await pumpHome(tester, memory: const AssistantMemory(quiet: true));
    await wait(tester, const Duration(seconds: 40));
    expect(find.text(intro), findsNothing);
    expect(find.text(planTip), findsNothing);
    expect(dock, findsOneWidget);
  });

  testWidgets('with reduce motion Pip holds still and speaks at once', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpHome(tester);
    await wait(tester, const Duration(seconds: 2));
    expect(find.text(intro), findsOneWidget);
    expect(rigOf(tester).moving, isFalse);
    await tester.pumpAndSettle();
  });
}
