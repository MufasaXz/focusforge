// The donut's arithmetic and its selection.
//
// WHAT INVARIANT: every slice is guaranteed a minimum sweep, the sweeps still
// add up to exactly one turn, and the ordering of the slices never changes —
// and a tap on either the ring or the legend moves the readout to that
// subject.
//
// WHY IT MATTERS: `donutSweeps` is the only place the chart does maths, and
// the failure modes are silent. A distribution that overshoots a full turn
// draws arcs on top of each other; a floor applied after the fact reorders the
// slices so the biggest subject is no longer the biggest arc. Neither throws.
// The painter is not reachable from a unit test, so the arithmetic is exposed
// as a function precisely so it can be pinned here.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/data/seed.dart';
import 'package:focusforge/features/dashboard/widgets/subject_breakdown.dart';

const _full = 2 * math.pi;
const _floor = 15 * math.pi / 180;

void main() {
  group('donutSweeps', () {
    test('always sums to exactly one turn', () {
      const cases = <List<double>>[
        [65, 52, 30],
        [1, 1],
        [600, 1],
        [0, 0, 0],
        [12],
        [3, 3, 3, 3, 3, 3],
        [180, 1, 1, 1, 1, 1],
      ];

      for (final values in cases) {
        final sweeps = donutSweeps(values);
        expect(
          sweeps.fold<double>(0, (a, b) => a + b),
          closeTo(_full, 1e-9),
          reason: 'input $values',
        );
        expect(sweeps.length, values.length, reason: 'input $values');
      }
    });

    test('a slice under the floor is lifted to it, at the big slices expense',
        () {
      final sweeps = donutSweeps([600, 1]);

      expect(sweeps[1], closeTo(_floor, 1e-9));
      expect(sweeps[0], closeTo(_full - _floor, 1e-9));
    });

    test('the floor never reorders the slices', () {
      // 5 minutes would be 9.7 degrees; the floor lifts it to 15, and the
      // others give up the difference in proportion. The order by size must
      // survive that — 90 > 60 > 30 > 5.
      final sweeps = donutSweeps([90, 30, 5, 60]);

      expect(sweeps[0], greaterThan(sweeps[3]));
      expect(sweeps[3], greaterThan(sweeps[1]));
      expect(sweeps[1], greaterThan(sweeps[2]));
    });

    test('an empty chart is empty, and a zeroed one splits evenly', () {
      expect(donutSweeps(const []), isEmpty);

      final zeroed = donutSweeps([0, 0, 0]);
      expect(zeroed.length, 3);
      for (final sweep in zeroed) {
        expect(sweep, closeTo(_full / 3, 1e-9));
      }
    });

    test('one subject is the whole ring', () {
      expect(donutSweeps([42]).single, closeTo(_full, 1e-9));
    });
  });

  group('SubjectBreakdown', () {
    const subjects = <Subject>[
      Subject(
        id: 'math',
        name: 'Math',
        icon: Icons.square_foot_rounded,
        color: SubjectPalette.math,
        minutesToday: 65,
      ),
      Subject(
        id: 'physics',
        name: 'Physics',
        icon: Icons.bolt_rounded,
        color: SubjectPalette.physics,
        minutesToday: 52,
      ),
    ];

    Widget harness() => MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: SubjectBreakdown(subjects: subjects),
              ),
            ),
          ),
        );

    testWidgets('opens on the total, and a legend tap moves to that subject', (
      tester,
    ) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('1h 57m'), findsOneWidget);

      await tester.tap(find.text('Math'));
      await tester.pumpAndSettle();

      // The centre now names the subject, so 'Math' appears twice: once in
      // the legend and once in the middle of the ring.
      expect(find.text('Today'), findsNothing);
      expect(find.text('Math'), findsNWidgets(2));
      // The legend already carried Math's value, so the readout doubles it.
      expect(find.text('1h 5m'), findsNWidgets(2));

      // Tapping the same entry again releases it back to the total.
      await tester.tap(find.text('Math').first);
      await tester.pumpAndSettle();
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('a tap on the ring itself selects the slice under it', (
      tester,
    ) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      final ring = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.size == const Size(168, 168),
      );
      expect(ring, findsOneWidget);

      // Straight up from the centre is the start of the first slice — Math,
      // which is the larger of the two and therefore drawn first.
      final centre = tester.getCenter(ring);
      await tester.tapAt(centre + const Offset(0, -65));
      await tester.pumpAndSettle();

      expect(find.text('Math'), findsNWidgets(2));

      // And the hole in the middle is not a slice: tapping it clears the
      // selection rather than picking whichever arc happens to be nearest.
      await tester.tapAt(centre);
      await tester.pumpAndSettle();
      expect(find.text('Today'), findsOneWidget);
    });
  });
}
