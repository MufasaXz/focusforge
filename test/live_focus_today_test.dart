// Today's ring while a focus block is running.
//
// WHAT INVARIANT: the block in flight adds to today's total only when it
// started today, because a finished block is logged on the day it started.
//
// WHY IT MATTERS: a block begun at 23:50 and still running after midnight
// would otherwise fill today's ring, then empty it again when it finished and
// was logged to yesterday.

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

  /// A running 25-minute block with ten minutes left, started at [startedAt].
  void runBlock(ProviderContainer container, DateTime startedAt) {
    container.read(timerProvider.notifier).hydrate({
      'presetIndex': 0,
      'phase': TimerPhase.focus.name,
      'running': true,
      'targetEnd': DateTime.now()
          .add(const Duration(minutes: 10))
          .millisecondsSinceEpoch,
      'segmentStartedAt': startedAt.millisecondsSinceEpoch,
      'completedFocusSegments': 0,
    });
  }

  DateTime midnight() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  test('a block started today counts toward today', () {
    final container = freshContainer();
    runBlock(container, midnight());

    final seconds = container.read(liveFocusSecondsTodayProvider);
    expect(seconds, closeTo(15 * 60, 5));
  });

  test('a block started before midnight does not', () {
    final container = freshContainer();
    runBlock(container, midnight().subtract(const Duration(minutes: 10)));

    expect(container.read(liveFocusSecondsTodayProvider), 0);
  });
}
