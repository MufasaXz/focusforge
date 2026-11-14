// Pip's small gestures.
//
// WHAT INVARIANT: the little gestures (a yawn, a wiggle, a curious tilt, a
// weight shift, swinging feet, a nod) each play once and come to rest, so
// the frame scheduler goes quiet, and with reduce motion none of them plays.
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
  /// at [MascotRig.maxFrameStep], so one long pump would not get there.
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

  testWidgets('posture changes and sleep clear incompatible idle gestures', (
    tester,
  ) async {
    final rig = await pumpPip(tester);
    rig.sitDown();
    await tester.pumpAndSettle();
    rig.swingFeet();
    await play(tester, 400);
    expect(rig.pose.kick, isNot(0));
    final swinging = rig.pose.kick;
    rig.standUp();
    // Standing up eases the swing out rather than snapping the feet still.
    expect(rig.pose.kick, swinging);
    await play(tester, 320);
    expect(rig.pose.kick, 0);
    await tester.pumpAndSettle();
    rig.yawn();
    await play(tester, 400);
    rig.thinking = true;
    expect(rig.fidgeting, isFalse);
    rig.thinking = false;
    rig.wave();
    rig.fallAsleep();
    await tester.pumpAndSettle();
    expect(rig.gesturing, isFalse);
    expect(rig.sleeping, isTrue);
    expect(rig.moving, isFalse);
    rig.wake();
    await tester.pumpAndSettle();
    expect(rig.sleeping, isFalse);
    expect(rig.gesturing, isFalse);
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
