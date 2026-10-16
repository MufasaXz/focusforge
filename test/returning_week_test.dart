import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/providers/goal_planner_providers.dart';
import 'package:focusforge/core/models/study.dart';
import 'package:focusforge/core/services/local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'current week keeps studied dates and shows zero on absent days',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      final container = ProviderContainer(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          focusCalendarDateProvider.overrideWith(() => _Friday()),
        ],
      );
      addTearDown(container.dispose);
      container.read(sessionsProvider.notifier).hydrate([
        for (var day = 12; day <= 14; day++)
          FocusSession(
            id: 's$day',
            subjectId: 'math',
            startedAt: DateTime(2026, 10, day),
            minutes: 120,
          ).toJson(),
      ]);
      final bars = container.read(rangeBarsProvider(StudyRange.week));
      expect(bars.map((bar) => bar.hours), [2, 2, 2, 0, 0, 0, 0]);
      expect(bars.first.date, DateTime(2026, 10, 12));
      expect(bars.last.date, DateTime(2026, 10, 18));
    },
  );
}

class _Friday extends FocusCalendarDateNotifier {
  @override
  DateTime build() => DateTime(2026, 10, 16);
}
