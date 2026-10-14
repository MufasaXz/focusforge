import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/services/auth_service.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/features/onboarding/auth_screen.dart';
import 'package:focusforge/features/settings/privacy_screen.dart';

class _Browser extends UrlLauncherPlatform {
  final urls = <String>[];
  bool opens = true;
  @override
  LinkDelegate? get linkDelegate => null;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    urls.add(url);
    return opens;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late _Browser browser;
  late UrlLauncherPlatform original;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        authServiceProvider.overrideWithValue(LocalAuthService(store)),
      ],
    );
    original = UrlLauncherPlatform.instance;
    browser = _Browser();
    UrlLauncherPlatform.instance = browser;
  });
  tearDown(() {
    container.dispose();
    UrlLauncherPlatform.instance = original;
  });

  Future<void> mount(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.light(), home: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('privacy policy opens the public policy in the browser', (
    tester,
  ) async {
    await mount(tester, const PrivacyScreen());
    await tester.scrollUntilVisible(find.text('Privacy policy'), 250);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Privacy policy'));
    await tester.pumpAndSettle();
    expect(browser.urls, ['https://focusforgeorg.vercel.app/privacy']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account creation offers the policy before sign-in', (
    tester,
  ) async {
    await mount(tester, const AuthScreen());
    await tester.scrollUntilVisible(find.text('Privacy policy'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Privacy policy'));
    await tester.pumpAndSettle();
    expect(browser.urls, ['https://focusforgeorg.vercel.app/privacy']);
  });

  testWidgets('failed browser opening copies a usable policy link', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    browser.opens = false;
    await mount(tester, const PrivacyScreen());
    await tester.scrollUntilVisible(find.text('Privacy policy'), 250);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Privacy policy'));
    await tester.pumpAndSettle();
    expect(copied, 'https://focusforgeorg.vercel.app/privacy');
    expect(
      find.text(
        'Could not open a browser. Link copied; paste it into your browser.',
      ),
      findsOneWidget,
    );
  });
}
