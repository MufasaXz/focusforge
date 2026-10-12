// Independent compact-screen probes for permission lifecycle states.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/models/study.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/providers/usage_providers.dart';
import 'package:focusforge/core/services/app_catalog.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/features/dashboard/dashboard_screen.dart';
import 'package:focusforge/features/focus/focus_screen.dart';
import 'package:focusforge/features/profile/profile_screen.dart';
import 'package:focusforge/features/shield/shield_screen.dart';
import 'package:focusforge/features/onboarding/permissions_step.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
  const shield = MethodChannel('dev.focusforge/shield');
  const usage = MethodChannel('usage_stats');
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');

  for (final scale in [2.0, 3.0]) {
    for (final page in <String, Widget>{
      'dashboard': const DashboardScreen(),
      'shield': const ShieldScreen(),
      'focus': const FocusScreen(),
      'profile': const ProfileScreen(),
    }.entries) {
      testWidgets('${page.key} full scroll at 320dp/DPR3, text $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(960, 1920);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        SharedPreferences.setMockInitialValues({});
        final store = await LocalStore.open();
        await store.setBool(StoreKeys.coachSeen, true);
        final engine = RecordingShieldService();
        addTearDown(engine.dispose);
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
                InstalledApp(
                  packageId: 'com.google.android.youtube',
                  name: 'YouTube',
                  isSystem: false,
                ),
              ],
            ),
            appUsageTodayProvider.overrideWith((ref) async => const {}),
            usageAccessProvider.overrideWith((ref) async => false),
            shieldEnabledProvider.overrideWith((ref) async => false),
          ],
        );
        addTearDown(container.dispose);
        container
            .read(userProvider.notifier)
            .hydrate(
              const UserProfile(
                displayName: 'Alexandria Morgan Rivera',
                onboardingComplete: true,
              ),
            );
        container.read(sessionsProvider.notifier).hydrate([
          FocusSession(
            id: 'density',
            subjectId: 'math',
            startedAt: DateTime.now(),
            minutes: 25,
          ).toJson(),
        ]);
        container
            .read(statsProvider.notifier)
            .hydrate(
              const GamificationStats(
                xp: 650,
                level: 3,
                totalFocusHours: 123.5,
                totalSessions: 120,
              ),
            );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.dark(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: TextScaler.linear(scale),
                ),
                child: child!,
              ),
              home: Scaffold(body: page.value),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (var step = 0; step < 40; step++) {
          final vertical = tester
              .stateList<ScrollableState>(find.byType(Scrollable))
              .where(
                (state) =>
                    state.position.axis == Axis.vertical &&
                    state.position.hasContentDimensions,
              )
              .toList();
          if (vertical.isEmpty) break;
          final position = vertical.first.position;
          if (position.pixels >= position.maxScrollExtent) break;
          position.jumpTo(
            (position.pixels + 450).clamp(0, position.maxScrollExtent),
          );
          final errors = <FlutterErrorDetails>[];
          final originalErrorHandler = FlutterError.onError;
          FlutterError.onError = (details) {
            errors.add(details);
            originalErrorHandler?.call(details);
          };
          await tester.pumpAndSettle();
          FlutterError.onError = originalErrorHandler;
          if (errors.isNotEmpty) {
            for (final details in errors) {
              // ignore: avoid_print
              print(details.toString());
            }
          }
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  for (final scale in [2.0, 3.0]) {
    testWidgets('permanent permission refusal at 320dp, text $scale', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        tester.view.physicalSize = const Size(960, 1920);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        for (final channel in [shield, usage, permissions]) {
          messenger.setMockMethodCallHandler(
            channel,
            (call) async => channel == permissions ? 4 : false,
          );
          addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        }
        SharedPreferences.setMockInitialValues({});
        final store = await LocalStore.open();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [localStoreProvider.overrideWithValue(store)],
            child: MaterialApp(
              theme: AppTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: TextScaler.linear(scale),
                ),
                child: child!,
              ),
              home: Scaffold(body: PermissionsStep(onNext: () {})),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Keep your timer in view'),
          180,
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Open Settings').first, 180);
        await tester.pumpAndSettle();
        expect(find.text('Open Settings').first.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('settings waiting state at 320dp, text 2', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final channel in [shield, usage, permissions]) {
        messenger.setMockMethodCallHandler(
          channel,
          (call) async => channel == permissions ? 0 : false,
        );
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      }
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [localStoreProvider.overrideWithValue(store)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: TextScaler.linear(2),
              ),
              child: child!,
            ),
            home: Scaffold(body: PermissionsStep(onNext: () {})),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final usageCard = find
          .ancestor(
            of: find.text('Understand your screen time'),
            matching: find.byType(Padding),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Understand your screen time'),
        180,
      );
      await tester.pumpAndSettle();
      final enable = find.descendant(
        of: usageCard,
        matching: find.text('Enable'),
      );
      await tester.scrollUntilVisible(enable, 180);
      await tester.pumpAndSettle();
      await tester.tap(enable);
      await tester.pumpAndSettle();
      expect(
        find.text('Waiting for you to turn it on in Settings'),
        findsOneWidget,
      );
      expect(find.text('Open again'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
