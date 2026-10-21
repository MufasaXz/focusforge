import 'dart:async';

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
import 'package:focusforge/shared/widgets/glass_surface.dart';

import 'dart:math' as math;

class _Board implements LeaderboardService {
  final publishedLevels = <int>[];
  final withdrawn = <String>[];
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
    String? avatarPhoto,
  }) async {
    publishedLevels.add(level);
  }

  @override
  Future<void> withdraw(String week, String uid) async {
    withdrawn.add(uid);
  }

  @override
  void dispose() {}
}

class _PendingWithdrawalBoard extends _Board {
  final began = Completer<void>();
  final result = Completer<void>();

  @override
  Future<void> withdraw(String week, String uid) {
    withdrawn.add(uid);
    began.complete();
    return result.future;
  }
}

class _RetryBoard extends _Board {
  var attempts = 0;
  @override
  Future<void> publish({
    required String week,
    required String uid,
    required String name,
    required int minutes,
    required int level,
    String? avatarPhoto,
  }) async {
    attempts++;
    if (attempts <= 2) throw StateError('Offline');
    publishedLevels.add(level);
  }
}

class _RecoveringReadBoard extends _Board {
  int subscriptions = 0;
  @override
  Stream<List<BoardRow>> watch(String week, {int limit = 100}) async* {
    subscriptions++;
    if (subscriptions == 1) throw StateError('Credential not ready');
    yield const [BoardRow(uid: 'fresh', name: 'New student', minutes: 150)];
  }
}

class _LiveBoard extends _Board {
  String latestName = 'Saved student';
  bool emitOnConnect = true;
  int cancelled = 0;
  final streams = <StreamController<List<BoardRow>>>[];

  @override
  Stream<List<BoardRow>> watch(String week, {int limit = 100}) {
    final stream = StreamController<List<BoardRow>>(
      onCancel: () {
        cancelled++;
      },
    );
    streams.add(stream);
    if (emitOnConnect) {
      stream.add([BoardRow(uid: 'fresh', name: latestName, minutes: 150)]);
    }
    return stream.stream;
  }

  @override
  void dispose() {
    for (final stream in streams) {
      unawaited(stream.close());
    }
  }
}

void main() {
  testWidgets(
    'replacement account clears successful old rows before its read completes',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      final board = _LiveBoard();
      final container = ProviderContainer(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          leaderboardServiceProvider.overrideWithValue(board),
        ],
      );
      container
          .read(userProvider.notifier)
          .hydrate(const UserProfile(uid: 'alice', isAnonymous: false));
      final sub = container.listen(weekBoardProvider, (_, _) {});
      await tester.pump();
      expect(container.read(leaderboardProvider).single.name, 'Saved student');
      board.emitOnConnect = false;
      container
          .read(userProvider.notifier)
          .hydrate(const UserProfile(uid: 'bob', isAnonymous: false));
      expect(container.read(weekBoardProvider).isLoading, isTrue);
      expect(container.read(leaderboardProvider), isEmpty);
      board.streams.last.addError(StateError('Still connecting'));
      await tester.pump();
      expect(container.read(leaderboardProvider), isEmpty);
      sub.close();
      container.dispose();
      board.dispose();
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
  testWidgets('opening and resuming the board refreshes cached standings', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    final board = _LiveBoard();
    addTearDown(board.dispose);
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        leaderboardServiceProvider.overrideWithValue(board),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(userProvider.notifier)
        .hydrate(const UserProfile(uid: 'me', isAnonymous: false));
    final sub = container.listen(weekBoardProvider, (_, _) {});
    addTearDown(sub.close);
    await tester.pump();
    expect(container.read(leaderboardProvider).single.name, 'Saved student');
    board.latestName = 'New student';
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
    expect(find.text('New student'), findsOneWidget);
    board.latestName = 'Latest student';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Latest student'), findsOneWidget);
    expect(board.cancelled, greaterThanOrEqualTo(2));
    final refresh = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    board.latestName = 'Pulled student';
    final pending = refresh.onRefresh();
    await tester.pumpAndSettle();
    await pending;
    expect(find.text('Pulled student'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('changing accounts cancels a pending board retry', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    final board = _RecoveringReadBoard();
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        leaderboardServiceProvider.overrideWithValue(board),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(userProvider.notifier)
        .hydrate(const UserProfile(uid: 'alice', isAnonymous: false));
    final sub = container.listen(weekBoardProvider, (_, _) {});
    addTearDown(sub.close);
    await tester.pump();
    expect(container.read(weekBoardProvider).hasError, isTrue);
    container
        .read(userProvider.notifier)
        .hydrate(const UserProfile(uid: 'bob', isAnonymous: false));
    container.read(weekBoardProvider);
    await tester.pump();
    await tester.pump();
    expect(container.read(leaderboardProvider).single.name, 'New student');
    await tester.pump(const Duration(seconds: 4));
    expect(board.subscriptions, 2);
    container.read(userProvider.notifier).hydrate(const UserProfile());
    container.read(weekBoardProvider);
    await tester.pump();
    expect(container.read(leaderboardProvider), isEmpty);
    sub.close();
    container.dispose();
    await tester.pump(const Duration(milliseconds: 1));
  });
  testWidgets('a failed board reconnects without reopening the app', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    final service = _RecoveringReadBoard();
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        accountUidProvider.overrideWithValue('me'),
        leaderboardServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(weekBoardProvider, (_, _) {});
    addTearDown(sub.close);
    await tester.pump();
    expect(container.read(weekBoardProvider).hasError, isTrue);
    await tester.pump(const Duration(seconds: 3));
    expect(container.read(leaderboardProvider).single.name, 'New student');
    expect(service.subscriptions, 2);
  });
  testWidgets(
    'sharing card disappears after opt-in and member menus are absent',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      final container = ProviderContainer(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          accountUidProvider.overrideWithValue('me'),
          leaderboardServiceProvider.overrideWithValue(_Board()),
          leaderboardProvider.overrideWithValue(const [
            LeaderboardEntry(
              uid: 'other',
              name: 'Riley',
              hours: 2,
              isMe: false,
              level: 3,
            ),
          ]),
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
      expect(find.text('Share my weekly score'), findsOneWidget);
      await container.read(boardOptInProvider.notifier).set(true);
      await tester.pumpAndSettle();
      expect(find.text('Share my weekly score'), findsNothing);
      await tester.tap(find.byTooltip('Sharing options'));
      await tester.pumpAndSettle();
      expect(find.text('Turn off sharing'), findsOneWidget);
      expect(find.textContaining('Hide member'), findsNothing);
      expect(find.textContaining('Report member'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'pending board progress retries without another edit and stops after opt-out',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      await store.clearAll();
      final board = _RetryBoard();
      final container = ProviderContainer(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          leaderboardServiceProvider.overrideWithValue(board),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(userProvider.notifier)
          .save(const UserProfile(uid: 'me', isAnonymous: false));
      container.read(sessionsProvider.notifier).hydrate([
        FocusSession(
          id: 'saved',
          ownerUid: 'me',
          subjectId: '',
          startedAt: DateTime.now(),
          minutes: 300,
        ).toJson(),
      ]);
      await container.read(boardOptInProvider.notifier).set(true);
      container.read(leaderboardPublisherProvider);
      await tester.pump();
      expect(board.attempts, 1);
      await tester.pump(const Duration(seconds: 30));
      expect(board.attempts, 2);
      await tester.pump(const Duration(seconds: 30));
      expect(board.publishedLevels, [1]);
      await tester.pump(const Duration(seconds: 30));
      expect(board.attempts, 3);
      await container.read(boardOptInProvider.notifier).set(false);
      await tester.pump(const Duration(seconds: 60));
      expect(board.attempts, 3);
    },
  );
  test(
    'a failed previous-account opt-out never enables the next account',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      await store.clearAll();
      final board = _PendingWithdrawalBoard();
      final container = ProviderContainer(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          leaderboardServiceProvider.overrideWithValue(board),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(userProvider.notifier)
          .save(const UserProfile(uid: 'alice', isAnonymous: false));
      await container.read(boardOptInProvider.notifier).set(true);
      final pending = container.read(boardOptInProvider.notifier).set(false);
      final failure = expectLater(pending, throwsStateError);
      await board.began.future;
      await container
          .read(userProvider.notifier)
          .save(const UserProfile(uid: 'bob', isAnonymous: false));
      expect(container.read(boardOptInProvider), isFalse);
      board.result.completeError(StateError('Credential changed'));
      await failure;
      expect(container.read(boardOptInProvider), isFalse);
      expect(store.getBool(StoreKeys.boardOptIn), isFalse);
      expect(store.getBool('leaderboard.consent.bob'), isNot(isTrue));
      expect(store.getBool('leaderboard.consent.alice'), isTrue);
    },
  );
  test('signout retains a shared row and same-account login republishes existing time', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await store.clearAll();
    final board = _Board();
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        leaderboardServiceProvider.overrideWithValue(board),
      ],
    );
    addTearDown(container.dispose);
    const me = UserProfile(uid: 'me', isAnonymous: false, displayName: 'Alex');
    await container.read(userProvider.notifier).save(me);
    container.read(sessionsProvider.notifier).hydrate([
      FocusSession(
        id: 's',
        subjectId: 'math',
        ownerUid: 'me',
        startedAt: DateTime.now(),
        minutes: 300,
      ).toJson(),
    ]);
    container.read(leaderboardPublisherProvider);
    await container.read(boardOptInProvider.notifier).set(true);
    await container.pump();
    final count = board.publishedLevels.length;
    expect(count, greaterThan(0));
    await container
        .read(userProvider.notifier)
        .save(me.copyWith(isAnonymous: true));
    await container.pump();
    expect(board.withdrawn, isEmpty);
    await container.read(userProvider.notifier).save(me);
    await container.pump();
    await container.read(boardPublishQueueProvider).run(() async {});
    expect(board.publishedLevels.length, greaterThan(count));
    await container.read(boardOptInProvider.notifier).set(false);
    expect(board.withdrawn, ['me']);
  });
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
        .hydrate(
          GamificationStats(
            level: 7,
            xp: const GamificationStats(level: 7).xpForNext - 10,
          ),
        );
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
            .surfaceContainerLow,
      );
      final selfTile = tester.widget<ListTile>(
        find.ancestor(of: find.text('Alex'), matching: find.byType(ListTile)),
      );
      expect((selfTile.shape! as RoundedRectangleBorder).side.width, 1.5);
      final selfFinder = find.ancestor(
        of: find.text('Alex'),
        matching: find.byType(ListTile),
      );
      final cardFinder = find.ancestor(
        of: selfFinder,
        matching: find.byType(ContentCard),
      );
      final cardMaterial = tester.widget<Material>(
        find.descendant(of: cardFinder, matching: find.byType(Material)).first,
      );
      final cardRect = tester.getRect(cardFinder);
      final rowRect = tester.getRect(selfFinder).shift(-cardRect.topLeft);
      final clip = cardMaterial.shape!.getOuterPath(
        Offset.zero & cardRect.size,
      );
      final radius = (selfTile.shape! as RoundedRectangleBorder).borderRadius
          .resolve(TextDirection.ltr)
          .bottomRight
          .x;
      for (var step = 1; step < 10; step++) {
        final angle = math.pi / 2 * step / 10;
        final bottomRight = Offset(
          rowRect.right - radius + radius * math.cos(angle),
          rowRect.bottom - radius + radius * math.sin(angle),
        );
        final bottomLeft = Offset(
          rowRect.left + rowRect.right - bottomRight.dx,
          bottomRight.dy,
        );
        expect(
          clip.contains(bottomRight),
          isTrue,
          reason: 'bottom-right outline must stay inside the card clip',
        );
        expect(
          clip.contains(bottomLeft),
          isTrue,
          reason: 'bottom-left outline must stay inside the card clip',
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
}
