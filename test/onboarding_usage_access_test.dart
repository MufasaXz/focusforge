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

  testWidgets('the setup step is the app-list disclosure, in normal use', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      expect(
        const PermissionManager().supports(AppPermission.usageAccess),
        isTrue,
      );
      await tester.pumpWidget(wrap(UsageAccessStep(onNext: () {})));
      await tester.pumpAndSettle();

      expect(find.text('Limit distracting apps'), findsOneWidget);
      // What is read, for which feature, and where it goes — before any
      // button that could grant it.
      expect(find.textContaining('list of apps installed'), findsOneWidget);
      expect(find.textContaining('to let you choose apps to block'), findsOne);
      expect(find.textContaining('Never uploaded'), findsOneWidget);
      expect(find.text('Agree and allow'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      // Only this access is asked about here; the others are explained where
      // their features are turned on.
      expect(find.textContaining('Accessibility'), findsNothing);
      expect(find.textContaining('Draw over'), findsNothing);
      expect(calls, isNot(contains('queryInstalledApps')));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Not now moves on with nothing agreed and nothing opened', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      var continued = false;
      await tester.pumpWidget(
        wrap(UsageAccessStep(onNext: () => continued = true)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(continued, isTrue);
      expect(container.read(appListConsentProvider), isFalse);
      expect(calls, isNot(contains('openUsageAccessSettings')));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Agree and allow records consent before opening settings', (
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
      await tester.tap(find.text('Agree and allow'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(calls, contains('openUsageAccessSettings'));
      expect(consentWhenOpened, isTrue, reason: 'agreement comes first');
      expect(store.getBool(StoreKeys.appListConsent), isTrue);
      // Agreed but not yet switched on in Android: the step says what is
      // left instead of claiming access, and still offers a way past.
      expect(find.text('Allow usage access'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
