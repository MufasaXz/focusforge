// Home's week, by subject.
//
// WHAT INVARIANT: the week is Monday-aligned, counts completed focus only,
// ranks subjects by their minutes, names the top three side by side and folds
// every other subject into the bars without naming it. Its scale is a whole
// even number of hours sized to the busiest of this week and the last four
// days, so a quiet Monday keeps the scale of a busy weekend.
//
// WHY IT MATTERS: Home's chart answers "what did I study this week". A block
// from last week, an abandoned block or a fourth subject in the legend would
// each make it answer a different question.

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
import 'package:focusforge/features/dashboard/widgets/study_week.dart';

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

  final now = DateTime.now();
  final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));

  Subject subject(String id, String name, Color color) =>
      Subject(id: id, name: name, icon: Icons.book, color: color);

  FocusSession block(
    String id,
    String subjectId,
    DateTime at,
    int minutes, {
    bool completed = true,
  }) => FocusSession(
    id: id,
    subjectId: subjectId,
    startedAt: at,
    minutes: minutes,
    completed: completed,
  );

  void seed(ProviderContainer container) {
    container.read(subjectsProvider.notifier).hydrate([
      subject('math', 'Math', Colors.blue).toJson(),
      subject('physics', 'Physics', Colors.purple).toJson(),
      subject('english', 'English', Colors.green).toJson(),
      subject('history', 'History', Colors.orange).toJson(),
    ]);
    final at = DateTime(monday.year, monday.month, monday.day, 9);
    container.read(sessionsProvider.notifier).hydrate([
      block('a', 'math', at, 50).toJson(),
      block('b', 'math', at.add(const Duration(hours: 1)), 25).toJson(),
      block('c', 'physics', at.add(const Duration(hours: 2)), 50).toJson(),
      block('d', 'english', at.add(const Duration(hours: 3)), 40).toJson(),
      block('e', 'history', at.add(const Duration(hours: 4)), 10).toJson(),
      // Abandoned, and from last week: neither belongs to this week.
      block(
        'f',
        'history',
        at.add(const Duration(hours: 5)),
        90,
        completed: false,
      ).toJson(),
      block('g', 'history', at.subtract(const Duration(days: 3)), 120).toJson(),
    ]);
  }

  test('the chart scale is a whole even number of hours, two at least', () {
    expect(
      [
        for (final m in [0, 60, 120, 121, 240, 241, 360, 450, 600, 721])
          weekScaleHours(m),
      ],
      [2, 2, 2, 4, 4, 6, 6, 8, 10, 14],
    );
  });

  test('the scale remembers the last four days, even across the week', () {
    final container = freshContainer();
    final today = container.read(focusCalendarDateProvider);
    DateTime daysAgo(int n, [int hour = 9]) =>
        DateTime(today.year, today.month, today.day - n, hour);
    container.read(sessionsProvider.notifier).hydrate([
      block('old', 'math', daysAgo(5), 600).toJson(),
      block('a', 'math', daysAgo(3), 200).toJson(),
      block('b', 'math', daysAgo(2), 200).toJson(),
      block('c', 'physics', daysAgo(2, 15), 150).toJson(),
      block('quit', 'math', daysAgo(1), 500, completed: false).toJson(),
    ]);

    expect(container.read(weekStudyProvider).recentPeak, 350);
  });

  testWidgets('a quiet start to the week keeps the recent scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudyWeekChart(
            week: WeekStudy(
              monday: monday,
              days: List.generate(7, (_) => const <String, int>{}),
              subjects: const [],
              recentPeak: 330,
            ),
            named: const [],
          ),
        ),
      ),
    );
    expect(find.text('6h'), findsOneWidget);
    expect(find.text('3h'), findsOneWidget);
    expect(find.text('0h'), findsOneWidget);
  });

  test('the week ranks subjects by their completed minutes', () {
    final container = freshContainer();
    seed(container);

    final week = container.read(weekStudyProvider);

    expect(week.monday, monday);
    expect(
      [for (final s in week.subjects) s.id],
      ['math', 'physics', 'english', 'history'],
    );
    expect([for (final s in week.subjects) s.minutes], [75, 50, 40, 10]);
    expect(week.total, 175);
    expect(week.days.first['math'], 75);
  });

  testWidgets('the legend names the top three subjects side by side', (
    tester,
  ) async {
    final container = freshContainer();
    seed(container);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: SingleChildScrollView(child: StudyWeekOverview()),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    final math = tester.getTopLeft(find.text('Math'));
    final physics = tester.getTopLeft(find.text('Physics'));
    final english = tester.getTopLeft(find.text('English'));
    expect(math.dy, physics.dy);
    expect(physics.dy, english.dy);
    expect(math.dx, lessThan(physics.dx));
    expect(physics.dx, lessThan(english.dx));
    // The fourth subject is in the bars, not in the legend.
    expect(find.text('History'), findsNothing);
    expect(find.text('1h 15m'), findsOneWidget);
    // Screen time waits until the phone shares app usage.
    expect(find.text('Screen time today'), findsNothing);
  });
}
