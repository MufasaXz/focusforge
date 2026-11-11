// Design-review captures of the screens the redesign touches, with fictional
// local data and real shadows.
// Run: flutter test tool/capture_redesign_test.dart
// Writes PNGs to build/redesign; never changes a user's stored data.
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
import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/focus_goal.dart';
import 'package:focusforge/core/models/study.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/goal_planner_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/providers/social_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/providers/usage_providers.dart';
import 'package:focusforge/core/providers/usage_stats_providers.dart';
import 'package:focusforge/core/services/app_catalog.dart';
import 'package:focusforge/core/services/leaderboard_service.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/core/models/shield.dart';
import 'package:focusforge/features/dashboard/usage_stats.dart';
import 'package:focusforge/shared/widgets/app_segmented_control.dart';
import 'package:focusforge/features/focus/fullscreen_clock.dart';

class _Board implements LeaderboardService {
  const _Board(this.rows);
  final List<BoardRow> rows;
  @override
  bool get available => true;
  @override
  String? get uid => 'me';
  @override
  Future<void> publish({
    required String week,
    required String uid,
    required String name,
    required int minutes,
    required int level,
    String? avatarPhoto,
    String? avatarIcon,
    int? avatarColor,
  }) async {}
  @override
  Stream<List<BoardRow>> watch(String week, {int limit = 100}) =>
      Stream.value(rows);
  @override
  Future<void> withdraw(String week, String uid) async {}
  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture the redesigned screens', (tester) async {
    debugDisableShadows = false;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    // Store screenshots: room for a status bar and gesture bar, rendered big.
    if (_storeScale != null) {
      tester.view.padding = const FakeViewPadding(top: 40, bottom: 20);
    }
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
    // The capture harness is a test kept outside the default suite.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await store.setBool(StoreKeys.coachSeen, true);
    final engine = RecordingShieldService();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Screen time: a fixed week of fictional app use.
    Map<String, int> usageFor(DateTime day) {
      final i = day.weekday;
      if (day.isAfter(today)) return const {};
      if (_storeScale != null) {
        return {
          'com.instagram.android': 35 + i * 8,
          'com.google.android.youtube': 20 + (i * 11) % 40,
          'com.whatsapp': 25 + (i * 7) % 20,
          'com.snapchat.android': 10 + i * 4,
        };
      }
      return {
        'com.example.social': 40 + i * 9,
        'com.example.video': 25 + (i * 13) % 50,
        'com.example.reader': 30 + (i * 7) % 30,
        'com.example.notes': 12 + i * 3,
      };
    }

    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        shieldServiceProvider.overrideWithValue(engine),
        appListConsentProvider.overrideWith(() => AppListConsentNotifier(true)),
        installedAppsProvider.overrideWith(
          (ref) async => _storeScale != null ? _storeApps : _reviewApps,
        ),
        appUsageTodayProvider.overrideWith((ref) async => usageFor(today)),
        dayUsageProvider.overrideWith((ref, day) async => usageFor(day)),
        usageAccessProvider.overrideWith((ref) async => true),
        shieldEnabledProvider.overrideWith((ref) async => true),
        overlayAccessProvider.overrideWith((ref) async => true),
        appBlockingRunningProvider.overrideWith((ref) async => true),
        appBlockingPausedProvider.overrideWith((ref) async => false),
        accountUidProvider.overrideWith((ref) => 'me'),
        leaderboardServiceProvider.overrideWith(
          (ref) => const _Board([
            BoardRow(uid: 'a', name: 'Priya Sharma', minutes: 1460, level: 14),
            BoardRow(uid: 'b', name: 'Leo Martin', minutes: 1215, level: 11),
            BoardRow(uid: 'me', name: 'Alex Morgan', minutes: 1090, level: 9),
            BoardRow(uid: 'c', name: 'Mei Chen', minutes: 860, level: 8),
            BoardRow(uid: 'd', name: 'Omar Haddad', minutes: 610, level: 6),
            BoardRow(uid: 'e', name: 'Sofia Rossi', minutes: 395, level: 4),
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
            uid: 'me',
            displayName: 'Alex Morgan',
            onboardingComplete: true,
            isAnonymous: false,
          ),
        );
    container.read(subjectsProvider.notifier).hydrate([
      for (final (id, name, icon, color) in [
        ('math', 'Mathematics', 'calculate', SubjectPalette.math),
        ('physics', 'Physics', 'science', SubjectPalette.physics),
        if (_storeScale != null)
          ('chem', 'Chemistry', 'science', SubjectPalette.chemistry)
        else ...[
          ('english', 'English', 'translate', SubjectPalette.english),
          ('history', 'History', 'history_edu', SubjectPalette.history),
        ],
      ])
        Subject(
          id: id,
          name: name,
          icon: Icons.menu_book_rounded,
          color: color,
          weekTarget: 6,
        ).toJson()..['icon'] = icon,
    ]);
    final monday = DateTime(
      today.year,
      today.month,
      today.day - today.weekday + 1,
    );
    final plan = _storeScale != null
        ? _storePlan
        : <(int, String, int)>[
            (0, 'math', 50),
            (0, 'physics', 25),
            (0, 'english', 25),
            (1, 'math', 25),
            (1, 'history', 50),
            (2, 'physics', 50),
            (2, 'math', 50),
            (2, 'english', 25),
            (3, 'math', 25),
            (3, 'physics', 25),
            (4, 'english', 50),
            (4, 'math', 50),
            (5, 'history', 25),
            (5, 'math', 25),
            (6, 'physics', 50),
          ];
    final sessions = [
      for (final (i, (day, subject, minutes)) in plan.indexed)
        if (!DateTime(
          monday.year,
          monday.month,
          monday.day + day,
        ).isAfter(today))
          FocusSession(
            id: 'review-$i',
            subjectId: subject,
            startedAt: DateTime(
              monday.year,
              monday.month,
              monday.day + day,
              8 + i % 5,
            ),
            minutes: minutes,
          ),
    ];
    container
        .read(sessionsProvider.notifier)
        .hydrate(sessions.map((session) => session.toJson()).toList());
    if (_storeScale != null) {
      // A Shield with real work in it: two apps blocked, one for focus only.
      final shield = container.read(whitelistProvider.notifier);
      for (final (id, name, tier) in [
        ('com.instagram.android', 'Instagram', WhitelistTier.blocked),
        ('com.snapchat.android', 'Snapchat', WhitelistTier.blocked),
        ('com.google.android.youtube', 'YouTube', WhitelistTier.focusOnly),
      ]) {
        await shield.addInstalledApp(packageId: id, name: name, tier: tier);
      }
    }
    container
        .read(statsProvider.notifier)
        .hydrate(
          GamificationStats.fromJson({
            'xp': 0,
            'level': 1,
            'totalFocusHours': 41.5,
            'totalSessions': 64,
          }).withXp(2350),
        );
    await container
        .read(focusGoalPlannerProvider.notifier)
        .save(
          FocusGoalPlan(
            scope: FocusGoalScope.day,
            date: today,
            totalMinutes: 180,
            subjectMinutes: const {},
          ),
        );
    container.read(timerProvider.notifier).setSubject('math');

    final boundary = GlobalKey();
    Widget scope(Widget child) => UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(key: boundary, child: child),
    );
    final only = Platform.environment['CAPTURE_ONLY'];
    Future<void> capture(String name) async {
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      if (only != null && !name.startsWith(only)) return;
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: _storeScale ?? 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/redesign/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    final themes = <String, (ThemePreference, bool)>{
      'light': (ThemePreference.light, false),
      'dark': (ThemePreference.dark, false),
      'amoled': (ThemePreference.dark, true),
    };
    for (final MapEntry(key: label, value: (mode, amoled)) in themes.entries) {
      await container.read(themeSettingsProvider.notifier).setMode(mode);
      await container.read(themeSettingsProvider.notifier).setAmoled(amoled);
      await tester.pumpWidget(scope(const FocusForgeApp()));
      for (final route in [
        'dashboard',
        'profile',
        'profile/leaderboard',
        'focus',
        'shield',
      ]) {
        container.read(routerProvider).go('/$route');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        for (final state in tester.stateList<ScrollableState>(
          find.byType(Scrollable),
        )) {
          if (state.position.axis == Axis.vertical) state.position.jumpTo(0);
        }
        final name = route.replaceAll('/', '-');
        await capture('$name-$label');
        if (_storeScale != null && route == 'shield') {
          // The YouTube page shows Shorts blocked; the Apps page is shot first
          // so its summary card stays short.
          container
              .read(youtubeRulesProvider.notifier)
              .hydrate(const YoutubeRules(shorts: true).toJson());
          await tester.tap(
            find.descendant(
              of: find.byWidgetPredicate((w) => w is AppSegmentedControl),
              matching: find.text('YouTube'),
            ),
          );
          await tester.pump(const Duration(milliseconds: 400));
          await capture('shield-youtube-$label');
          container
              .read(youtubeRulesProvider.notifier)
              .hydrate(YoutubeRules.off.toJson());
        }
        if (_storeScale != null && route == 'dashboard') {
          await tester.ensureVisible(find.text('This week').first);
          final week = find.text('This week').first;
          await Scrollable.ensureVisible(tester.element(week), alignment: 0.04);
          await tester.pump(const Duration(milliseconds: 400));
          await capture('dashboard-week-$label');
        }
        if (route == 'dashboard') {
          final list = find.byType(Scrollable).first;
          final state = tester.state<ScrollableState>(list);
          state.position.jumpTo(state.position.maxScrollExtent);
          await capture('$name-bottom-$label');
        }
      }
      final theme = mode == ThemePreference.light
          ? AppTheme.light()
          : AppTheme.dark(amoled: amoled);
      await tester.pumpWidget(
        scope(MaterialApp(theme: theme, home: const FullscreenClock())),
      );
      await capture('fullscreen-$label');
      await tester.pumpWidget(
        scope(MaterialApp(theme: theme, home: const UsageStatsScreen())),
      );
      await capture('usage-$label');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    debugDisableShadows = true;
  });
}

/// Set CAPTURE_SCALE (for example 3) to render store-listing screenshots.
final double? _storeScale = double.tryParse(
  Platform.environment['CAPTURE_SCALE'] ?? '',
);

const _reviewApps = [
  InstalledApp(
    packageId: 'com.example.social',
    name: 'Social',
    isSystem: false,
  ),
  InstalledApp(packageId: 'com.example.video', name: 'Video', isSystem: false),
  InstalledApp(
    packageId: 'com.example.reader',
    name: 'Reader',
    isSystem: false,
  ),
  InstalledApp(packageId: 'com.example.notes', name: 'Notes', isSystem: false),
];

/// Store screenshots show the apps students actually ask to block.
const _storeApps = [
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
  InstalledApp(packageId: 'com.whatsapp', name: 'WhatsApp', isSystem: false),
  InstalledApp(
    packageId: 'com.snapchat.android',
    name: 'Snapchat',
    isSystem: false,
  ),
];

/// A full student week in three subjects: (day from Monday, subject, minutes).
const _storePlan = <(int, String, int)>[
  (0, 'math', 75),
  (0, 'physics', 50),
  (0, 'chem', 45),
  (1, 'physics', 90),
  (1, 'math', 50),
  (1, 'chem', 25),
  (2, 'chem', 75),
  (2, 'math', 75),
  (2, 'physics', 25),
  (3, 'math', 100),
  (3, 'physics', 45),
  (3, 'chem', 40),
  (4, 'physics', 60),
  (4, 'chem', 50),
  (4, 'math', 50),
  (5, 'math', 50),
  (5, 'chem', 50),
  (6, 'physics', 40),
  (6, 'math', 25),
];
