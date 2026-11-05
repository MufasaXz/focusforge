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
    if (!rig.sleeping && !rig.thinking && !holdGaze) {
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
    _later(6000, 10000, _breathe);
  }

  void _puff() {
    if (rig.sleeping) rig.puff();
    _later(2500, 2700, _puff);
  }
}
