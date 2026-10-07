// The daily focus goal: one target per weekday, the editor that sets them, and
// the day's own reading of it.
//
// WHAT INVARIANT: setting a day moves that day and nothing else; today's goal
// is resolved through the clock, so the ring can never show a target that
// belongs to another day; and the stored overrides are read during bootstrap,
// where junk has to degrade to "no override" rather than abort the launch.
//
// WHY IT MATTERS: the ring, the progress fraction and every "of N goal" line
// hang off this number. A goal that belongs to the wrong day is a target the
// user never agreed to — which is exactly the failure one number for the whole
// week produces on the days it does not fit.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/data/seed.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/providers/usage_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/features/dashboard/dashboard_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStore store;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
  });

  setUp(() async {
    await store.clearAll();
  });

  /// A container with the platform reads pinned — see `screen_smoke_test.dart`
  /// for why the usage providers cannot be left to run.
  ProviderContainer freshContainer() {
    final engine = RecordingShieldService();
    addTearDown(engine.dispose);

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
    return container;
  }

  Widget wrap(ProviderContainer container, Widget child) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: child),
        ),
      );

  void useTallPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Pumps past the stagger entrance.
  ///
  /// [Stagger] schedules its entrance with a bare `Future.delayed`, which
  /// schedules no frame — `pumpAndSettle` alone returns with the timer still
  /// pending and the framework then fails the test on teardown.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  group('DailyGoals', () {
    test('a day with no target of its own uses the shared one', () {
      const goals = DailyGoals(defaultMinutes: 300);
      expect(goals.forWeekday(DateTime.monday), 300);
      expect(goals.forWeekday(DateTime.sunday), 300);
      expect(goals.isPerDay, isFalse);
    });

    test('a day of its own leaves the rest of the week alone', () {
      const goals = DailyGoals(
        defaultMinutes: 300,
        byWeekday: {DateTime.sunday: 480},
      );
      expect(goals.forWeekday(DateTime.sunday), 480);
      expect(goals.forWeekday(DateTime.monday), 300);
      expect(goals.isPerDay, isTrue);
    });

    test('stored overrides survive a round trip', () {
      const goals = DailyGoals(
        defaultMinutes: 300,
        byWeekday: {1: 120, 7: 480},
      );
      expect(DailyGoals.readOverrides(goals.toJson()), {1: 120, 7: 480});
    });

    test('an unreadable override is no override', () {
      final read = DailyGoals.readOverrides({
        '1': 120,
        '9': 200, // not a weekday
        'x': 200, // not a day at all
        '2': 'two hours', // not a number
        '3': 0, // no target
        '4': -60,
        '5': 99999, // past the end of the range the editor can show
      });

      expect(read.keys, [1, 5]);
      expect(read[1], 120);
      expect(
        read[5],
        DailyGoals.maxMinutes,
        reason: 'clamped, so the editor opens describing the day it edits',
      );
      expect(DailyGoals.readOverrides(null), isEmpty);
    });
  });

  group('the goal in the app', () {
    test('a cold install uses the shipped number for every day', () {
      final container = freshContainer();
      expect(
        container.read(dailyGoalProvider).defaultMinutes,
        SeedData.focusGoalMinutes,
      );
      expect(
        container.read(todayGoalMinutesProvider),
        SeedData.focusGoalMinutes,
      );
    });

    test('setting a day moves that day and nothing else', () async {
      final container = freshContainer();
      await container
          .read(dailyGoalProvider.notifier)
          .setDay(DateTime.sunday, 480);

      final goals = container.read(dailyGoalProvider);
      expect(goals.forWeekday(DateTime.sunday), 480);
      expect(goals.forWeekday(DateTime.monday), SeedData.focusGoalMinutes);

      // Today resolves through the clock, so the ring reads the target for the
      // day the user is actually in.
      final today = DateTime.now().weekday;
      expect(
        container.read(todayGoalMinutesProvider),
        today == DateTime.sunday ? 480 : SeedData.focusGoalMinutes,
      );
    });

    test('the single onboarding number clears the per-day ones', () async {
      final container = freshContainer();
      await container
          .read(dailyGoalProvider.notifier)
          .setDay(DateTime.sunday, 480);
      await container.read(dailyGoalProvider.notifier).set(240);

      expect(container.read(dailyGoalProvider).byWeekday, isEmpty);
      expect(
        container.read(dailyGoalProvider).forWeekday(DateTime.sunday),
        240,
      );
    });

    test('the goals survive a relaunch', () async {
      final first = freshContainer();
      await first.read(dailyGoalProvider.notifier).setDay(DateTime.sunday, 480);
      await first.read(dailyGoalProvider.notifier).setDay(DateTime.monday, 120);

      // A second container over the same store is the relaunch.
      final second = freshContainer();
      second
          .read(dailyGoalProvider.notifier)
          .hydrate(
            store.getInt(StoreKeys.dailyGoal),
            store.getMap(StoreKeys.dailyGoalDays),
          );

      final goals = second.read(dailyGoalProvider);
      expect(goals.forWeekday(DateTime.sunday), 480);
      expect(goals.forWeekday(DateTime.monday), 120);
      expect(goals.defaultMinutes, SeedData.focusGoalMinutes);
    });
  });

  group("the day's own count", () {
    test('a finished block is banked and an abandoned one is not', () async {
      final container = freshContainer();
      final now = DateTime.now();
      await container
          .read(sessionsProvider.notifier)
          .record(
            FocusSession(
              id: 's-banked',
              subjectId: 'math',
              startedAt: DateTime(now.year, now.month, now.day, 9),
              minutes: 50,
            ),
          );

      expect(container.read(liveFocusSecondsTodayProvider), 50 * 60);

      // Starting a block does not lose what the day has already earned.
      container.read(timerProvider.notifier).start();
      final running = container.read(liveFocusSecondsTodayProvider);
      expect(running, greaterThanOrEqualTo(50 * 60));
      expect(running, lessThan(51 * 60));

      // Abandoning it puts the count back exactly where it was — a block only
      // counts once it is finished.
      container.read(timerProvider.notifier).reset();
      expect(container.read(liveFocusSecondsTodayProvider), 50 * 60);
    });

    test('the progress is measured against the day, not the default', () async {
      final container = freshContainer();
      await container
          .read(dailyGoalProvider.notifier)
          .setDay(DateTime.now().weekday, 60);
      await container
          .read(sessionsProvider.notifier)
          .record(
            FocusSession(
              id: 's-half',
              subjectId: 'math',
              startedAt: DateTime.now(),
              minutes: 30,
            ),
          );

      expect(container.read(todayGoalProgressProvider), closeTo(0.5, 0.001));
    });
  });

  group('the goal editor', () {
    testWidgets('the dashboard row opens it and a day can be moved', (
      tester,
    ) async {
      useTallPhone(tester);
      await store.setBool(StoreKeys.coachSeen, true);

      final container = freshContainer();
      final now = DateTime.now();
      await container
          .read(sessionsProvider.notifier)
          .record(
            FocusSession(
              id: 's-editor',
              subjectId: 'math',
              startedAt: DateTime(now.year, now.month, now.day, 9),
              minutes: 50,
            ),
          );

      await tester.pumpWidget(wrap(container, const DashboardScreen()));
      await settle(tester);

      await tester.tap(find.text("Today's goal"));
      await settle(tester);

      expect(find.text('Daily goal'), findsOneWidget);
      expect(
        find.textContaining('Every day can have its own target'),
        findsOneWidget,
        reason: 'the sheet is where the per-day idea is explained',
      );

      // Sunday is the last row. Dragged to the end of its range it becomes the
      // eight-hour day the week is meant to be able to hold.
      await tester.drag(find.byType(Slider).last, const Offset(600, 0));
      await settle(tester);

      final goals = container.read(dailyGoalProvider);
      expect(goals.forWeekday(DateTime.sunday), DailyGoals.maxMinutes);
      expect(
        goals.forWeekday(DateTime.monday),
        SeedData.focusGoalMinutes,
        reason: 'a day of its own leaves the rest of the week alone',
      );

      await tester.tap(find.text('Done'));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
