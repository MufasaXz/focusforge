import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/social.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/models/study.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/social_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/leaderboard_service.dart';
import 'package:focusforge/features/settings/leaderboard_screen.dart';

class _Board implements LeaderboardService {
  final publishedLevels = <int>[];
  @override
  bool get available => true;
  @override
  String? get uid => 'me';
  @override
  Stream<List<BoardRow>> watch(String week, {int limit = 100}) =>
      Stream.value(const []);
  @override
  Future<void> publish({
    required String week,
    required String uid,
    required String name,
    required int minutes,
    required int level,
  }) async {
    publishedLevels.add(level);
  }

  @override
  Future<void> withdraw(String week, String uid) async {}
  @override
  void dispose() {}
}

void main() {
  testWidgets('a failed board offers retry instead of claiming nobody joined', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        accountUidProvider.overrideWithValue('me'),
        leaderboardServiceProvider.overrideWithValue(_Board()),
        weekBoardProvider.overrideWith(
          (ref) => Stream.error(StateError('offline')),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(userProvider.notifier)
        .hydrate(const UserProfile(uid: 'me', isAnonymous: false));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const LeaderboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load this week’s standings.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('Nobody'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('board preserves a shared level and keeps legacy levels unknown', () {
    final current = BoardRow.fromJson('alex', {
      'name': 'Alex',
      'minutes': 60,
      'level': 7,
    });
    expect(current!.toJson()['level'], 7);
    final legacy = BoardRow.fromJson('old', {
      'name': 'Older app',
      'minutes': 60,
    });
    expect(legacy!.toJson().containsKey('level'), isFalse);
    for (final invalid in [0, -1, 1.5, '7']) {
      final row = BoardRow.fromJson('bad', {
        'name': 'Alex',
        'minutes': 60,
        'level': invalid,
      });
      expect(row!.toJson().containsKey('level'), isFalse);
    }
  });

  test('publisher shares the real level, updates on level-up, and respects opt-out', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    final service = _Board();
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        leaderboardServiceProvider.overrideWithValue(service),
        accountUidProvider.overrideWithValue('me'),
      ],
    );
    addTearDown(container.dispose);
    container.read(sessionsProvider.notifier).hydrate([
      FocusSession(
        id: 'week-session',
        subjectId: 'math',
        startedAt: DateTime.now(),
        minutes: 60,
      ).toJson(),
    ]);
    container
        .read(statsProvider.notifier)
        .hydrate(const GamificationStats(level: 7, xp: 2490));
    container.read(leaderboardPublisherProvider);
    await container.pump();
    expect(service.publishedLevels, isEmpty);
    await container.read(boardOptInProvider.notifier).set(true);
    await container.pump();
    expect(service.publishedLevels.last, 7);
    await container.read(statsProvider.notifier).award(10);
    await container.pump();
    expect(service.publishedLevels.last, 8);
    await container.read(boardOptInProvider.notifier).set(false);
    final count = service.publishedLevels.length;
    await container.read(statsProvider.notifier).award(100);
    await container.pump();
    expect(service.publishedLevels.length, count);
  });

  test('board entries carry the shared level into the screen model', () async {
    final container = ProviderContainer(
      overrides: [
        accountUidProvider.overrideWithValue('me'),
        weekBoardProvider.overrideWith(
          (ref) => Stream.value(const [
            BoardRow(uid: 'me', name: 'Alex', minutes: 60, level: 7),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(weekBoardProvider.future);
    final entry = container.read(leaderboardProvider).single;
    expect(entry.level, 7);
    expect(entry.isMe, isTrue);
  });

  for (final dark in [false, true]) {
    testWidgets('weekly summary and standings fit 320dp at 2x, dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      final container = ProviderContainer(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          leaderboardServiceProvider.overrideWithValue(_Board()),
          leaderboardWeekHoursProvider.overrideWithValue(2),
          previousWeekHoursProvider.overrideWithValue(4),
          weekSessionCountProvider.overrideWithValue(3),
          leaderboardProvider.overrideWithValue(const [
            LeaderboardEntry(
              uid: 'riley',
              name: 'Alexandria Morgan Rivera',
              hours: 6,
            ),
            LeaderboardEntry(name: 'Alex', hours: 2, level: 7, isMe: true),
          ]),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(userProvider.notifier)
          .hydrate(
            const UserProfile(
              uid: 'me',
              displayName: 'Alex',
              isAnonymous: false,
            ),
          );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: dark ? AppTheme.dark(amoled: true) : AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: const LeaderboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('leaderboard-week')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('leaderboard-week')),
          matching: find.text('2h'),
        ),
        findsOneWidget,
      );
      expect(find.text('−2h'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.label == 'This week against last week' &&
              w.properties.value == '50 percent',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Alex'), 160);
      expect(find.text('Alex'), findsOneWidget);
      expect(find.text('Level 7'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(find.text('Level unavailable'), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(
              find.ancestor(
                of: find.text('Alex'),
                matching: find.byType(ListTile),
              ),
            )
            .tileColor,
        (dark ? AppTheme.dark(amoled: true) : AppTheme.light())
            .colorScheme
            .primaryContainer,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
