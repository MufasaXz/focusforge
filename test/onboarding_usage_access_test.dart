import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/usage_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/permission_manager.dart';
import 'package:focusforge/features/onboarding/usage_access_step.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore store;
  late ProviderContainer container;
  final calls = <String>[];
  const channel = MethodChannel('usage_stats');

  setUp(() async {
    calls.clear();
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
    container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return call.method == 'isUsagePermission' ? false : null;
        });
  });

  tearDown(() {
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Widget wrap(Widget child) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: child),
    ),
  );

  testWidgets(
    'the setup step is a checklist that never asks for Accessibility',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        expect(
          const PermissionManager().supports(AppPermission.usageAccess),
          isTrue,
        );
        await tester.pumpWidget(wrap(UsageAccessStep(onNext: () {})));
        await tester.pumpAndSettle();
        expect(find.text('Limit distracting apps'), findsOneWidget);
        expect(find.text('Usage access'), findsOneWidget);
        expect(find.text('Display over other apps'), findsOneWidget);
        expect(find.text('Notifications'), findsOneWidget);
        // One row at a time: only the first carries a button.
        expect(find.text('Allow'), findsOneWidget);
        expect(find.text('Continue without app blocking'), findsOneWidget);
        expect(find.textContaining('Accessibility'), findsNothing);
        expect(calls, isNot(contains('queryInstalledApps')));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('Continue without app blocking moves on with nothing agreed', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      var continued = false;
      await tester.pumpWidget(
        wrap(UsageAccessStep(onNext: () => continued = true)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue without app blocking'));
      await tester.pumpAndSettle();
      expect(continued, isTrue);
      expect(container.read(appListConsentProvider), isFalse);
      expect(calls, isNot(contains('openUsageAccessSettings')));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Allow shows the disclosure, then the guide, then settings', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      var consentWhenOpened = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'openUsageAccessSettings') {
              consentWhenOpened = container.read(appListConsentProvider);
            }
            return call.method == 'isUsagePermission' ? false : null;
          });
      await tester.pumpWidget(wrap(UsageAccessStep(onNext: () {})));
      await tester.pumpAndSettle();

      // Not now on the disclosure: nothing agreed, nothing opened.
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();
      expect(
        find.text('Allow FocusForge to read your app list?'),
        findsOneWidget,
      );
      expect(find.textContaining('never uploaded or shared'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(container.read(appListConsentProvider), isFalse);
      expect(calls, isNot(contains('openUsageAccessSettings')));

      // Agree, read the guide, open settings.
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agree'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Turn on Permit usage access'), findsOneWidget);
      expect(calls, isNot(contains('openUsageAccessSettings')));
      await tester.ensureVisible(find.text('Open settings'));
      await tester.pump();
      await tester.tap(find.text('Open settings'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(calls, contains('openUsageAccessSettings'));
      expect(consentWhenOpened, isTrue, reason: 'agreement comes first');
      expect(store.getBool(StoreKeys.appListConsent), isTrue);
      // Not yet switched on in Android: the row still offers Allow.
      expect(find.text('Allow'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
