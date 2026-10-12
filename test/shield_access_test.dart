import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/providers/usage_providers.dart';
import 'package:focusforge/core/services/app_catalog.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/features/shield/shield_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  ProviderContainer containerFor({
    bool accessible = false,
    bool usage = false,
  }) {
    final engine = RecordingShieldService();
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        shieldServiceProvider.overrideWithValue(engine),
        installedAppsProvider.overrideWith(
          (ref) async => const [
            InstalledApp(
              packageId: 'com.instagram.android',
              name: 'Instagram',
              isSystem: false,
            ),
          ],
        ),
        shieldEnabledProvider.overrideWith((ref) async => accessible),
        usageAccessProvider.overrideWith((ref) async => usage),
        appUsageTodayProvider.overrideWith((ref) async => const {}),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(engine.dispose);
    return container;
  }

  Future<void> mount(
    WidgetTester tester,
    ProviderContainer container,
    Widget screen,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: screen),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'enabling an app without accessibility asks for access and saves no rule',
    (tester) async {
      final container = containerFor();
      await mount(tester, container, const ShieldScreen());
      final row = find.ancestor(
        of: find.text('Instagram'),
        matching: find.byType(InkWell),
      );
      await tester.tap(
        find.descendant(of: row, matching: find.byType(GestureDetector)).last,
      );
      await tester.pumpAndSettle();

      expect(container.read(whitelistProvider), isEmpty);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'enabling a YouTube filter without accessibility leaves the filter off',
    (tester) async {
      final container = containerFor();
      await mount(tester, container, const ShieldScreen());
      await tester.tap(find.text('YouTube'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SwitchListTile, 'Block Shorts'));
      await tester.pumpAndSettle();

      expect(container.read(youtubeRulesProvider).shorts, isFalse);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('a budget without usage access is not saved as an active rule', (
    tester,
  ) async {
    final container = containerFor(accessible: true);
    await mount(
      tester,
      container,
      const AppRuleSheet(
        packageId: 'com.instagram.android',
        name: 'Instagram',
        icon: Icons.apps,
        usedMinutes: 0,
      ),
    );
    await tester.tap(find.text('Time budgeted'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save rule'));
    await tester.pumpAndSettle();

    expect(container.read(whitelistProvider), isEmpty);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
