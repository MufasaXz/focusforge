import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/data/seed.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/social_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/services/achievement_service.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/features/settings/achievements_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore store;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
    await store.clearAll();
    container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    container
        .read(userProvider.notifier)
        .hydrate(const UserProfile(uid: 'alice', isAnonymous: false));
    container.read(achievementsProvider.notifier).hydrate(const {});
    addTearDown(() async {
      await container.read(achievementsProvider.notifier).flushLocal();
      container.dispose();
    });
  });

  FocusSession session(
    int day, {
    int minutes = 25,
    String owner = 'alice',
    bool completed = true,
  }) => FocusSession(
    id: '$day-$minutes-$owner-$completed',
    subjectId: 'math',
    startedAt: DateTime(2026, 1, day, 12),
    minutes: minutes,
    completed: completed,
    ownerUid: owner,
  );

  Future<void> history(List<FocusSession> sessions) async {
    container
        .read(sessionsProvider.notifier)
        .hydrate(sessions.map((s) => s.toJson()).toList());
    await container.read(achievementsProvider.notifier).refresh();
  }

  const intermediate = {
    'five_sessions',
    'three_day_streak',
    'five_hours',
    'ten_hours',
  };

  test('new milestones stay locked until completed owned sessions reach each target', () async {
    await history([
      for (var day = 1; day <= 4; day++) session(day),
      session(5, owner: 'bob', minutes: 600),
      session(5, completed: false, minutes: 600),
    ]);
    final badges = {
      for (final b in container.read(achievementsProvider)) b.id: b,
    };
    expect(badges.keys, containsAll(intermediate));
    expect(badges['five_sessions']!.progress, 4);
    expect(badges['five_sessions']!.unlocked, isFalse);
    expect(badges['three_day_streak']!.unlocked, isTrue);
    expect(badges['five_hours']!.unlocked, isFalse);
    expect(badges['ten_hours']!.unlocked, isFalse);
    await history([for (var day = 1; day <= 5; day++) session(day)]);
    expect(
      container
          .read(achievementsProvider)
          .singleWhere((b) => b.id == 'five_sessions')
          .unlocked,
      isTrue,
    );
  });

  test('three-day streak counts consecutive calendar days rather than duplicate sessions', () async {
    await history([
      session(1),
      session(1, minutes: 30),
      session(3),
      session(4),
    ]);
    final badges = {
      for (final b in container.read(achievementsProvider)) b.id: b,
    };
    expect(badges.keys, contains('three_day_streak'));
    expect(badges['three_day_streak']!.progress, 2);
    expect(badges['three_day_streak']!.unlocked, isFalse);
    await history([session(3), session(4), session(5)]);
    expect(
      container
          .read(achievementsProvider)
          .singleWhere((b) => b.id == 'three_day_streak')
          .unlocked,
      isTrue,
    );
  });

  test('hour milestones use exact minutes and keep earned dates when history is removed', () async {
    await history([session(1, minutes: 299)]);
    final badges = {
      for (final b in container.read(achievementsProvider)) b.id: b,
    };
    expect(badges.keys, containsAll(intermediate));
    expect(badges['five_hours']!.unlocked, isFalse);
    await history([session(1, minutes: 300)]);
    final earnedAt = container
        .read(achievementsProvider)
        .singleWhere((b) => b.id == 'five_hours')
        .unlockedAt;
    expect(earnedAt, isNotNull);
    await history([session(1, minutes: 599)]);
    expect(
      container
          .read(achievementsProvider)
          .singleWhere((b) => b.id == 'ten_hours')
          .unlocked,
      isFalse,
    );
    await history([session(1, minutes: 600)]);
    expect(
      container
          .read(achievementsProvider)
          .singleWhere((b) => b.id == 'ten_hours')
          .unlocked,
      isTrue,
    );
    await history([]);
    expect(
      container
          .read(achievementsProvider)
          .singleWhere((b) => b.id == 'five_hours')
          .unlockedAt,
      earnedAt,
    );
  });

  test(
    'new badge backup parser keeps valid dates and rejects malformed ones',
    () {
      expect(
        readAchievementTimes({
          'five_sessions': 1704067200000,
          'three_day_streak': 0,
          'five_hours': -1,
          'ten_hours': '2026',
        }),
        {'five_sessions': 1704067200000, 'three_day_streak': 0},
      );
    },
  );

  test(
    'new badge recovery retains original dates and never crosses accounts',
    () async {
      await container.read(achievementsProvider.notifier).restoreBackup(
        'alice',
        {
          'first_focus': 1704067200000,
          'five_sessions': 1735689600000,
          'three_day_streak': 0,
          'five_hours': 1740787200000,
          'ten_hours': 1743465600000,
        },
      );
      expect(container.read(achievementsProvider.notifier).earnedTimes, {
        'first_focus': 1704067200000,
        'five_sessions': 1735689600000,
        'three_day_streak': 0,
        'five_hours': 1740787200000,
        'ten_hours': 1743465600000,
      });
      await container
          .read(userProvider.notifier)
          .save(const UserProfile(uid: 'bob', isAnonymous: false));
      expect(container.read(unlockedCountProvider), 0);
      await container.read(achievementsProvider.notifier).restoreBackup(
        'alice',
        {'ten_hours': 1704067200000},
      );
      expect(container.read(unlockedCountProvider), 0);
      await container
          .read(userProvider.notifier)
          .save(const UserProfile(uid: 'alice', isAnonymous: false));
      expect(
        container.read(achievementsProvider.notifier).earnedTimes['ten_hours'],
        1743465600000,
      );
    },
  );

  test(
    'hour units preserve a minute of remaining work at a near-complete target',
    () {
      final fiveHours = SeedData.badges
          .singleWhere((b) => b.id == 'five_hours')
          .copyWith(progress: 299 / 60);
      expect(fiveHours.remainingLabel, '1 minute remaining');
      expect(fiveHours.progressLabel, '4 hours 59 min / 5 hours');
      expect(
        SeedData.badges
            .singleWhere((b) => b.id == 'five_sessions')
            .copyWith(progress: 4)
            .remainingLabel,
        '1 session remaining',
      );
      expect(
        SeedData.badges
            .singleWhere((b) => b.id == 'three_day_streak')
            .copyWith(progress: 1)
            .remainingLabel,
        '2 days remaining',
      );
    },
  );

  Widget app({double textScale = 1}) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: const AchievementsScreen(),
    ),
  );

  testWidgets(
    'collection keeps the next milestone visible after the first earn',
    (tester) async {
      await tester.runAsync(() => history([session(1)]));
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('Your collection'), findsOneWidget);
      expect(find.text('Next milestone'), findsOneWidget);
      expect(find.textContaining('remaining'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'earned collection places the newest known date before earlier and unknown dates',
    (tester) async {
      await tester.runAsync(
        () => container.read(achievementsProvider.notifier).restoreBackup(
          'alice',
          {
            'first_focus': 1704067200000,
            'week_warrior': 1767225600000,
            'night_owl': 0,
          },
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final names = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(GridView).first,
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data)
          .where(
            (text) =>
                {'Week Warrior', 'First Spark', 'Night Owl'}.contains(text),
          )
          .toList();
      expect(names, ['Week Warrior', 'First Spark', 'Night Owl']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('320dp at standard text shows two useful badge columns', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    for (final grid in tester.widgetList<GridView>(find.byType(GridView))) {
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        2,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'locked hour detail keeps actual minutes readable at double text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => history([session(1, minutes: 299)]));
      await tester.pumpWidget(app(textScale: 2));
      await tester.pumpAndSettle();
      for (
        var attempt = 0;
        attempt < 15 &&
            find.text('View milestone').hitTestable().evaluate().isEmpty;
        attempt++
      ) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -220));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('View milestone'));
      await tester.pumpAndSettle();
      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(
          of: sheet,
          matching: find.text('4 hours 59 min / 5 hours'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('1 minute remaining')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '320dp with double text uses one column and a scrollable detail',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => history([session(1)]));
      await tester.pumpWidget(app(textScale: 2));
      await tester.pumpAndSettle();
      final grids = tester.widgetList<GridView>(find.byType(GridView));
      expect(grids, isNotEmpty);
      for (final grid in grids) {
        expect(
          (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
              .crossAxisCount,
          1,
        );
      }
      expect(tester.takeException(), isNull);
      for (
        var attempt = 0;
        attempt < 20 &&
            find.text('First Spark').hitTestable().evaluate().isEmpty;
        attempt++
      ) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -240));
        await tester.pumpAndSettle();
      }
      expect(find.text('First Spark').hitTestable(), findsOneWidget);
      await tester.tap(find.text('First Spark'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
