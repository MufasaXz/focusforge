import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/providers/usage_providers.dart';
import 'package:focusforge/core/services/app_catalog.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/permission_manager.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/core/models/shield.dart';
import 'package:focusforge/features/shield/shield_access.dart';
import 'package:focusforge/features/shield/shield_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.focusforge/shield'),
          null,
        );
    debugDefaultTargetPlatformOverride = null;
  });

  ProviderContainer containerFor({
    bool accessible = false,
    bool usage = false,
    bool Function()? accessibilityCheck,
    PermissionManager? manager,
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
        shieldEnabledProvider.overrideWith(
          (ref) async => accessibilityCheck?.call() ?? accessible,
        ),
        if (manager != null)
          shieldPermissionManagerProvider.overrideWithValue(manager),
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
    'enabling an app without usage access asks for access and saves no rule',
    (tester) async {
      final container = containerFor();
      await mount(tester, container, const ShieldScreen());
      expect(find.text('Turn on app blocking'), findsNothing);
      expect(find.text('1 apps'), findsNothing);
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
    'normal app blocking works with usage and overlay without accessibility',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('dev.focusforge/shield'),
            (call) async {
              if (call.method == 'hasOverlayPermission' ||
                  call.method == 'resumeAppBlocking') {
                return true;
              }
              return false;
            },
          );
      final manager = SettingsPermissionManager();
      final container = containerFor(usage: true, manager: manager);
      await mount(tester, container, const ShieldScreen());
      final row = find.ancestor(
        of: find.text('Instagram'),
        matching: find.byType(InkWell),
      );
      await tester.tap(
        find.descendant(of: row, matching: find.byType(GestureDetector)).last,
      );
      await tester.pumpAndSettle();
      expect(container.read(whitelistProvider), hasLength(1));
      expect(manager.requests, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('normal app rule requests only overlay after usage is granted', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.focusforge/shield'),
          (_) async => false,
        );
    final manager = SettingsPermissionManager();
    final container = containerFor(usage: true, manager: manager);
    await mount(tester, container, const ShieldScreen());
    final row = find.ancestor(
      of: find.text('Instagram'),
      matching: find.byType(InkWell),
    );
    await tester.tap(
      find.descendant(of: row, matching: find.byType(GestureDetector)).last,
    );
    await tester.pumpAndSettle();
    expect(find.text('Allow draw over other apps'), findsOneWidget);
    expect(container.read(whitelistProvider), isEmpty);
    await tester.tap(find.text('Open overlay settings'));
    await tester.pumpAndSettle();
    expect(manager.requests, [AppPermission.overlay]);
    expect(container.read(whitelistProvider), isEmpty);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'budget status remains inactive after app boundaries are stopped',
    (tester) async {
      final container = containerFor(usage: true);
      await container
          .read(whitelistProvider.notifier)
          .addInstalledApp(
            packageId: 'com.instagram.android',
            name: 'Instagram',
            tier: WhitelistTier.budgeted,
            budgetMinutes: 30,
          );
      await mount(tester, container, const ShieldScreen());
      await tester.tap(find.bySemanticsLabel(RegExp('Shield status')));
      await tester.pumpAndSettle();
      expect(find.text('1 inactive'), findsOneWidget);
      expect(find.text('1 running'), findsNothing);
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
      expect(find.text('Allow Shorts blocking'), findsOneWidget);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(container.read(youtubeRulesProvider).shorts, isFalse);
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

  testWidgets(
    'Shorts consent opens settings once and waits for a verified retry',
    (tester) async {
      var accessible = false;
      final manager = SettingsPermissionManager();
      final container = containerFor(
        accessibilityCheck: () => accessible,
        manager: manager,
      );
      await mount(tester, container, const ShieldScreen());
      await tester.tap(find.text('YouTube'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      // Entering the tab itself must not ask for special access.
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.widgetWithText(SwitchListTile, 'Block Shorts'));
      await tester.pumpAndSettle();
      expect(find.text('Agree and open Settings'), findsOneWidget);
      await tester.tap(find.text('Agree and open Settings'));
      await tester.pumpAndSettle();
      expect(manager.requests, [AppPermission.accessibility]);
      expect(container.read(youtubeRulesProvider).shorts, isFalse);
      // A return from Settings alone cannot enable a rule without a grant.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(container.read(youtubeRulesProvider).shorts, isFalse);
      accessible = true;
      await tester.tap(find.widgetWithText(SwitchListTile, 'Block Shorts'));
      await tester.pumpAndSettle();
      expect(container.read(youtubeRulesProvider).shorts, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      // Turning it off remains possible if access is later revoked.
      accessible = false;
      await tester.tap(find.widgetWithText(SwitchListTile, 'Block Shorts'));
      await tester.pumpAndSettle();
      expect(container.read(youtubeRulesProvider).shorts, isFalse);
      await tester.tap(find.widgetWithText(SwitchListTile, 'Block Shorts'));
      await tester.pumpAndSettle();
      expect(container.read(youtubeRulesProvider).shorts, isFalse);
      expect(find.text('Allow Shorts blocking'), findsOneWidget);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(manager.requests, [AppPermission.accessibility]);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}

class SettingsPermissionManager extends PermissionManager {
  final requests = <AppPermission>[];
  @override
  Future<PermissionOutcome> request(AppPermission permission) async {
    requests.add(permission);
    return PermissionOutcome.openedSettings;
  }
}
