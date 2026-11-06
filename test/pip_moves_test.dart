// Pip's walk, slip and book.
//
// WHAT INVARIANT: a walk goes out and comes back with its feet stepping in
// time with the ground covered, a slip drops Pip below the bar and climbs it
// back up, reading raises a book, runs the eye along lines and turns pages,
// and the little gestures (a yawn, a wiggle, a curious tilt, a weight shift,
// swinging feet, a nod) play once;
// each of them comes to rest so the frame scheduler goes quiet, sleep puts
// the book away, and with reduce motion Pip neither walks nor slips.
//
// WHY IT MATTERS: a character that never stops asking for frames drains the
// battery on Home and hangs every widget test that settles the screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/features/assistant/mascot/mascot.dart';
import 'package:focusforge/features/assistant/mascot/mascot_rig.dart';

void main() {
  /// Plays [ms] milliseconds frame by frame; the rig caps one frame's step
  /// at a quarter second, so one long pump would not get there.
  Future<void> play(WidgetTester tester, int ms) async {
    for (var t = 0; t < ms; t += 16) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<MascotRig> pumpPip(WidgetTester tester) async {
    final rig = MascotRig();
    addTearDown(rig.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Center(child: Mascot(rig: rig, width: 80)),
      ),
    );
    return rig;
  }

  testWidgets('a walk goes out, comes back and stops', (tester) async {
    final rig = await pumpPip(tester);
    rig.walk(distance: -0.9, seconds: 4);
    await tester.pump(const Duration(milliseconds: 16));
    expect(rig.wandering, isTrue);
    await play(tester, 2000);
    expect(rig.pose.shiftX, lessThan(-0.5));
    await tester.pumpAndSettle();
    expect(rig.wandering, isFalse);
    expect(rig.moving, isFalse);
    expect(rig.pose.shiftX, 0);
  });

  testWidgets('a slip drops below the bar and climbs back', (tester) async {
    final rig = await pumpPip(tester);
    rig.slip(edge: 0.7);
    await tester.pump(const Duration(milliseconds: 16));
    await play(tester, 1500);
    expect(rig.pose.dropY, greaterThan(0.2));
    expect(rig.pose.surprise, greaterThan(0.5));
    await tester.pumpAndSettle();
    expect(rig.moving, isFalse);
    expect(rig.pose.dropY, 0);
    expect(rig.pose.lean, 0);
  });

  testWidgets('a book comes out, pages turn, and sleep puts it away', (
    tester,
  ) async {
    final rig = await pumpPip(tester);
    rig.sitDown();
    rig.reading = true;
    await tester.pumpAndSettle();
    expect(rig.pose.read, 1);
    rig.flipPage();
    await tester.pump(const Duration(milliseconds: 16));
    await play(tester, 330);
    expect(rig.pose.page, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(rig.pose.page, -1);
    expect(rig.moving, isFalse);

    rig.fallAsleep();
    await tester.pumpAndSettle();
    expect(rig.reading, isFalse);
    expect(rig.pose.read, 0);
  });

  testWidgets('with reduce motion Pip stays on its spot', (tester) async {
    final rig = await pumpPip(tester);
    rig.reduceMotion = true;
    rig.walk();
    rig.slip();
    await tester.pump(const Duration(milliseconds: 500));
    expect(rig.wandering, isFalse);
    expect(rig.pose.shiftX, 0);
    expect(rig.pose.dropY, 0);
  });

  testWidgets('a walk lands on both feet, leaning the way it goes', (
    tester,
  ) async {
    final rig = await pumpPip(tester);
    rig.walk(distance: -1, seconds: 4);
    await play(tester, 900);
    expect(rig.pose.roll, lessThan(0));
    expect(rig.pose.lookX, lessThan(0));
    // The pause halfway: both feet down.
    await play(tester, 1100);
    expect(rig.pose.step.abs(), lessThan(0.05));
    await tester.pumpAndSettle();
    expect(rig.pose.roll, 0);
  });

  testWidgets('every small gesture plays once and comes to rest', (
    tester,
  ) async {
    final rig = await pumpPip(tester);
    rig.yawn();
    await play(tester, 900);
    expect(rig.pose.mouth, greaterThan(1));
    await tester.pumpAndSettle();

    rig.wiggle();
    await play(tester, 600);
    expect(rig.pose.squint, greaterThan(0.5));
    await tester.pumpAndSettle();

    rig.tiltCurious(-1);
    await play(tester, 700);
    expect(rig.pose.tilt, lessThan(-0.1));
    await tester.pumpAndSettle();

    rig.shiftWeight();
    rig.nod();
    await tester.pumpAndSettle();

    rig.sitDown();
    rig.swingFeet();
    await play(tester, 400);
    expect(rig.pose.kick, isNot(0));
    rig.reading = true;
    rig.readLines();
    await tester.pumpAndSettle();
    expect(rig.moving, isFalse);
    expect(rig.pose.kick, 0);

    rig.reduceMotion = true;
    rig.yawn();
    rig.wiggle();
    rig.swingFeet();
    await tester.pump(const Duration(milliseconds: 300));
    expect(rig.fidgeting, isFalse);
  });
}
