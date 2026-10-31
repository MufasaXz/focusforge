import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/study.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/goal_planner_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/features/focus/custom_plan_sheet.dart';
import 'package:focusforge/features/focus/focus_screen.dart';

class _BoundaryRandom implements Random {
  int calls = 0;
  @override
  int nextInt(int max) => calls++ == 0 ? 0 : max - 1;
  @override
  bool nextBool() => throw UnimplementedError();
  @override
  double nextDouble() => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
    await store.clearAll();
  });

  const randomPlan = CustomPlan(
    id: 'random',
    name: 'Flexible focus',
    goalMinutes: 120,
    focusMinutes: 30,
    randomMinMinutes: 20,
    randomMaxMinutes: 40,
  );

  ProviderContainer freshContainer({_BoundaryRandom? random, DateTime? today}) {
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        if (random != null) timerRandomProvider.overrideWithValue(random),
        if (today != null)
          focusCalendarDateProvider.overrideWith(() => _FixedCalendar(today)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<TimerNotifier> selectRandom(ProviderContainer container) async {
    await container.read(planLibraryProvider.notifier).save(randomPlan);
    final index = container
        .read(presetsProvider)
        .indexWhere((p) => p.key == 'custom:random');
    final timer = container.read(timerProvider.notifier);
    await timer.setPreset(index);
    return timer;
  }

  test(
    'random ranges survive stored plans and invalid ranges are rejected',
    () {
      final restored = CustomPlan.fromJson(randomPlan.toJson())!;
      expect(restored.isRandomFocus, isTrue);
      expect(restored.toPreset().randomMinMinutes, 20);
      expect(restored.toPreset().randomMaxMinutes, 40);
      for (final range in [
        [40, 20],
        [20, 20],
        [0, 50],
        [20, 121],
      ]) {
        expect(
          CustomPlan.fromJson({
            ...randomPlan.toJson(),
            'randomMinMinutes': range[0],
            'randomMaxMinutes': range[1],
          }),
          isNull,
        );
      }
    },
  );

  test(
    'one inclusive bounded sample survives pause and cold restore',
    () async {
      final random = _BoundaryRandom();
      final container = freshContainer(random: random);
      final timer = await selectRandom(container);
      expect(
        timer.state.plannedDuration(timer.preset),
        const Duration(minutes: 20),
      );
      expect(random.calls, 1);
      timer.start();
      timer.pause();
      timer.start();
      timer.nudge(const Duration(minutes: 5));
      timer.pause();
      await Future<void>.delayed(Duration.zero);
      final snapshot = store.getMap(StoreKeys.presets)!;
      expect(snapshot['hideRandomDuration'], isTrue);
      expect(snapshot['sampledFocusMs'], 1200000);
      expect(random.calls, 1);

      final nextRandom = _BoundaryRandom();
      final restarted = freshContainer(random: nextRandom);
      restarted
          .read(planLibraryProvider.notifier)
          .hydrate(store.getMap(StoreKeys.planLibrary));
      final restored = restarted.read(timerProvider.notifier)
        ..hydrate(snapshot);
      expect(
        restored.state.plannedDuration(restored.preset),
        const Duration(minutes: 20),
      );
      restored.start();
      expect(
        nextRandom.calls,
        0,
        reason: 'resuming the same block must not resample',
      );
      restored.skip();
      restored.skip();
      expect(
        restored.state.plannedDuration(restored.preset),
        const Duration(minutes: 20),
      );
      expect(nextRandom.calls, 1);
      restored.reset();
      expect(
        restored.state.plannedDuration(restored.preset),
        const Duration(minutes: 40),
      );
      expect(
        nextRandom.calls,
        2,
        reason: 'the inclusive maximum can be selected',
      );
    },
  );

  test(
    'live random blocks use sampled length for progress and completion',
    () async {
      final container = freshContainer(random: _BoundaryRandom());
      final timer = await selectRandom(container);
      final end = DateTime.now().add(const Duration(minutes: 15));
      timer.hydrate({
        'presetKey': 'custom:random',
        'phase': 'focus',
        'running': true,
        'targetEnd': end.millisecondsSinceEpoch,
        'segmentStartedAt': end
            .subtract(const Duration(minutes: 20))
            .millisecondsSinceEpoch,
        'sampledFocusMs': 1200000,
        'remainingMs': 900000,
      });
      expect(
        container.read(liveFocusSecondsTodayProvider),
        inInclusiveRange(300, 301),
      );
      timer.state = timer.state.copyWith(
        targetEnd: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      timer.tick();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(sessionsProvider).single.minutes, 20);
      expect(timer.state.phase, TimerPhase.shortBreak);
    },
  );

  test(
    'completed random blocks credit sampled actual length after process death',
    () async {
      final end = DateTime.now().subtract(const Duration(seconds: 1));
      // A session is credited to the calendar day it *started* on, so a
      // 37-minute segment that ends a second ago began yesterday whenever this
      // runs in the first half hour after midnight. Pin the calendar to the
      // segment's own day instead of leaving the assertion to the wall clock.
      final started = end.subtract(const Duration(minutes: 37));
      final container = freshContainer(
        today: DateTime(started.year, started.month, started.day),
      );
      final timer = await selectRandom(container);
      timer.hydrate({
        'presetKey': 'custom:random',
        'phase': 'focus',
        'running': true,
        'targetEnd': end.millisecondsSinceEpoch,
        'segmentStartedAt': started.millisecondsSinceEpoch,
        'sampledFocusMs': 2220000,
        'remainingMs': 1,
      });
      await Future<void>.delayed(Duration.zero);
      expect(container.read(sessionsProvider).single.minutes, 37);
      expect(container.read(focusMinutesTodayProvider), 37);
    },
  );

  testWidgets(
    'random plan opts in with editable bounds and no countdown leak',
    (tester) async {
      tester.view.physicalSize = const Size(420, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = freshContainer(random: _BoundaryRandom());
      CustomPlan? chosen;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    chosen = await showCustomPlanSheet(context);
                  },
                  child: const Text('Edit'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Random focus length'));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.byType(RangeSlider), findsOneWidget);
      await tester.ensureVisible(find.text('Use this plan'));
      await tester.tap(find.text('Use this plan'));
      await tester.pumpAndSettle();
      expect(chosen!.isRandomFocus, isTrue);

      await selectRandom(container);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: FocusScreen()),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Time stays hidden'), findsOneWidget);
      expect(find.text('20:00'), findsNothing);
      expect(find.text('40:00'), findsNothing);
      await tester.ensureVisible(find.text('Full screen'));
      await tester.tap(find.text('Full screen'));
      await tester.pumpAndSettle();
      expect(find.text('Time stays hidden'), findsWidgets);
      expect(find.text('20:00'), findsNothing);
      await tester.tap(find.byIcon(Icons.close_fullscreen_rounded));
      await tester.pumpAndSettle();
    },
  );
}

class _FixedCalendar extends FocusCalendarDateNotifier {
  _FixedCalendar(this.day);
  final DateTime day;
  @override
  DateTime build() => day;
}
