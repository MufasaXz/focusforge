import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/providers/usage_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/shared/widgets/app_list_disclosure.dart';

/// Play's User Data policy: the installed-app list is read only after an
/// in-app disclosure and an affirmative tap. These pin that order down at the
/// provider, where every screen gets its data, and at the dialog.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('usage_stats');
  final calls = <String>[];
  late LocalStore store;
  late RecordingShieldService engine;

  setUp(() async {
    calls.clear();
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
    engine = RecordingShieldService()
      ..launchableSet = const {'com.example.game'};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return switch (call.method) {
            'queryInstalledApps' => [
              {
                'packageName': 'com.example.game',
                'appName': 'Game',
                'isSystemApp': 'false',
              },
            ],
            'queryEvents' => <Object>[],
            _ => null,
          };
        });
  });

  tearDown(() {
    engine.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        shieldServiceProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('nothing reads the app list or usage before consent', () async {
    final c = container();
    expect(c.read(appListConsentProvider), isFalse);
    expect(await c.read(installedAppsProvider.future), isEmpty);
    expect(await c.read(launchablePackagesProvider.future), isEmpty);
    expect(await c.read(appUsageTodayProvider.future), isEmpty);
    expect(calls, isEmpty, reason: 'the platform must not even be asked');
  });

  test('consent is remembered and only then is the list read', () async {
    final c = container();
    await c.read(appListConsentProvider.notifier).set(true);
    expect(store.getBool(StoreKeys.appListConsent), isTrue);
    final apps = await c.read(installedAppsProvider.future);
    expect(apps.single.packageId, 'com.example.game');
    expect(await c.read(launchablePackagesProvider.future), {
      'com.example.game',
    });
    expect(calls, contains('queryInstalledApps'));

    await c.read(appListConsentProvider.notifier).set(false);
    expect(store.getBool(StoreKeys.appListConsent), isFalse);
    expect(await c.read(installedAppsProvider.future), isEmpty);
  });

  Future<bool?> openDialog(WidgetTester tester, ProviderContainer c) async {
    bool? answer;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () async =>
                  answer = await confirmAppListAccess(context, ref),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return answer;
  }

  testWidgets('the dialog says what is read, why, and that it stays local', (
    tester,
  ) async {
    final c = container();
    await openDialog(tester, c);
    expect(
      find.text('Allow FocusForge to read your app list?'),
      findsOneWidget,
    );
    expect(find.textContaining('list of apps installed'), findsOneWidget);
    expect(find.textContaining('to let you choose apps to block'), findsOne);
    expect(find.textContaining('does not upload'), findsOneWidget);
  });

  testWidgets('tapping outside or pressing Back is not consent', (
    tester,
  ) async {
    final c = container();
    await openDialog(tester, c);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(
      find.text('Allow FocusForge to read your app list?'),
      findsOneWidget,
      reason: 'the barrier does not dismiss it',
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Allow FocusForge to read your app list?'), findsNothing);
    expect(c.read(appListConsentProvider), isFalse);
    expect(calls, isEmpty);
  });

  testWidgets('Not now leaves consent off; Agree turns it on', (tester) async {
    final c = container();
    await openDialog(tester, c);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(c.read(appListConsentProvider), isFalse);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agree'));
    await tester.pumpAndSettle();
    expect(c.read(appListConsentProvider), isTrue);
    expect(store.getBool(StoreKeys.appListConsent), isTrue);
  });

  testWidgets('the Shield card asks inline and Agree grants', (tester) async {
    final c = container();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: SingleChildScrollView(child: AppListDisclosureCard()),
          ),
        ),
      ),
    );
    expect(find.textContaining('does not upload'), findsOneWidget);
    await tester.tap(find.text('Agree'));
    await tester.pumpAndSettle();
    expect(c.read(appListConsentProvider), isTrue);
  });
}
