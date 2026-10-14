import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:focusforge/core/models/focus_goal.dart';
import 'package:focusforge/core/models/study.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/goal_planner_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/services/local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final wednesday = DateTime(2026, 10, 14);
  late LocalStore store;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
  });
  setUp(() async => store.clearAll());

  ProviderContainer containerFor(DateTime day) {
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        focusCalendarDateProvider.overrideWith(() => _FixedCalendar(day)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('an eight hour target requires exactly eight subject hours', () {
    expect(
      () => FocusGoalPlan(
        scope: FocusGoalScope.day,
        date: wednesday,
        totalMinutes: 480,
        subjectMinutes: const {'math': 240, 'science': 180},
      ),
      throwsArgumentError,
    );
    final plan = FocusGoalPlan(
      scope: FocusGoalScope.day,
      date: wednesday,
      totalMinutes: 480,
      subjectMinutes: const {'math': 240, 'science': 240},
    );
    expect(plan.subjectMinutes.values.reduce((a, b) => a + b), 480);
    expect(() => plan.subjectMinutes['math'] = 0, throwsUnsupportedError);
  });

  test(
    'zero target and twelve hours are allowed but invalid values are rejected',
    () {
      expect(
        FocusGoalPlan(
          scope: FocusGoalScope.day,
          date: wednesday,
          totalMinutes: 0,
          subjectMinutes: const {},
        ).totalMinutes,
        0,
      );
      expect(
        FocusGoalPlan(
          scope: FocusGoalScope.day,
          date: wednesday,
          totalMinutes: 720,
          subjectMinutes: const {'math': 720},
        ).totalMinutes,
        720,
      );
      for (final value in [-1, 721]) {
        expect(
          () => FocusGoalPlan(
            scope: FocusGoalScope.day,
            date: wednesday,
            totalMinutes: value,
            subjectMinutes: {'math': value},
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => FocusGoalPlan(
          scope: FocusGoalScope.day,
          date: wednesday,
          totalMinutes: 60,
          subjectMinutes: const {'math': 90, 'science': -30},
        ),
        throwsArgumentError,
      );
    },
  );

  test('daily target belongs only to the selected date', () {
    final plan = FocusGoalPlan(
      scope: FocusGoalScope.day,
      date: wednesday,
      totalMinutes: 120,
      subjectMinutes: const {'math': 120},
    );
    expect(plan.appliesOn(DateTime(2026, 10, 14, 23, 59)), isTrue);
    expect(plan.appliesOn(DateTime(2026, 10, 15)), isFalse);
  });

  test('saved weekly plans never recur or become daily allocations', () async {
    await store.setMap(FocusGoalPlannerNotifier.storageKey, {
      'version': 1,
      'week': {
        'scope': 'week',
        'date': '2026-10-14',
        'totalMinutes': 480,
        'subjectMinutes': {'math': 480},
      },
    });
    expect(containerFor(wednesday).read(activeFocusGoalProvider), isNull);
    expect(
      containerFor(DateTime(2026, 10, 19)).read(activeFocusGoalProvider),
      isNull,
    );
  });

  test('malformed stored allocations do not become a misleading target', () {
    expect(
      FocusGoalPlan.fromJson({
        'scope': 'day',
        'date': '2026-10-14',
        'totalMinutes': 480,
        'subjectMinutes': {'math': 120},
      }),
      isNull,
    );
    expect(
      FocusGoalPlan.fromJson({
        'scope': 'day',
        'date': 'bad date',
        'totalMinutes': 0,
        'subjectMinutes': {},
      }),
      isNull,
    );
  });

  test('a new installation has no invented goal', () {
    final container = containerFor(wednesday);
    expect(container.read(activeFocusGoalProvider), isNull);
  });

  test(
    'saving a daily goal drops legacy weekly data and expires tomorrow',
    () async {
      await store.setMap(FocusGoalPlannerNotifier.storageKey, {
        'version': 1,
        'week': {
          'scope': 'week',
          'date': '2026-10-14',
          'totalMinutes': 480,
          'subjectMinutes': {'math': 480},
        },
      });
      final container = containerFor(wednesday);
      final notifier = container.read(focusGoalPlannerProvider.notifier);
      await notifier.save(
        FocusGoalPlan(
          scope: FocusGoalScope.day,
          date: wednesday,
          totalMinutes: 120,
          subjectMinutes: const {'science': 120},
        ),
      );
      expect(container.read(activeFocusGoalProvider)?.totalMinutes, 120);
      final tomorrow = containerFor(DateTime(2026, 10, 15));
      expect(
        store.getMap(FocusGoalPlannerNotifier.storageKey)?.containsKey('week'),
        isFalse,
      );
      expect(tomorrow.read(activeFocusGoalProvider), isNull);
    },
  );

  test('a legacy weekly object cannot replace a current daily goal', () async {
    final container = containerFor(wednesday);
    final planner = container.read(focusGoalPlannerProvider.notifier);
    await planner.save(
      FocusGoalPlan(
        scope: FocusGoalScope.day,
        date: wednesday,
        totalMinutes: 60,
        subjectMinutes: const {'math': 60},
      ),
    );
    await expectLater(
      planner.save(
        FocusGoalPlan(
          scope: FocusGoalScope.week,
          date: wednesday,
          totalMinutes: 480,
          subjectMinutes: const {'math': 480},
        ),
      ),
      throwsArgumentError,
    );
    expect(container.read(activeFocusGoalProvider)?.scope, FocusGoalScope.day);
    expect(container.read(activeFocusGoalProvider)?.totalMinutes, 60);
  });

  test('goal progress matches widget account ownership including migrated guest records', () async {
    await store.setString(StoreKeys.achievementHistoryOwner, 'account-b');
    await store.setMap(StoreKeys.achievementAliases, {'guest-b': 'account-b'});
    final container = containerFor(wednesday);
    container
        .read(userProvider.notifier)
        .hydrate(const UserProfile(uid: 'account-b'));
    await container
        .read(focusGoalPlannerProvider.notifier)
        .save(
          FocusGoalPlan(
            scope: FocusGoalScope.day,
            date: wednesday,
            totalMinutes: 240,
            subjectMinutes: const {'math': 240},
          ),
        );
    container.read(sessionsProvider.notifier).hydrate([
      for (final item in [
        ('account-a', 120),
        ('account-b', 30),
        ('guest-b', 20),
        ('', 10),
      ])
        FocusSession(
          id: 'session-${item.$1}',
          ownerUid: item.$1,
          subjectId: 'math',
          startedAt: wednesday,
          minutes: item.$2,
        ).toJson(),
    ]);
    expect(container.read(activeFocusGoalSecondsProvider), 60 * 60);
    expect(container.read(activeSubjectGoalMinutesProvider)['math'], 60);
  });

  test(
    'daily progress counts only completed sessions on the selected date',
    () async {
      final container = containerFor(wednesday);
      await container
          .read(focusGoalPlannerProvider.notifier)
          .save(
            FocusGoalPlan(
              scope: FocusGoalScope.day,
              date: wednesday,
              totalMinutes: 480,
              subjectMinutes: const {'math': 480},
            ),
          );
      container.read(sessionsProvider.notifier).hydrate([
        FocusSession(
          id: 'old',
          subjectId: 'math',
          startedAt: DateTime(2026, 10, 11),
          minutes: 180,
        ).toJson(),
        FocusSession(
          id: 'current',
          subjectId: 'math',
          startedAt: wednesday,
          minutes: 120,
        ).toJson(),
        FocusSession(
          id: 'abandoned',
          subjectId: 'math',
          startedAt: wednesday,
          minutes: 90,
          completed: false,
        ).toJson(),
        FocusSession(
          id: 'future',
          subjectId: 'math',
          startedAt: DateTime(2026, 10, 19),
          minutes: 60,
        ).toJson(),
      ]);
      expect(container.read(activeFocusGoalSecondsProvider), 120 * 60);
      expect(container.read(activeFocusGoalProgressProvider), .25);
      expect(container.read(activeSubjectGoalMinutesProvider)['math'], 120);
      final nextWeek = containerFor(DateTime(2026, 10, 19));
      nextWeek
          .read(sessionsProvider.notifier)
          .hydrate(
            container.read(sessionsProvider).map((s) => s.toJson()).toList(),
          );
      expect(nextWeek.read(activeFocusGoalSecondsProvider), 0);
    },
  );
}

class _FixedCalendar extends FocusCalendarDateNotifier {
  _FixedCalendar(this.day);
  final DateTime day;
  @override
  DateTime build() => day;
}
