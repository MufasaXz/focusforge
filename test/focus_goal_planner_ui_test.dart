import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/models/study.dart';
import 'package:focusforge/core/providers/goal_planner_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/features/dashboard/widgets/daily_goal_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore store;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
  });
  setUp(() async => store.clearAll());

  Future<ProviderContainer> mount(
    WidgetTester tester, {
    double width = 400,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    container.read(subjectsProvider.notifier).hydrate([
      const Subject(
        id: 'math',
        name: 'Math',
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
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDailyGoalSheet(context),
                child: const Text('Plan'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'a mismatched allocation cannot save and an exact one survives reopening',
    (tester) async {
      final container = await mount(tester);
      final picker = tester.widget<CupertinoPicker>(
        find.byType(CupertinoPicker),
      );
      picker.scrollController!.jumpToItem(32); // 8h, in quarter-hour steps.
      await tester.pumpAndSettle();
      expect(find.text('8h'), findsWidgets);
      await tester.drag(
        find.byKey(const ValueKey('goal-subject-math')),
        const Offset(600, 0),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('goal-subject-science')),
        const Offset(600, 0),
      );
      await tester.pumpAndSettle();
      final save = tester.widget<FilledButton>(
        find.byKey(const ValueKey('save-focus-goal')),
      );
      expect(save.onPressed, isNull);
      expect(container.read(activeFocusGoalProvider), isNull);
      await tester.tap(find.text('Split evenly'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('save-focus-goal')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const ValueKey('save-focus-goal')));
      await tester.pumpAndSettle();
      expect(container.read(activeFocusGoalProvider)?.totalMinutes, 480);
      expect(container.read(activeFocusGoalProvider)?.subjectMinutes, {
        'math': 240,
        'science': 240,
      });
      await tester.tap(find.text('Plan'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CupertinoPicker>(find.byType(CupertinoPicker))
            .scrollController!
            .selectedItem,
        32,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a zero-hour goal cannot be saved without subject allocations', (
    tester,
  ) async {
    final container = await mount(tester);
    tester
        .widget<CupertinoPicker>(find.byType(CupertinoPicker))
        .scrollController!
        .jumpToItem(0);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('save-focus-goal')));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('save-focus-goal')))
          .onPressed,
      isNull,
    );
    expect(container.read(focusGoalPlannerProvider).day, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('positive targets need matching subject allocations', (
    tester,
  ) async {
    final container = await mount(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('save-focus-goal')));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('save-focus-goal')))
          .onPressed,
      isNull,
    );
    expect(container.read(focusGoalPlannerProvider).day, isNull);
    await tester.ensureVisible(find.text('Split evenly'));
    await tester.tap(find.text('Split evenly'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('save-focus-goal')));
    await tester.tap(find.byKey(const ValueKey('save-focus-goal')));
    await tester.pumpAndSettle();
    expect(container.read(activeFocusGoalProvider)?.subjectMinutes, {
      'math': 30,
      'science': 30,
    });
  });

  testWidgets('daily-only editor saves a target on a narrow large-text phone', (
    tester,
  ) async {
    final container = await mount(tester, width: 320, scale: 1.6);
    expect(find.text('For a week'), findsNothing);
    expect(find.textContaining('Today only'), findsOneWidget);
    await tester.ensureVisible(find.text('Split evenly'));
    await tester.tap(find.text('Split evenly'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('save-focus-goal')));
    await tester.tap(find.byKey(const ValueKey('save-focus-goal')));
    await tester.pumpAndSettle();
    expect(container.read(activeFocusGoalProvider)?.scope.name, 'day');
    expect(container.read(activeFocusGoalProvider)?.totalMinutes, 60);
    expect(tester.takeException(), isNull);
  });
}
