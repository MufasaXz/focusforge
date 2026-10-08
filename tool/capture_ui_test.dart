// Reproducible UI review captures with bundled fonts and fictional local data.
// Run: flutter test tool/capture_ui_test.dart
// Writes PNGs to build/ui-review; never changes a user's stored data.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/app.dart';
import 'package:focusforge/app/router.dart';
import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/study.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/providers/usage_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/features/onboarding/persona_step.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture the primary screens in both themes', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final family in ['Inter', 'InterDisplay']) {
      final loader = FontLoader(family);
      for (final weight in [
        if (family == 'Inter') ...['Regular', 'Medium'],
        'SemiBold',
        'Bold',
      ]) {
        loader.addFont(rootBundle.load('assets/fonts/$family-$weight.ttf'));
      }
      await loader.load();
    }
    // The capture harness is a test kept outside the default suite.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await store.setBool(StoreKeys.coachSeen, true);
    final engine = RecordingShieldService();
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        shieldServiceProvider.overrideWithValue(engine),
        installedAppsProvider.overrideWith((ref) async => const []),
        appUsageTodayProvider.overrideWith((ref) async => const {}),
        usageAccessProvider.overrideWith((ref) async => false),
        shieldEnabledProvider.overrideWith((ref) async => false),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(engine.dispose);
    container
        .read(userProvider.notifier)
        .hydrate(
          const UserProfile(
            displayName: 'Alex Morgan',
            onboardingComplete: true,
          ),
        );
    final now = DateTime.now();
    final sessions = [
      for (var day = 6; day >= 0; day--)
        for (var block = 0; block < (day % 3) + 2; block++)
          FocusSession(
            id: 'review-$day-$block',
            subjectId: block.isEven ? 'math' : 'physics',
            startedAt: DateTime(now.year, now.month, now.day - day, 9 + block),
            minutes: block.isEven ? 25 : 50,
          ),
    ];
    container
        .read(sessionsProvider.notifier)
        .hydrate(sessions.map((session) => session.toJson()).toList());
    container
        .read(statsProvider.notifier)
        .hydrate(
          GamificationStats(
            xp: 650,
            level: 3,
            totalFocusHours:
                sessions.fold<int>(0, (sum, s) => sum + s.minutes) / 60,
            totalSessions: sessions.length,
          ),
        );

    final boundary = GlobalKey();
    Widget scope(Widget child) => UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(key: boundary, child: child),
    );
    Future<void> capture(String name) async {
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/ui-review/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    for (final mode in [ThemePreference.dark, ThemePreference.light]) {
      await container.read(themeSettingsProvider.notifier).setMode(mode);
      await tester.pumpWidget(scope(const FocusForgeApp()));
      for (final route in ['dashboard', 'shield', 'focus', 'profile']) {
        container.read(routerProvider).go('/$route');
        await capture('$route-${mode.name}');
        if (route == 'profile') {
          await tester.scrollUntilVisible(
            find.text('Tide'),
            180,
            scrollable: find.byType(Scrollable).last,
          );
          await capture('appearance-${mode.name}');
        }
      }
    }
    await tester.pumpWidget(
      scope(
        MaterialApp(
          theme: AppTheme.dark(amoled: true),
          home: Scaffold(
            body: SafeArea(child: PersonaStep(onNext: () {})),
          ),
        ),
      ),
    );
    await capture('setup-dark');
    tester.view.physicalSize = const Size(1280, 900);
    await tester.pumpWidget(scope(const FocusForgeApp()));
    container.read(routerProvider).go('/dashboard');
    await capture('dashboard-tablet');
    container.read(routerProvider).go('/profile');
    await capture('profile-tablet');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
