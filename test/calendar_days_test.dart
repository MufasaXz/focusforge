// Stepping through calendar days in Usage stats.
//
// WHAT INVARIANT: a step of n days lands on midnight of the date n days on,
// whatever the length of the days in between.
//
// WHY IT MATTERS: a daylight-saving day is 23 or 25 hours long. A 24-hour step
// from midnight lands at 23:00 or 01:00, so a day's usage window ran into the
// next day or stopped an hour short, and the day view's arrow stuck on a
// 25-hour day or skipped a 23-hour one.
//
// These cases only bite in a zone that observes daylight saving. Run them with
// one, for example `TZ=America/New_York flutter test test/calendar_days_test.dart`.

import 'package:flutter_test/flutter_test.dart';

import 'package:focusforge/core/providers/usage_stats_providers.dart';

void main() {
  void expectMidnight(DateTime actual, int year, int month, int day) {
    expect(
      [actual.year, actual.month, actual.day, actual.hour, actual.minute],
      [year, month, day, 0, 0],
      reason: '$actual',
    );
  }

  test('a step over a 25-hour day lands on the next date', () {
    // 1 November 2026: clocks go back in the United States.
    expectMidnight(addDays(DateTime(2026, 11, 1), 1), 2026, 11, 2);
    expectMidnight(addDays(DateTime(2026, 11, 2), -1), 2026, 11, 1);
    // 25 October 2026: clocks go back in the European Union.
    expectMidnight(addDays(DateTime(2026, 10, 25), 1), 2026, 10, 26);
  });

  test('a step over a 23-hour day does not skip a date', () {
    // 8 March 2026: clocks go forward in the United States.
    expectMidnight(addDays(DateTime(2026, 3, 9), -1), 2026, 3, 8);
    expectMidnight(addDays(DateTime(2026, 3, 8), 1), 2026, 3, 9);
  });

  test('a week is seven dates, Monday first', () {
    final monday = weekStart(DateTime(2026, 11, 5, 15, 30));
    expectMidnight(monday, 2026, 11, 2);
    expectMidnight(weekStart(DateTime(2026, 11, 1)), 2026, 10, 26);
    final days = [
      for (var i = 0; i < 7; i++) addDays(weekStart(DateTime(2026, 11, 1)), i),
    ];
    expect([for (final d in days) d.day], [26, 27, 28, 29, 30, 31, 1]);
    expect(days.every((d) => d.hour == 0), isTrue);
  });
}
