// README screenshots and Focus motion, using bundled fonts and fictional data.
// Run: flutter test tool/capture_readme_test.dart
// Writes PNGs to build/readme-captures; never changes a user's stored data.
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
import 'package:focusforge/core/models/study.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/providers/usage_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/core/models/shield.dart';
import 'package:focusforge/core/models/social.dart';
import 'package:focusforge/core/providers/social_providers.dart';
import 'package:focusforge/core/services/app_catalog.dart';
import 'package:focusforge/core/services/leaderboard_service.dart';
import 'package:focusforge/core/services/study_group_service.dart';

class _ReadmeGroups extends UnavailableStudyGroupService {
  const _ReadmeGroups();
  @override
  bool get available => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture four current screens and focus motion', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Widget tests do not load app fonts automatically. Include the icon font
    // as well as text fonts, otherwise Material icons become missing-glyph boxes.
    final fontManifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in fontManifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
    // The capture harness is a test kept outside the default suite.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await store.setBool(StoreKeys.coachSeen, true);
    final engine = RecordingShieldService();
    final now = DateTime.now();
    final group = StudyGroup(
      id: 'readme-circle',
      name: 'The quiet corner',
      icon: Icons.groups_rounded,
      targetHours: 20,
      createdAt: now,
      inviteCode: 'STUDY23456',
      ownerUid: 'alex',
      memberIds: const ['alex', 'riley', 'maya'],
    );
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        shieldServiceProvider.overrideWithValue(engine),
        installedAppsProvider.overrideWith(
          (ref) async => const [
            InstalledApp(
              packageId: 'com.google.android.youtube',
              name: 'YouTube',
              isSystem: false,
            ),
            InstalledApp(
              packageId: 'com.instagram.android',
              name: 'Instagram',
              isSystem: false,
            ),
            InstalledApp(
              packageId: 'com.reddit.frontpage',
              name: 'Reddit',
              isSystem: false,
            ),
          ],
        ),
        appUsageTodayProvider.overrideWith(
          (ref) async => const {
            'com.google.android.youtube': 20,
            'com.instagram.android': 12,
            'com.reddit.frontpage': 5,
          },
        ),
        usageAccessProvider.overrideWith((ref) async => true),
        // Do not claim Android accessibility access in a widget capture.
        shieldEnabledProvider.overrideWith((ref) async => false),
        studyGroupServiceProvider.overrideWithValue(const _ReadmeGroups()),
        cloudGroupsProvider.overrideWith((ref) => Stream.value([group])),
        groupClockProvider.overrideWith((ref) => Stream.value(now)),
        groupMembersProvider('readme-circle').overrideWith(
          (ref) => Stream.value([
            GroupMember(
              uid: 'alex',
              name: 'Alex Morgan',
              week: weekKey(now.toUtc()),
              minutes: 180,
            ),
            GroupMember(
              uid: 'riley',
              name: 'Riley Chen',
              week: weekKey(now.toUtc()),
              minutes: 240,
              focusUntil: now.add(const Duration(minutes: 20)),
            ),
            GroupMember(
              uid: 'maya',
              name: 'Maya Patel',
              week: weekKey(now.toUtc()),
              minutes: 150,
            ),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(engine.dispose);
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

    container.read(timerProvider.notifier).setSubject('math');
    container.read(dailyGoalProvider.notifier).hydrate(120, null);
    container.read(whitelistProvider.notifier).hydrate([
      {
        'id': 'instagram',
        'name': 'Instagram',
        'icon': 'instagram',
        'tier': WhitelistTier.blocked.index,
        'packageId': 'com.instagram.android',
      },
      {
        'id': 'reddit',
        'name': 'Reddit',
        'icon': 'reddit',
        'tier': WhitelistTier.budgeted.index,
        'packageId': 'com.reddit.frontpage',
        'budgetMinutes': 15,
      },
    ]);
    final boundary = GlobalKey();
    Widget scope(Widget child) => UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(key: boundary, child: child),
    );
    Future<void> capture(String name) async {
      expect(tester.takeException(), isNull);
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/readme-captures/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await container
        .read(themeSettingsProvider.notifier)
        .setMode(ThemePreference.dark);
    await tester.pumpWidget(scope(const FocusForgeApp()));
    Future<void> route(String path) async {
      container.read(routerProvider).go(path);
      await tester.pump();
      await tester.pumpAndSettle();
    }

    await route('/dashboard');
    await capture('01-dashboard');
    await route('/shield');
    await capture('02-shield');
    await route('/focus');
    await capture('03-focus');
    // Capture the real press/release transition. Test pumps do not advance
    // DateTime.now, so this animation demonstrates the control rather than
    // fabricating an accelerated focus session.
    await capture('focus-frames/000');
    final start = find.text('Start');
    expect(start.hitTestable(), findsOneWidget);
    final press = await tester.startGesture(tester.getCenter(start));
    for (var frame = 1; frame <= 3; frame++) {
      await tester.pump(const Duration(milliseconds: 83));
      await capture('focus-frames/${frame.toString().padLeft(3, '0')}');
    }
    await press.up();
    for (var frame = 4; frame <= 18; frame++) {
      await tester.pump(const Duration(milliseconds: 83));
      await capture('focus-frames/${frame.toString().padLeft(3, '0')}');
    }
    expect(find.text('Pause'), findsOneWidget);
    container.read(timerProvider.notifier).pause();
    await tester.pump();
    await tester.pumpAndSettle();
    await route('/profile/groups');
    await tester.ensureVisible(find.text('The quiet corner'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('The quiet corner'));
    await tester.pumpAndSettle();
    await capture('04-groups');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
