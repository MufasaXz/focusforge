// Pip's motion stays smooth, whatever the frame rate.
//
// WHAT INVARIANT: the same stretch of time produces the same pose at 40, 100
// or 200 frames a second; a long stalled frame moves Pip no further than a
// short one would; and a gesture that is interrupted, or asked for twice,
// eases out instead of snapping a joint back in a single frame.
//
// WHY IT MATTERS: frame-rate-dependent springs look different on a 120 Hz
// phone and a 60 Hz one, a quarter-second jump after a route push reads as a
// glitch, and a restart from zero (a hop dropped out of the air, a tilted head
// snapping upright) is the jerk users notice first.

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/features/assistant/mascot/mascot.dart';
import 'package:focusforge/features/assistant/mascot/mascot_rig.dart';

void main() {
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

  /// Plays [ms] milliseconds in frames of [frameMs].
  Future<void> play(WidgetTester tester, int ms, {int frameMs = 16}) async {
    for (var t = 0; t < ms; t += frameMs) {
      await tester.pump(Duration(milliseconds: frameMs));
    }
  }

  for (final frameMs in const [5, 10, 25]) {
    testWidgets(
      'sitting down lands on the same pose at ${1000 ~/ frameMs} Hz',
      (tester) async {
        final rig = await pumpPip(tester);
        rig.sitDown();
        rig.presenting = true;
        // The first frame after a start measures no time.
        await tester.pump();
        await play(tester, 400, frameMs: frameMs);
        final pose = rig.pose;
        // Reference values from the closed-form springs at 400 ms.
        final reference = await _referencePose(tester);
        expect(pose.sit, closeTo(reference.sit, 1e-6));
        expect(pose.leftArm, closeTo(reference.leftArm, 1e-6));
        expect(pose.sway, closeTo(reference.sway, 1e-6));
        await tester.pumpAndSettle();
        expect(rig.moving, isFalse);
      },
    );
  }

  testWidgets('a long stalled frame moves Pip no further than a short one', (
    tester,
  ) async {
    final rig = await pumpPip(tester);
    rig.sitDown();
    await tester.pump();
    // A half-second stall, as after a route push.
    await tester.pump(const Duration(milliseconds: 500));
    final stalled = rig.pose.sit;

    final other = MascotRig();
    addTearDown(other.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Center(child: Mascot(rig: other, width: 80)),
      ),
    );
    other.sitDown();
    await tester.pump();
    await tester.pump(
      Duration(microseconds: (MascotRig.maxFrameStep * 1e6).round()),
    );
    expect(stalled, closeTo(other.pose.sit, 1e-6));
    expect(stalled, lessThan(0.25), reason: 'no jump across the stall');
    await tester.pumpAndSettle();
  });

  testWidgets('a wave eases a curious tilt out instead of snapping it', (
    tester,
  ) async {
    final rig = await pumpPip(tester);
    rig.tiltCurious(1);
    await play(tester, 700);
    final tilted = rig.pose.tilt;
    expect(tilted, greaterThan(0.1));

    rig.wave();
    expect(rig.pose.tilt, tilted, reason: 'nothing jumps on the same frame');
    var last = tilted;
    var biggestStep = 0.0;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final now = rig.pose.tilt;
      biggestStep = (now - last).abs() > biggestStep
          ? (now - last).abs()
          : biggestStep;
      last = now;
    }
    expect(biggestStep, lessThan(0.03), reason: 'the tilt eases out');
    expect(last.abs(), lessThan(0.05), reason: 'and is gone once it has');
    await tester.pumpAndSettle();
    expect(rig.moving, isFalse);
  });

  testWidgets('a second cheer mid-hop does not drop Pip out of the air', (
    tester,
  ) async {
    final rig = await pumpPip(tester);
    rig.cheer();
    await play(tester, 260);
    final airborne = rig.pose.hop;
    expect(airborne, greaterThan(5));
    rig.cheer();
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      (rig.pose.hop - airborne).abs(),
      lessThan(6),
      reason: 'the hop carries on from where it was',
    );
    await tester.pumpAndSettle();
    expect(rig.moving, isFalse);
  });

  testWidgets('talking again keeps the mouth moving from where it was', (
    tester,
  ) async {
    final rig = await pumpPip(tester);
    rig.talk(seconds: 0.6);
    await play(tester, 300);
    final open = rig.pose.mouth;
    rig.talk(seconds: 0.6);
    expect(rig.pose.mouth, open);
    await tester.pump(const Duration(milliseconds: 16));
    expect((rig.pose.mouth - open).abs(), lessThan(0.45));
    await tester.pumpAndSettle();
    expect(rig.moving, isFalse);
  });

  testWidgets('falling asleep mid-gesture eases everything out', (
    tester,
  ) async {
    final rig = await pumpPip(tester);
    rig.cheer();
    await play(tester, 260);
    final airborne = rig.pose.hop;
    rig.fallAsleep();
    expect(rig.pose.hop, airborne);
    await tester.pump(const Duration(milliseconds: 16));
    expect(rig.pose.hop, greaterThan(airborne * 0.6));
    await tester.pumpAndSettle();
    expect(rig.pose.hop, 0);
    expect(rig.sleeping, isTrue);
    expect(rig.moving, isFalse);
  });

  testWidgets('reduce motion still cuts straight to the held pose', (
    tester,
  ) async {
    final rig = await pumpPip(tester);
    rig.tiltCurious(1);
    await play(tester, 500);
    rig.reduceMotion = true;
    rig.sitDown();
    await tester.pump();
    expect(rig.pose.sit, 1);
    expect(rig.pose.tilt, 0);
    expect(rig.moving, isFalse);
  });
}

/// The pose a rig reaches 400 ms after sitting down while presenting, run in
/// 1 ms frames as the reference the coarser frame rates must match.
Future<MascotPose> _referencePose(WidgetTester tester) async {
  final rig = MascotRig();
  final vsync = _ManualVsync();
  rig.attach(vsync);
  rig.sitDown();
  rig.presenting = true;
  vsync.tick(Duration.zero);
  for (var ms = 1; ms <= 400; ms++) {
    vsync.tick(Duration(milliseconds: ms));
  }
  final pose = rig.pose;
  rig.dispose();
  return pose;
}

/// A ticker provider whose frames are driven by hand.
class _ManualVsync implements TickerProvider {
  TickerCallback? _onTick;

  @override
  Ticker createTicker(TickerCallback onTick) {
    _onTick = onTick;
    return _ManualTicker(onTick);
  }

  void tick(Duration elapsed) => _onTick?.call(elapsed);
}

class _ManualTicker extends Ticker {
  _ManualTicker(super.onTick);

  bool _on = false;

  @override
  bool get isActive => _on;

  @override
  TickerFuture start() {
    _on = true;
    return TickerFuture.complete();
  }

  @override
  void stop({bool canceled = false}) => _on = false;
}
