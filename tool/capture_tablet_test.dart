// Actual tablet UI with fictional data. Run: flutter test tool/capture_tablet_test.dart
import 'dart:convert';
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
import 'package:focusforge/core/services/app_catalog.dart';
import 'package:focusforge/core/models/focus_goal.dart';
import 'package:focusforge/core/models/study.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/goal_planner_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/providers/social_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/providers/usage_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/core/services/leaderboard_service.dart';

class _ReviewBoard extends UnavailableLeaderboardService {
  const _ReviewBoard();
  @override
  bool get available => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('review Home, navigation and leaderboard in both themes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await store.setBool(StoreKeys.coachSeen, true);
    final engine = RecordingShieldService();
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        shieldServiceProvider.overrideWithValue(engine),
        installedAppsProvider.overrideWith(
          (ref) async => const [
            InstalledApp(
              packageId: 'com.example.social',
              name: 'Social',
              isSystem: false,
            ),
            InstalledApp(
              packageId: 'com.example.video',
              name: 'Video',
              isSystem: false,
            ),
            InstalledApp(
              packageId: 'com.example.games',
              name: 'Games',
              isSystem: false,
            ),
          ],
        ),
        appUsageTodayProvider.overrideWith((ref) async => const {}),
        usageAccessProvider.overrideWith((ref) async => true),
        shieldEnabledProvider.overrideWith((ref) async => false),
        leaderboardServiceProvider.overrideWithValue(const _ReviewBoard()),
        weekBoardProvider.overrideWith(
          (ref) => Stream.value(const [
            BoardRow(uid: 'riley', name: 'Riley Chen', minutes: 540, level: 12),
            BoardRow(uid: 'alex', name: 'Alex Morgan', minutes: 390, level: 7),
            BoardRow(uid: 'maya', name: 'Maya Patel', minutes: 310, level: 5),
            BoardRow(uid: 'sam', name: 'Sam Rivera', minutes: 240),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(engine.dispose);
    await container.read(youtubeRulesProvider.notifier).setShorts(true);
    await container.read(youtubeRulesProvider.notifier).setFeed(true);
    container.read(clockFaceProvider.notifier).hydrate('minimal');
    container.read(timerProvider.notifier).setSubject('math');
    await container
        .read(whitelistProvider.notifier)
        .addInstalledApp(packageId: 'com.example.social', name: 'Social');
    await container
        .read(whitelistProvider.notifier)
        .addInstalledApp(packageId: 'com.example.video', name: 'Video');
    container
        .read(userProvider.notifier)
        .hydrate(
          const UserProfile(
            uid: 'alex',
            isAnonymous: false,
            displayName: 'Alex Morgan',
            onboardingComplete: true,
          ),
        );
    container.read(boardOptInProvider.notifier).hydrate(true);
    container.read(subjectsProvider.notifier).hydrate([
      const Subject(
        id: 'math',
        name: 'Mathematics',
        icon: Icons.calculate_outlined,
        color: Colors.blue,
      ).toJson(),
      const Subject(
        id: 'physics',
        name: 'Physics',
        icon: Icons.science_outlined,
        color: Colors.teal,
      ).toJson(),
    ]);
    final now = DateTime.now();
    container.read(sessionsProvider.notifier).hydrate([
      for (var day = 0; day < 5; day++)
        FocusSession(
          id: 'review-$day',
          subjectId: day.isEven ? 'math' : 'physics',
          startedAt: now.subtract(Duration(days: day)),
          minutes: day == 0 ? 60 : 45,
        ).toJson(),
    ]);
    container
        .read(statsProvider.notifier)
        .hydrate(
          const GamificationStats(
            level: 7,
            xp: 600,
            totalFocusHours: 24,
            totalSessions: 30,
          ),
        );
    await container
        .read(focusGoalPlannerProvider.notifier)
        .save(
          FocusGoalPlan(
            scope: FocusGoalScope.day,
            date: now,
            totalMinutes: 120,
            subjectMinutes: const {'math': 60, 'physics': 60},
          ),
        );
    final boundary = GlobalKey();
    Widget scope() => UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(key: boundary, child: const FocusForgeApp()),
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
        final file = File('build/tablet-captures/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await container.read(themeSettingsProvider.notifier).setAmoled(false);
    for (final mode in [ThemePreference.light, ThemePreference.dark]) {
      await container.read(themeSettingsProvider.notifier).setMode(mode);
      await tester.pumpWidget(scope());
      for (final route in [
        'dashboard',
        'shield',
        'focus',
        'profile',
        'profile/leaderboard',
      ]) {
        container.read(routerProvider).go('/$route');
        await capture('$route-${mode.name}'.replaceAll('/', '-'));
        if (route == 'shield') {
          await tester.tap(find.text('YouTube'));
          await capture('youtube-${mode.name}');
          await tester.tap(find.text('Apps'));
        }
      }
    }
    tester.view.physicalSize = const Size(800, 1280);
    for (final route in ['dashboard', 'shield', 'focus', 'profile']) {
      container.read(routerProvider).go('/$route');
      await capture('$route-portrait');
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
