import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/router.dart';
import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/social.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/providers/social_providers.dart';
import 'package:focusforge/core/providers/usage_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/features/settings/leaderboard_screen.dart';
import 'package:focusforge/shared/widgets/icon_badge.dart';
import 'package:focusforge/features/settings/study_groups_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  var board = <LeaderboardEntry>[];
  var groups = <StudyGroup>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await store.clearAll();
    await store.setBool(StoreKeys.coachSeen, true);
    final engine = RecordingShieldService();
    board = [];
    groups = [];
    container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        shieldServiceProvider.overrideWithValue(engine),
        installedAppsProvider.overrideWith((ref) async => const []),
        appUsageTodayProvider.overrideWith((ref) async => const {}),
        usageAccessProvider.overrideWith((ref) async => false),
        shieldEnabledProvider.overrideWith((ref) async => false),
        leaderboardProvider.overrideWith((ref) => board),
        groupsProvider.overrideWith((ref) => groups),
        // The groups screen ticks a 30 s clock; a fixed time keeps the
        // test from ending with a live timer.
        groupClockProvider.overrideWith(
          (ref) => Stream.value(DateTime(2026, 11, 14, 12)),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(engine.dispose);
  });

  Finder tile(String route) => find.byKey(ValueKey('profile-$route-tile'));

  Future<void> pumpProfile(
    WidgetTester tester, {
    bool anonymous = false,
  }) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container
        .read(userProvider.notifier)
        .hydrate(
          UserProfile(
            uid: 'alex',
            displayName: 'Alex Morgan',
            onboardingComplete: true,
            isAnonymous: anonymous,
          ),
        );
    final router = container.read(routerProvider);
    addTearDown(router.dispose);
    router.goNamed(AppRoutes.profile);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('community tiles sit below the hero and open their routes', (
    tester,
  ) async {
    await pumpProfile(tester);
    final hero = tester.getRect(find.byKey(const ValueKey('profile-hero')));
    final left = tester.getRect(tile(AppRoutes.leaderboard));
    final right = tester.getRect(tile(AppRoutes.groups));
    expect(left.top, greaterThan(hero.bottom));
    expect(left.top, right.top);
    expect(left.width, right.width);
    expect(left.height, right.height);
    expect(left.height, greaterThanOrEqualTo(56));
    for (final route in [AppRoutes.leaderboard, AppRoutes.groups]) {
      final material = tester.widget<Material>(
        find.descendant(of: tile(route), matching: find.byType(Material)),
      );
      final ink = tester.widget<InkWell>(
        find.descendant(of: tile(route), matching: find.byType(InkWell)),
      );
      expect(material.shape, isA<StadiumBorder>());
      expect(ink.customBorder, isA<StadiumBorder>());
      final outer = tester.getRect(tile(route));
      final badge = tester.getRect(
        find.descendant(of: tile(route), matching: find.byType(IconBadge)),
      );
      expect(badge.width, outer.height - 16);
      expect(badge.left - outer.left, 8);
      expect(badge.top - outer.top, 8);
      expect(outer.bottom - badge.bottom, 8);
    }
    expect(left.right, lessThan(right.left));
    expect(left.left, hero.left);
    expect(right.right, hero.right);
    expect(find.text('Leaderboard'), findsOneWidget);
    expect(find.text('Study Groups'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Leaderboard'),
        matching: find.byType(ListTile),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.text('Study Groups'),
        matching: find.byType(ListTile),
      ),
      findsNothing,
    );

    final router = container.read(routerProvider);
    await tester.tap(tile(AppRoutes.leaderboard));
    await tester.pumpAndSettle();
    expect(find.byType(LeaderboardScreen), findsOneWidget);
    expect(
      router.routeInformationProvider.value.uri.path,
      '/profile/leaderboard',
    );
    router.goNamed(AppRoutes.profile);
    await tester.pumpAndSettle();
    await tester.tap(tile(AppRoutes.groups));
    await tester.pumpAndSettle();
    expect(find.byType(StudyGroupsScreen), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/profile/groups');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final maxLevel in [false, true]) {
    testWidgets('level, XP and progress open achievements, max=$maxLevel', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final stats = GamificationStats(xp: 25, level: maxLevel ? 50 : 3);
      container.read(statsProvider.notifier).hydrate(stats);
      await pumpProfile(tester, anonymous: true);
      final region = find.byKey(const ValueKey('profile-achievements'));
      expect(tester.getSize(region).height, greaterThanOrEqualTo(48));
      expect(
        tester.getSemantics(region),
        matchesSemantics(
          label: maxLevel
              ? 'Level 50, maximum level. 25 XP'
              : 'Level 3, 25 of 55 XP',
          value: maxLevel ? '100 percent' : '45 percent',
          hint: 'Achievements',
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(find.text('Achievements'), findsNothing);
      expect(find.text('Progress'), findsNothing);
      final router = container.read(routerProvider);
      final targets = [
        find.textContaining('Level ${stats.level}', findRichText: true),
        find.text(maxLevel ? '25 XP · Max level' : '25 / 55 XP'),
        find.byType(LinearProgressIndicator),
      ];
      for (final target in targets) {
        expect(find.descendant(of: region, matching: target), findsOneWidget);
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          '/profile/achievements',
        );
        router.goNamed(AppRoutes.profile);
        await tester.pumpAndSettle();
      }
      await tester.scrollUntilVisible(
        find.text('About FocusForge'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Achievements'), findsNothing);
      expect(find.text('Progress'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
    });
  }

  testWidgets('community values stay live and expose full button semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpProfile(tester);

    void expectButton(String route, String label, String value) {
      expect(
        tester.getSemantics(tile(route)),
        matchesSemantics(
          label: label,
          value: value,
          isButton: true,
          hasTapAction: true,
        ),
      );
    }

    expectButton(AppRoutes.leaderboard, 'Leaderboard', '');
    expectButton(AppRoutes.groups, 'Study Groups', '0 active');
    board = const [
      LeaderboardEntry(name: 'Sam', hours: 3),
      LeaderboardEntry(name: 'Alex', hours: 2, isMe: true),
    ];
    groups = [
      StudyGroup(
        id: 'math',
        name: 'Math',
        icon: Icons.school_outlined,
        targetHours: 5,
        createdAt: DateTime(2026),
      ),
    ];
    container.invalidate(leaderboardProvider);
    container.invalidate(groupsProvider);
    await tester.pumpAndSettle();
    expectButton(AppRoutes.leaderboard, 'Leaderboard', '#2');
    expectButton(AppRoutes.groups, 'Study Groups', '1 active');
    expect(find.text('#2'), findsOneWidget);
    expect(find.text('1 active'), findsOneWidget);

    board = [];
    container.invalidate(leaderboardProvider);
    await tester.pumpAndSettle();
    expectButton(AppRoutes.leaderboard, 'Leaderboard', '');
    expect(find.text('#2'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
  });

  testWidgets(
    'anonymous tiles follow the local card and keep the account gate',
    (tester) async {
      await pumpProfile(tester, anonymous: true);
      final local = tester.getRect(
        find.byKey(const ValueKey('profile-local-account')),
      );
      expect(
        tester.getTopLeft(tile(AppRoutes.leaderboard)).dy,
        greaterThan(local.bottom),
      );
      for (final (route, label) in [
        (AppRoutes.leaderboard, 'Leaderboard'),
        (AppRoutes.groups, 'Study Groups'),
      ]) {
        expect(
          find.descendant(
            of: tile(route),
            matching: find.byIcon(Icons.lock_outlined),
          ),
          findsOneWidget,
        );
        await tester.ensureVisible(tile(route));
        await tester.tap(tile(route));
        await tester.pumpAndSettle();
        expect(find.text('$label needs an account'), findsOneWidget);
        expect(
          container
              .read(routerProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/profile',
        );
        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
        expect(container.read(userProvider).isAnonymous, isTrue);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
