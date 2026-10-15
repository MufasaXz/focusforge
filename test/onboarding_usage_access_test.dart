import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/permission_manager.dart';
import 'package:focusforge/features/onboarding/usage_access_step.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
  });

  Widget wrap(Widget child) => ProviderScope(
    overrides: [localStoreProvider.overrideWithValue(store)],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: child),
    ),
  );

  testWidgets('explains optional usage access without background language', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(const PermissionManager().supports(AppPermission.usageAccess), isTrue);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('usage_stats'), (
      call,
    ) async {
      if (call.method == 'checkUsagePermission') return false;
      return null;
    });
    try {
      await tester.pumpWidget(wrap(UsageAccessStep(onNext: () {})));
      await tester.pumpAndSettle();

      expect(find.text('See your real screen time'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Allow usage access'), 220);
      await tester.pumpAndSettle();
      expect(find.text('Allow usage access'), findsOneWidget);
      expect(find.text('Continue without access'), findsOneWidget);
      expect(find.textContaining('selected apps'), findsOneWidget);
      expect(find.textContaining('background'), findsNothing);
      expect(find.textContaining('Accessibility'), findsNothing);
      expect(find.textContaining('Draw over'), findsNothing);
    } finally {
      messenger.setMockMethodCallHandler(
        const MethodChannel('usage_stats'),
        null,
      );
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('usage access setup can be skipped', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('usage_stats'),
      (call) async => false,
    );
    try {
      var continued = false;
      await tester.pumpWidget(
        wrap(UsageAccessStep(onNext: () => continued = true)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue without access'));
      await tester.pumpAndSettle();
      expect(continued, isTrue);
    } finally {
      messenger.setMockMethodCallHandler(
        const MethodChannel('usage_stats'),
        null,
      );
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
