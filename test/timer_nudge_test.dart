// The ±5 controls beside the session bar: what they move, and what they leave
// alone.
//
// WHAT INVARIANT: a nudge changes the segment on the clock — its remaining
// time, its deadline while it runs, and the length the ring divides by — and
// nothing else. The plan keeps its own numbers, so the next block runs as it
// always would, and a block that finishes after being nudged logs the length
// it actually ran.
//
// WHY IT MATTERS: the ring, the clock and the session log all read from this
// one state. A nudge that moved the counter without the deadline would leave a
// clock that disagrees with itself, and one that moved the plan would quietly
// rewrite a choice the user made in the sheet.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/services/local_store.dart';

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

  const five = Duration(minutes: 5);
  const minusFive = Duration(minutes: -5);

  test('an idle block stretches by five and the ring divides by the new '
      'length', () {
    final container = freshContainer();
    final timer = container.read(timerProvider.notifier);
    final preset = container.read(presetsProvider).first;

    expect(timer.state.remaining, preset.focusDuration);

    timer.nudge(five);

    expect(timer.state.remaining, preset.focusDuration + five);
    expect(timer.state.plannedDuration(preset), preset.focusDuration + five);
    // Nothing has run yet, so the ring is still empty: a longer block is not a
    // partly-finished one.
    expect(timer.state.progressFor(preset), 0);

    timer.nudge(minusFive);

    expect(timer.state.remaining, preset.focusDuration);
    expect(timer.state.segmentExtra, Duration.zero);
  });

  test('a running block moves its deadline, so the clock cannot drift', () {
    final container = freshContainer();
    final timer = container.read(timerProvider.notifier);

    timer.start();
    final before = timer.state.targetEnd!;

    timer.nudge(five);

    expect(timer.state.targetEnd, before.add(five));
    // The counter is recomputed from the deadline rather than nudged on its
    // own, so the two agree to within a tick.
    final expected = timer.state.targetEnd!.difference(DateTime.now());
    expect(
      (timer.state.remaining - expected).abs(),
      lessThan(const Duration(seconds: 2)),
    );
  });

  test('a break is nudged on its own length, and the extra stays there', () {
    final container = freshContainer();
    final timer = container.read(timerProvider.notifier);
    final preset = container.read(presetsProvider).first;

    timer.skip();
    expect(timer.state.phase, TimerPhase.shortBreak);
    expect(timer.state.remaining, preset.shortBreakDuration);

    timer.nudge(five);
    expect(timer.state.remaining, preset.shortBreakDuration + five);

    timer.skip();
    expect(timer.state.phase, TimerPhase.focus);
    expect(timer.state.segmentExtra, Duration.zero);
    expect(timer.state.remaining, preset.focusDuration);
  });

  test('the bounds hold at both ends', () {
    final container = freshContainer();
    final timer = container.read(timerProvider.notifier);
    final preset = container.read(presetsProvider).first;

    // Down to the floor and no further: a block cannot be nudged away.
    for (var i = 0; i < 10; i++) {
      timer.nudge(minusFive);
    }
    expect(timer.state.plannedDuration(preset), TimerNotifier.minSegment);

    // Up to the ceiling and no further.
    for (var i = 0; i < 60; i++) {
      timer.nudge(five);
    }
    expect(timer.state.plannedDuration(preset), TimerNotifier.maxSegment);
  });

  test('a block that finishes after a nudge logs the length it ran', () async {
    final container = freshContainer();
    final timer = container.read(timerProvider.notifier);

    // A block that ran its full stretched length while the app was away: the
    // deadline is behind us and the snapshot says it was five minutes longer.
    final started = DateTime.now().subtract(
      const Duration(minutes: 29, seconds: 30),
    );
    timer.hydrate({
      'presetIndex': 0,
      'phase': TimerPhase.focus.name,
      'running': true,
      'targetEnd': DateTime.now()
          .subtract(const Duration(seconds: 1))
          .millisecondsSinceEpoch,
      'segmentStartedAt': started.millisecondsSinceEpoch,
      'completedFocusSegments': 0,
      'segmentExtraMs': five.inMilliseconds,
    });

    // The recovery lands on a microtask, once the log has been read.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final sessions = container.read(sessionsProvider);
    expect(sessions.single.minutes, 30);
  });
}
