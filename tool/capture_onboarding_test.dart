// Reproducible captures of every first-run setup page, header included.
// Run: flutter test tool/capture_onboarding_test.dart
// Writes PNGs to build/ui-review/onboarding; never changes a user's data.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/localization/app_strings.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/features/onboarding/onboarding_flow.dart';
import 'package:focusforge/features/onboarding/usage_access_step.dart';
import 'package:focusforge/shared/widgets/app_list_disclosure.dart';

const _pages = [
  'splash',
  'account',
  'focus',
  'profile',
  'subjects',
  'plan',
  'access',
  'ready',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Bundled fonts once per run: widget tests do not load them, and loading
  // them again in a second test stalls the capture.
  setUpAll(() async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  testWidgets('capture every setup page in both themes', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('usage_stats'),
          (call) async => call.method == 'isUsagePermission' ? false : null,
        );

    for (final dark in [true, false]) {
      // The capture harness is a test kept outside the default suite.
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      final engine = RecordingShieldService();
      final container = ProviderContainer(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          shieldServiceProvider.overrideWithValue(engine),
        ],
      );
      container
          .read(userProvider.notifier)
          .hydrate(const UserProfile(uid: 'review', displayName: 'Alex'));
      final boundary = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              home: const OnboardingFlow(),
            ),
          ),
        ),
      );
      Future<void> capture(String name) async {
        await tester.pump(const Duration(milliseconds: 900));
        await tester.pumpAndSettle();
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/ui-review/onboarding/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.pump(const Duration(milliseconds: 400));
      await capture('${_pages[0]}-${dark ? 'dark' : 'light'}');
      for (var page = 1; page < _pages.length; page++) {
        tester
            .widget<PageView>(find.byType(PageView))
            .controller!
            .jumpToPage(page);
        await capture(
          '${page.toString().padLeft(2, '0')}-${_pages[page]}-'
          '${dark ? 'dark' : 'light'}',
        );
      }
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) => Center(
                    child: TextButton(
                      onPressed: () => confirmAppListAccess(context, ref),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await capture('dialog-${dark ? 'dark' : 'light'}');
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              home: const Scaffold(
                body: SafeArea(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(20),
                    child: AppListDisclosureCard(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await capture('shield-card-${dark ? 'dark' : 'light'}');
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      engine.dispose();
    }
  });

  // The disclosure in a long script and in a right-to-left one: the step has
  // to fit its whole explanation above the button in every bundled language.
  testWidgets('capture the access step in Hindi and Arabic', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('usage_stats'),
          (call) async => call.method == 'isUsagePermission' ? false : null,
        );
    for (final locale in const [Locale('hi'), Locale('ar')]) {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      final container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      final boundary = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(),
              locale: locale,
              supportedLocales: AppStrings.supportedLocales,
              localizationsDelegates: AppStrings.localizationsDelegates,
              home: Scaffold(
                body: SafeArea(child: UsageAccessStep(onNext: () {})),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          'build/ui-review/onboarding/access-${locale.languageCode}.png',
        );
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    }
  });
}
