import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/focus_goal.dart';
import 'package:focusforge/core/models/study.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/goal_planner_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/providers/usage_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/features/dashboard/dashboard_screen.dart';
import 'package:focusforge/features/dashboard/widgets/screen_time_card.dart';
import 'package:focusforge/features/onboarding/coach_marks.dart';
import 'package:focusforge/shared/widgets/glass_surface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
    await store.clearAll();
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
  }

  Future<ProviderContainer> mountHome(
    WidgetTester tester, {
    required bool Function() access,
    double width = 400,
    double scale = 1,
    FocusGoalPlan? plan,
  }) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await store.setBool(StoreKeys.coachSeen, true);
    if (plan != null && plan.totalMinutes == 0) {
      // Compatibility fixture: zero-hour plans could be persisted by older
      // releases, but the new editor/notifier must never create one.
      await store.setMap(FocusGoalPlannerNotifier.storageKey, {
        'version': 2,
        'day': plan.toJson(),
      });
    }
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        usageAccessProvider.overrideWith((ref) async => access()),
        installedAppsProvider.overrideWith((ref) async => const []),
        appUsageTodayProvider.overrideWith((ref) async => const {}),
      ],
    );
    addTearDown(container.dispose);
    container.read(subjectsProvider.notifier).hydrate([
      const Subject(
        id: 'math',
        name: 'Mathematics',
        icon: Icons.book,
        color: Colors.blue,
      ).toJson(),
      const Subject(
        id: 'science',
        name: 'Science',
        icon: Icons.science,
        color: Colors.green,
      ).toJson(),
    ]);
    if (plan != null && plan.totalMinutes > 0) {
      await container.read(focusGoalPlannerProvider.notifier).save(plan);
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const Scaffold(body: DashboardScreen()),
        ),
      ),
    );
    await settle(tester);
    return container;
  }

  testWidgets(
    'subject allocations have their own solid tile outside the goal gauge',
    (tester) async {
      await mountHome(
        tester,
        access: () => false,
        width: 320,
        scale: 2,
        plan: FocusGoalPlan(
          scope: FocusGoalScope.day,
          date: DateTime.now(),
          totalMinutes: 120,
          subjectMinutes: const {'math': 45, 'science': 75},
        ),
      );
      final gauge = find.byKey(const ValueKey('daily-goal-tile'));
      final subjects = find.byKey(const ValueKey('subject-allocation-tile'));
      expect(gauge, findsOneWidget);
      await tester.scrollUntilVisible(subjects, 200);
      expect(subjects, findsOneWidget);
      expect(
        find.descendant(of: gauge, matching: find.text('Mathematics')),
        findsNothing,
      );
      expect(
        find.descendant(of: subjects, matching: find.text('Mathematics')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: subjects, matching: find.text('45m')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: subjects, matching: find.text('1h 15m')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: subjects, matching: find.byType(GlassCard)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'zero-hour daily plan keeps Home on Set goal without a session action',
    (tester) async {
      await mountHome(
        tester,
        access: () => false,
        plan: FocusGoalPlan(
          scope: FocusGoalScope.day,
          date: DateTime.now(),
          totalMinutes: 0,
          subjectMinutes: const {},
        ),
      );
      expect(find.text('Set goal'), findsOneWidget);
      expect(find.text('Start session'), findsNothing);
      expect(
        find.byKey(const ValueKey('subject-allocation-tile')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'usage access only toggles its request card and never adds analytics',
    (tester) async {
      var allowed = false;
      final container = await mountHome(tester, access: () => allowed);
      expect(find.text('Allow app usage'), findsOneWidget);
      expect(find.text('Screen time today'), findsNothing);
      expect(find.byType(ScreenTimeCard), findsNothing);
      allowed = true;
      container.invalidate(usageAccessProvider);
      await settle(tester);
      expect(find.text('Allow app usage'), findsNothing);
      expect(find.text('Screen time today'), findsNothing);
      expect(find.byType(ScreenTimeCard), findsNothing);
      allowed = false;
      container.invalidate(usageAccessProvider);
      await settle(tester);
      expect(find.text('Allow app usage'), findsOneWidget);
      expect(find.text('Screen time today'), findsNothing);
      expect(find.byType(ScreenTimeCard), findsNothing);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('unallocated daily goal hides the subject tile', (tester) async {
    await mountHome(
      tester,
      access: () => true,
      plan: FocusGoalPlan(
        scope: FocusGoalScope.day,
        date: DateTime.now(),
        totalMinutes: 120,
        subjectMinutes: const {},
      ),
    );
    expect(find.byKey(const ValueKey('daily-goal-tile')), findsOneWidget);
    expect(find.byKey(const ValueKey('subject-allocation-tile')), findsNothing);
    expect(find.text('Start session'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'a large coach target gets a compact spotlight on a 320dp screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final target = GlobalKey();
      final container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: CoachMarks(
                spots: [
                  CoachSpot(
                    target: target,
                    icon: Icons.flag,
                    title: 'Your daily goal',
                    body: 'Your saved target belongs to today.',
                  ),
                ],
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(key: target, width: 280, height: 400),
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      final spotlight = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .singleWhere(
            (paint) =>
                paint.painter.runtimeType.toString() == '_SpotlightPainter',
          );
      final dynamic painter = spotlight.painter;
      expect(painter.radius, inInclusiveRange(32.0, 64.0));
      expect(painter.center, tester.getRect(find.byKey(target)).center);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Got it'));
      await settle(tester);
    },
  );
}
