import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
    'Home places optional usage card after session start at enlarged text',
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
      final start = find.text('Start session');
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
      expect(find.text('Allow app usage'), findsOneWidget);
      expect(manager.requests, isEmpty);
      await tester.tap(find.text('Allow app usage'));
      await tester.pumpAndSettle();
      expect(find.textContaining('stays on this device'), findsWidgets);
      expect(find.textContaining('messages'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(manager.requests, isEmpty);
      await tester.tap(find.text('Allow app usage'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open usage settings'));
      await tester.pumpAndSettle();
      expect(manager.requests, [AppPermission.usageAccess]);
      expect(
        find.text('Allow app usage'),
        findsOneWidget,
        reason: 'Opening settings does not mean granted',
      );
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
