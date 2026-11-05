// Moving between the four tabs by swiping.
//
// WHAT INVARIANT: a horizontal swipe moves to the next or previous tab and
// the router follows it; a tap on the bar still moves the pages; a tab keeps
// its state when the user swipes away and back.
//
// WHY IT MATTERS: the bar is at the far edge of the screen from where a thumb
// rests, and a swipe is the faster way between neighbouring tabs. A swipe
// that moved the pages without the router would leave the bar and the screen
// disagreeing about where the user is.

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

  Future<ProviderContainer> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
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
    await container.read(userProvider.notifier).completeOnboarding();
    await store.setBool(StoreKeys.coachSeen, true);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const FocusForgeApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    return container;
  }

  String location(ProviderContainer container) =>
      container.read(routerProvider).routeInformationProvider.value.uri.path;

  Future<void> swipe(WidgetTester tester, double dx) async {
    await tester.fling(find.byType(PageView), Offset(dx, 0), 1200);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  testWidgets('a swipe moves between neighbouring tabs', (tester) async {
    final container = await pumpApp(tester);
    expect(location(container), '/dashboard');

    await swipe(tester, -300);
    expect(location(container), '/shield');

    await swipe(tester, -300);
    expect(location(container), '/focus');

    await swipe(tester, 300);
    expect(location(container), '/shield');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tap on the bar moves the pages with it', (tester) async {
    final container = await pumpApp(tester);

    await tester.tap(find.text('You'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(location(container), '/profile');

    // The pages followed the bar, so one swipe back lands on Focus.
    await swipe(tester, 300);
    expect(location(container), '/focus');
  });
}
