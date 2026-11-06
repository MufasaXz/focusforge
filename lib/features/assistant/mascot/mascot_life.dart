import 'dart:async';
import 'dart:math' as math;

import 'mascot_rig.dart';

/// Small signs of life between the things Pip is asked to do: a blink every
/// few seconds, a glance around, a breath, a "z" while asleep.
///
/// Each is a one-shot on a timer, with stillness between them, so Pip looks
/// alive without ever asking for a frame it does not need.
class MascotLife {
  MascotLife(this.rig, {math.Random? random})
    : _random = random ?? math.Random();

  final MascotRig rig;
  final math.Random _random;
  final _timers = <Timer>{};
  bool _running = false;

  /// While true, Pip keeps its eyes where they were sent, such as on a finger.
  bool holdGaze = false;

  bool get running => _running;

  void start() {
    if (_running) return;
    _running = true;
    _later(2200, 5200, _blink);
    _later(6000, 12000, _glance);
    _later(4000, 9000, _breathe);
    _later(2400, 2800, _puff);
    _later(3500, 6000, _turnPage);
    _later(5000, 9000, _fidget);
  }

  void stop() {
    _running = false;
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }

  void dispose() => stop();

  void _later(int minMs, int maxMs, void Function() action) {
    late final Timer timer;
    timer = Timer(
      Duration(milliseconds: minMs + _random.nextInt(maxMs - minMs + 1)),
      () {
        _timers.remove(timer);
        if (_running) action();
      },
    );
    _timers.add(timer);
  }

  void _blink() {
    rig.blink();
    // Now and then a double blink, the way people do.
    if (_random.nextDouble() < 0.2) _later(240, 300, rig.blink);
    _later(2600, 6400, _blink);
  }

  void _glance() {
    if (!rig.sleeping && !rig.thinking && !rig.reading && !holdGaze) {
      rig.lookAt(
        _random.nextDouble() * 1.6 - 0.8,
        _random.nextDouble() * 0.9 - 0.4,
      );
      _later(1100, 1700, () {
        if (!holdGaze && !rig.thinking) rig.lookAhead();
      });
    }
    _later(7000, 14000, _glance);
  }

  void _breathe() {
    if (!rig.sleeping && !rig.thinking) rig.breathe();
    _later(4500, 7500, _breathe);
  }

  /// The small things a little one does when nothing is happening: shift
  /// from foot to foot, tilt its head at something, swing its feet.
  void _fidget() {
    final free =
        !rig.sleeping &&
        !rig.thinking &&
        !rig.reading &&
        !rig.presenting &&
        !rig.wandering &&
        !rig.fidgeting &&
        !holdGaze;
    if (free) {
      final roll = _random.nextDouble();
      final side = _random.nextBool() ? 1.0 : -1.0;
      if (rig.sitting) {
        if (roll < 0.6) rig.swingFeet();
      } else if (roll < 0.45) {
        rig.shiftWeight(side);
      } else if (roll < 0.7) {
        rig.tiltCurious(side);
      }
    }
    _later(6000, 11000, _fidget);
  }

  /// While reading: a few lines read, now and then a page turned.
  void _turnPage() {
    if (rig.reading) {
      if (_random.nextDouble() < 0.7) {
        rig.readLines();
      } else {
        rig.flipPage();
      }
    }
    _later(3200, 5200, _turnPage);
  }

  void _puff() {
    if (rig.sleeping) rig.puff();
    _later(2500, 2700, _puff);
  }
}
