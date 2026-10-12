import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/core/models/study.dart';
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
  setUp(() => store.clearAll());

  ProviderContainer fresh() {
    final container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    return container;
  }

  CustomPlan named(String id, String name, int focus) => CustomPlan.fromJson({
    'id': id,
    'name': name,
    'goalMinutes': 180,
    'focusMinutes': focus,
  })!;

  test('a saved name becomes the timer plan name after a round trip', () {
    final plan = named('revision', '  Exam revision  ', 30);
    final restored = CustomPlan.fromJson(plan.toJson())!;
    expect(restored.toPreset().name, 'Exam revision');
  });

  test('saving a second named plan keeps both plans available', () async {
    final container = fresh();
    await container
        .read(customPlanProvider.notifier)
        .set(named('revision', 'Exam revision', 30));
    await container
        .read(customPlanProvider.notifier)
        .set(named('reading', 'Evening reading', 45));
    expect(
      container.read(presetsProvider).map((plan) => plan.name),
      containsAll(['Exam revision', 'Evening reading']),
    );
  });

  test(
    'removing an earlier plan keeps a running custom timer on its identity',
    () async {
      final container = fresh();
      await container
          .read(customPlanProvider.notifier)
          .set(named('reading', 'Reading', 45));
      final timer = container.read(timerProvider.notifier);
      timer.setPreset(container.read(presetsProvider).length - 1);
      timer.start();
      final deadline = container.read(timerProvider).targetEnd;
      final key = container.read(presetsProvider).first.key;
      await container.read(planLibraryProvider.notifier).remove(key);
      expect(timer.preset.name, 'Reading');
      expect(container.read(timerProvider).targetEnd, deadline);
      expect(container.read(timerProvider).running, isTrue);
      timer.pause();
    },
  );

  test(
    'removing a selected plan resets safely and persists the new selection',
    () async {
      final container = fresh();
      await container
          .read(customPlanProvider.notifier)
          .set(named('reading', 'Reading', 45));
      final timer = container.read(timerProvider.notifier);
      timer.setPreset(container.read(presetsProvider).length - 1);
      timer.setSubject('math');
      timer.start();
      final key = timer.preset.key;
      await container.read(planLibraryProvider.notifier).remove(key);
      expect(container.read(timerProvider).running, isFalse);
      expect(container.read(timerProvider).subjectId, 'math');
      expect(
        container.read(timerProvider).remaining,
        timer.preset.focusDuration,
      );
      final second = fresh();
      second
          .read(customPlanProvider.notifier)
          .hydrate(store.getMap(StoreKeys.customPlan));
      second
          .read(timerProvider.notifier)
          .hydrate(store.getMap(StoreKeys.presets));
      expect(second.read(presetsProvider).any((p) => p.key == key), isFalse);
      expect(second.read(timerProvider.notifier).preset.key, timer.preset.key);
    },
  );

  test('last plan cannot be removed and stock plans can be restored', () async {
    final container = fresh();
    final library = container.read(planLibraryProvider.notifier);
    for (final preset in container.read(presetsProvider).skip(1).toList()) {
      expect(await library.remove(preset.key), isTrue);
    }
    expect(
      await library.remove(container.read(presetsProvider).first.key),
      isFalse,
    );
    await library.restoreStock();
    expect(container.read(presetsProvider).length, greaterThan(1));
  });
}
