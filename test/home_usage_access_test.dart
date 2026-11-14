import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/usage_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/permission_manager.dart';
import 'package:focusforge/features/dashboard/widgets/usage_access_card.dart';
import 'package:focusforge/features/dashboard/dashboard_screen.dart';
import 'package:focusforge/features/shield/shield_access.dart';

class _Permissions extends PermissionManager {
  final requests = <AppPermission>[];
  @override
  Future<PermissionOutcome> request(AppPermission permission) async {
    requests.add(permission);
    return PermissionOutcome.openedSettings;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Home offers goal setup and usage access without denied screen-time analytics',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      await store.clearAll();
      final container = ProviderContainer(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          usageAccessProvider.overrideWith((ref) async => false),
          appUsageTodayProvider.overrideWith((ref) async => const {}),
        ],
      );
      addTearDown(container.dispose);
      await store.setBool(StoreKeys.coachSeen, true);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const Scaffold(body: DashboardScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final start = find.text('Set goal');
      expect(find.text('Start focus'), findsNothing);
      expect(find.text('Screen time today'), findsNothing);
      expect(find.textContaining('is not sharing app usage'), findsNothing);
      final allow = find.text('Allow app usage');
      await tester.scrollUntilVisible(allow, 100);
      expect(allow, findsOneWidget);
      expect(
        tester.getTopLeft(allow).dy,
        greaterThan(tester.getTopLeft(start).dy),
      );
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'Home disclosure is optional and affirmative before opening usage settings',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      final manager = _Permissions();
      final container = ProviderContainer(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          usageAccessProvider.overrideWith((ref) async => false),
          shieldPermissionManagerProvider.overrideWithValue(manager),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: UsageAccessCard()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final cardAllow = find.widgetWithText(FilledButton, 'Allow');
      expect(find.text('Allow app usage'), findsOneWidget);
      expect(manager.requests, isEmpty);
      // First time: one dialog, the app-list disclosure, which already
      // covers what usage access reads. Declining it requests nothing.
      await tester.tap(cardAllow);
      await tester.pumpAndSettle();
      expect(
        find.text('Allow FocusForge to read your app list?'),
        findsOneWidget,
      );
      expect(find.text('Why FocusForge asks for app usage'), findsNothing);
      expect(find.textContaining('never uploaded or shared'), findsOneWidget);
      await tester.tap(find.text('Not now').last);
      await tester.pumpAndSettle();
      expect(manager.requests, isEmpty);
      expect(container.read(appListConsentProvider), isFalse);

      await tester.tap(cardAllow);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agree'));
      await tester.pumpAndSettle();
      expect(container.read(appListConsentProvider), isTrue);
      // The guide comes next; Android opens only from its button.
      expect(find.text('Turn on Usage access'), findsOneWidget);
      expect(manager.requests, isEmpty);
      await tester.ensureVisible(find.text('Open settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(manager.requests, [AppPermission.usageAccess]);
      expect(
        find.text('Allow app usage'),
        findsOneWidget,
        reason: 'Opening settings does not mean granted',
      );

      // Already agreed: the guide is the one sheet, and Not now still
      // sends nobody to Settings.
      await tester.tap(cardAllow);
      await tester.pumpAndSettle();
      expect(find.text('Turn on Usage access'), findsOneWidget);
      expect(
        find.text('Allow FocusForge to read your app list?'),
        findsNothing,
      );
      await tester.ensureVisible(find.text('Not now').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now').last);
      await tester.pumpAndSettle();
      expect(manager.requests, [AppPermission.usageAccess]);
      await tester.tap(cardAllow);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Open settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(manager.requests, [
        AppPermission.usageAccess,
        AppPermission.usageAccess,
      ]);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('Not now hides the usage card until the next launch', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        usageAccessProvider.overrideWith((ref) async => false),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: UsageAccessCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Allow app usage'), findsNothing);
    expect(container.read(usageCardDismissedProvider), isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('signing back in asks again for missing permissions', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channels = [
      MethodChannel('dev.focusforge/shield'),
      MethodChannel('usage_stats'),
      MethodChannel('flutter.baseflow.com/permissions/methods'),
    ];
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => channel.name.contains('permissions') ? 0 : false,
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await store.setBool(StoreKeys.coachSeen, true);
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        usageAccessProvider.overrideWith((ref) async => false),
        appUsageTodayProvider.overrideWith((ref) async => const {}),
      ],
    );
    addTearDown(container.dispose);
    container.read(askPermissionsAfterSignInProvider.notifier).state = true;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: DashboardScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Make room for focus'), findsWidgets);
    expect(find.text('Show app pause screens'), findsOneWidget);
    expect(container.read(askPermissionsAfterSignInProvider), isFalse);
    // Continue closes it and it does not come back on its own.
    await tester.tap(find.text('Continue for now'));
    await tester.pumpAndSettle();
    expect(find.text('Show app pause screens'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
