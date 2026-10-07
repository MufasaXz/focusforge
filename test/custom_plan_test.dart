// The user's own Pomodoro plan: the arithmetic that turns a goal and a block
// length into a full preset, the store round-trip, and the sheet that sets it.
//
// WHAT INVARIANT: two numbers go in — how long the user means to study and how
// long a block runs — and everything else follows from them, deterministically
// and in a range the timer can actually run. A saved plan survives a relaunch
// and is the preset the timer comes back wearing.
//
// WHY IT MATTERS: the derived numbers are what the timer counts down and what
// the session log records against the goal, so an off-by-one in the block
// count is a plan that silently misses the time the user asked for. The stored
// shape is read during bootstrap, before the first frame, so it also has to
// degrade to "no plan" rather than throw on a value it cannot use.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/data/seed.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/features/focus/custom_plan_sheet.dart';
import 'package:focusforge/features/focus/focus_screen.dart';

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

  ProviderContainer freshContainer() {
    final container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
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

  /// Pumps past the stagger entrance.
  ///
  /// [Stagger] schedules its entrance with a bare `Future.delayed`, which
  /// schedules no frame — `pumpAndSettle` alone returns with the timer still
  /// pending and the framework then fails the test on teardown.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  group('CustomPlan', () {
    test('the breaks and the block count follow from the two numbers', () {
      const plan = CustomPlan(goalMinutes: 240, focusMinutes: 50);

      // Four hours at fifty minutes is four blocks and a bit — and the bit is
      // a fifth block, not a lost twenty minutes.
      expect(plan.blocks, 5);
      expect(plan.plannedMinutes, 250);
      expect(plan.shortBreak, 10);
      expect(plan.longBreak, 30);
      expect(plan.cadence, 2);

      final preset = plan.toPreset();
      expect(preset.name, 'Custom');
      expect(preset.focus, 50);
      expect(preset.shortBreak, 10);
      expect(preset.longBreak, 30);
      expect(preset.segments, 2);
    });

    test('a goal that divides evenly is not rounded up to an extra block', () {
      expect(const CustomPlan(goalMinutes: 100, focusMinutes: 25).blocks, 4);
      expect(const CustomPlan(goalMinutes: 101, focusMinutes: 25).blocks, 5);
      expect(const CustomPlan(goalMinutes: 30, focusMinutes: 90).blocks, 1);
    });

    test('a very short block still gets a break worth standing up for', () {
      const plan = CustomPlan(goalMinutes: 60, focusMinutes: 10);
      expect(plan.shortBreak, 3, reason: 'a fifth of ten would be two');
      expect(plan.longBreak, 10);
      expect(plan.cadence, 6, reason: 'short blocks run in longer sets');
    });

    test('a very long block does not get half an hour off', () {
      const plan = CustomPlan(goalMinutes: 480, focusMinutes: 120);
      expect(plan.shortBreak, 20);
      expect(plan.longBreak, 45);
      expect(plan.cadence, 2);
    });

    test('a plan survives the store', () {
      const plan = CustomPlan(goalMinutes: 195, focusMinutes: 45);
      final read = CustomPlan.fromJson(plan.toJson());
      expect(read, isNotNull);
      expect(read!.goalMinutes, 195);
      expect(read.focusMinutes, 45);
    });

    test('an unreadable plan is no plan at all', () {
      expect(CustomPlan.fromJson(const {}), isNull);
      expect(CustomPlan.fromJson(const {'goalMinutes': 120}), isNull);
      expect(CustomPlan.fromJson(const {'goalMinutes': 0, 'focusMinutes': 0}), isNull);
      expect(
        CustomPlan.fromJson(const {'goalMinutes': 'four hours', 'focusMinutes': 50}),
        isNull,
      );

      // Out-of-range values are pulled into the range the sliders can show,
      // rather than opening the sheet pinned at an end that lies about them.
      final huge = CustomPlan.fromJson(const {
        'goalMinutes': 99999,
        'focusMinutes': 99999,
      });
      expect(huge!.goalMinutes, CustomPlan.maxGoal);
      expect(huge.focusMinutes, CustomPlan.maxFocus);
    });
  });

  group('the custom plan in the app', () {
    test('a cold install offers only the shipped presets', () {
      final container = freshContainer();
      expect(container.read(customPlanProvider), isNull);
      expect(container.read(presetsProvider), SeedData.presets);
    });

    test('saving a plan adds it, last, and the timer can wear it', () async {
      final container = freshContainer();
      const plan = CustomPlan(goalMinutes: 240, focusMinutes: 50);

      await container.read(customPlanProvider.notifier).set(plan);

      final presets = container.read(presetsProvider);
      expect(presets, hasLength(SeedData.presets.length + 1));
      expect(presets.last.name, 'Custom');
      expect(presets.last.focus, 50);

      container.read(timerProvider.notifier).setPreset(presets.length - 1);

      final timer = container.read(timerProvider);
      expect(timer.presetIndex, presets.length - 1);
      expect(timer.remaining, const Duration(minutes: 50));
      expect(
        container.read(timerProvider.notifier).preset.name,
        'Custom',
        reason: 'the timer counts down the plan the user set',
      );
    });

    test('the plan and the choice survive a relaunch', () async {
      final first = freshContainer();
      const plan = CustomPlan(goalMinutes: 300, focusMinutes: 30);
      await first.read(customPlanProvider.notifier).set(plan);
      first.read(timerProvider.notifier).setPreset(SeedData.presets.length);
      // The snapshot is written by the notifier itself; the persist is
      // fire-and-forget, so the write is awaited through the store.
      await Future<void>.delayed(Duration.zero);

      // A second container over the same store is the relaunch.
      final second = freshContainer();
      second
          .read(customPlanProvider.notifier)
          .hydrate(store.getMap(StoreKeys.customPlan));
      second
          .read(timerProvider.notifier)
          .hydrate(store.getMap(StoreKeys.presets));

      expect(second.read(customPlanProvider)?.focusMinutes, 30);
      expect(second.read(presetsProvider), hasLength(SeedData.presets.length + 1));
      expect(
        second.read(timerProvider).presetIndex,
        SeedData.presets.length,
        reason: 'the timer comes back on the plan, not on the first preset',
      );
      expect(second.read(timerProvider).remaining, const Duration(minutes: 30));
    });

    test('a plan stored as junk leaves the user on the shipped presets', () {
      final container = freshContainer();
      container
          .read(customPlanProvider.notifier)
          .hydrate(const {'goalMinutes': -5, 'focusMinutes': 0});

      expect(container.read(customPlanProvider), isNull);
      expect(container.read(presetsProvider), SeedData.presets);
    });
  });

  group('the plan sheet', () {
    /// A screen whose only job is to open the sheet and remember what it
    /// returned.
    Widget opener(ProviderContainer container, List<CustomPlan?> out) =>
        wrap(
          container,
          Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  out.add(await showCustomPlanSheet(context));
                },
                child: const Text('open'),
              ),
            ),
          ),
        );

    testWidgets('it opens on a usable plan and returns what is chosen', (
      tester,
    ) async {
      final out = <CustomPlan?>[];
      await tester.pumpWidget(opener(freshContainer(), out));
      await tester.tap(find.text('open'));
      await settle(tester);

      expect(find.text('Your own plan'), findsOneWidget);
      // The default plan is spelled out before anything is touched: two
      // sliders and no numbers would leave the user guessing what they are
      // about to agree to.
      expect(find.textContaining('4h'), findsWidgets);
      expect(find.textContaining('50m'), findsWidgets);

      await tester.tap(find.text('Use this plan'));
      await settle(tester);

      expect(out, hasLength(1));
      expect(out.single!.goalMinutes, 240);
      expect(out.single!.focusMinutes, 50);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the summary follows the sliders', (tester) async {
      final out = <CustomPlan?>[];
      await tester.pumpWidget(opener(freshContainer(), out));
      await tester.tap(find.text('open'));
      await settle(tester);

      expect(find.textContaining('5 focus blocks of 50m'), findsOneWidget);

      // The block-length slider, dragged to the end of its range.
      await tester.drag(find.byType(Slider).last, const Offset(600, 0));
      await settle(tester);

      expect(
        find.textContaining('120m'),
        findsWidgets,
        reason: 'the plan is redrawn while the slider moves, not on submit',
      );

      await tester.tap(find.text('Use this plan'));
      await settle(tester);

      expect(out.single!.focusMinutes, 120);
      expect(out.single!.blocks, 2, reason: 'four hours is two 120m blocks');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the preset sheet offers it beside the shipped presets', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final container = freshContainer();
      await tester.pumpWidget(wrap(container, const FocusScreen()));
      await settle(tester);

      await tester.tap(find.text('Classic Pomodoro'));
      await settle(tester);

      expect(find.text('Pomodoro presets'), findsOneWidget);
      expect(
        find.text('Custom plan'),
        findsOneWidget,
        reason: 'the sheet is where a plan of one\'s own is found',
      );
      expect(
        find.text('Set your own goal and block length'),
        findsOneWidget,
        reason: 'with nothing set, the row says what it is for',
      );
      expect(tester.takeException(), isNull);
    });
  });
}
