// The goal ring's motion: when it celebrates and when it stays still.
//
// WHAT INVARIANT: a rising milestone plays the celebration once and then the
// ring rests; the same milestone again plays nothing; reduce-motion plays
// nothing at all.
//
// WHY IT MATTERS: the celebration marks a step the user took. One that
// replayed on every rebuild would be noise, and motion the system asked the
// app to leave out is a hard accessibility requirement.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/features/dashboard/widgets/goal_ring.dart';

void main() {
  // One theme for every pump: a rebuilt ThemeData is not equal to the last,
  // so MaterialApp would run its own cross-fade and mask the ring's motion.
  final theme = AppTheme.dark();

  Widget ring(int milestone, {bool reduce = false}) => MaterialApp(
    theme: theme,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: Center(
          child: GoalRing(
            value: .3,
            milestone: milestone,
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  );

  testWidgets('a rising milestone celebrates once, then rests', (tester) async {
    await tester.pumpWidget(ring(1));
    await tester.pumpAndSettle();

    await tester.pumpWidget(ring(2));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pumpWidget(ring(2));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('reduce motion never celebrates', (tester) async {
    await tester.pumpWidget(ring(1, reduce: true));
    await tester.pump();
    await tester.pumpWidget(ring(2, reduce: true));
    expect(tester.hasRunningAnimations, isFalse);
  });
}
