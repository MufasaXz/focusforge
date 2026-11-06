import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Pip's joints and expressions at one instant, in the drawing's own units.
///
/// Arms are angles from hanging straight down, turning outward. Everything
/// else is a 0–1 amount, apart from [hop] (units up) and the look direction
/// (−1 to 1 on each axis).
@immutable
class MascotPose {
  const MascotPose({
    this.sit = 0,
    this.sleep = 0,
    this.blink = 0,
    this.squint = 0,
    this.lookX = 0,
    this.lookY = 0,
    this.leftArm = MascotRig.restArm,
    this.rightArm = MascotRig.restArm,
    this.tilt = 0,
    this.hop = 0,
    this.squash = 0,
    this.mouth = 0,
    this.surprise = 0,
    this.think = 0,
    this.thinkPhase = 0,
    this.antenna = 0,
    this.breath = 0,
    this.sway = 0,
    this.headLag = 0,
    this.read = 0,
    this.page = -1,
    this.shiftX = 0,
    this.dropY = 0,
    this.lean = 0,
    this.step = 0,
    this.kick = 0,
    this.roll = 0,
    this.zPuff = -1,
  });

  final double sit;
  final double sleep;
  final double blink;
  final double squint;
  final double lookX;
  final double lookY;
  final double leftArm;
  final double rightArm;
  final double tilt;
  final double hop;
  final double squash;
  final double mouth;
  final double surprise;
  final double think;
  final double thinkPhase;
  final double antenna;
  final double breath;

  /// The antenna's swing in radians, trailing the head's movements.
  final double sway;

  /// How far the head trails the body, in units down, during a hop.
  final double headLag;

  /// How far the book is up, 0–1, and a page's turn from right to left
  /// (0–1), or −1 when no page is turning.
  final double read;
  final double page;

  /// Where Pip has walked to, in its own widths (negative is left), and how
  /// far it has dropped below the floor, in its own heights.
  final double shiftX;
  final double dropY;

  /// The whole figure's tilt in radians, pivoting on its right foot.
  final double lean;

  /// The walking step, −1 to 1: positive lifts the left foot.
  final double step;

  /// Seated feet swinging, in radians: positive lifts the left foot.
  final double kick;

  /// A lean into a walk, in radians, pivoting between the feet.
  final double roll;

  /// Progress of the current sleeping "z", or −1 when none is drifting.
  final double zPuff;
}

/// A damped spring that eases one value toward a target.
class _Spring {
  _Spring(this.value, {this.stiffness = 180, this.ratio = 0.8})
    : target = value;

  double value;
  double target;
  double velocity = 0;
  final double stiffness;

  /// Damping ratio: 1 settles without overshoot, below 1 springs past.
  final double ratio;

  bool get settled =>
      (target - value).abs() < 0.0008 && velocity.abs() < 0.0008;

  void step(double dt) {
    final damping = 2 * ratio * math.sqrt(stiffness);
    final force = stiffness * (target - value) - damping * velocity;
    velocity += force * dt;
    value += velocity * dt;
    if (settled) {
      value = target;
      velocity = 0;
    }
  }

  void snap() {
    value = target;
    velocity = 0;
  }
}

/// One timed gesture: when it began and how long it lasts, on the rig's clock.
class _Clip {
  double start = -1;
  double length = 0;

  bool activeAt(double now) => start >= 0 && now - start < length;
  double progressAt(double now) =>
      start < 0 ? 1 : ((now - start) / length).clamp(0.0, 1.0);
  void play(double now, double seconds) {
    start = now;
    length = seconds;
  }

  void stop() => start = -1;
}

/// Drives Pip: springs for the states it holds, short clips for gestures.
///
/// The ticker only runs while something is moving. Between gestures Pip holds
/// still, so the frame scheduler goes quiet. That keeps the battery cost of a
/// character on the home screen near zero, and keeps every animation finite:
/// a widget test can always settle. Sleeping "z"s are one-shot puffs with a
/// rest between them for the same reason.
///
/// With reduce motion on, every change lands at once and no gesture plays.
class MascotRig extends ChangeNotifier {
  MascotRig();

  /// Arms hanging at the sides.
  static const double restArm = 0.5;

  /// The right arm up for a wave.
  static const double waveArm = 2.0;

  /// The left arm out toward a speech bubble.
  static const double presentArm = 1.45;

  /// Both hands at the lower corners of an open book held at the chest.
  static const double readArm = 0.48;

  final _sit = _Spring(0, stiffness: 90, ratio: 0.75);
  final _sleep = _Spring(0, stiffness: 50, ratio: 1);
  final _lookX = _Spring(0, stiffness: 320, ratio: 0.9);
  final _lookY = _Spring(0, stiffness: 320, ratio: 0.9);
  final _tilt = _Spring(0, stiffness: 120, ratio: 0.7);
  final _leftArm = _Spring(restArm, stiffness: 160, ratio: 0.62);
  final _rightArm = _Spring(restArm, stiffness: 160, ratio: 0.62);
  final _think = _Spring(0, stiffness: 140, ratio: 0.9);

  /// The antenna: light and loosely damped, so it wobbles after a move.
  final _sway = _Spring(0, stiffness: 70, ratio: 0.3);
  final _read = _Spring(0, stiffness: 110, ratio: 0.85);

  final _blink = _Clip();
  final _wave = _Clip();
  final _hop = _Clip();
  final _talk = _Clip();
  final _squint = _Clip();
  final _startle = _Clip();
  final _breath = _Clip();
  final _antenna = _Clip();
  final _cheer = _Clip();
  final _puff = _Clip();
  final _page = _Clip();
  final _walk = _Clip();
  final _slip = _Clip();
  final _yawn = _Clip();
  final _wiggle = _Clip();
  final _curious = _Clip();
  final _shift = _Clip();
  final _swing = _Clip();
  final _nod = _Clip();
  final _scan = _Clip();

  Iterable<_Spring> get _springs => [
    _sit,
    _sleep,
    _lookX,
    _lookY,
    _tilt,
    _leftArm,
    _rightArm,
    _think,
    _sway,
    _read,
  ];
  Iterable<_Clip> get _clips => [
    _blink,
    _wave,
    _hop,
    _talk,
    _squint,
    _startle,
    _breath,
    _antenna,
    _cheer,
    _puff,
    _page,
    _walk,
    _slip,
    _yawn,
    _wiggle,
    _curious,
    _shift,
    _swing,
    _nod,
    _scan,
  ];

  Ticker? _ticker;
  Duration _last = Duration.zero;
  double _clock = 0;
  bool _reduceMotion = false;
  bool _presenting = false;
  bool _sitting = false;
  bool _sleeping = false;
  bool _thinking = false;
  bool _disposed = false;
  bool _landed = true;
  bool _reading = false;
  double _walkDistance = 0;
  double _edge = 0.3;
  double _curiousSide = 1;
  double _shiftSide = 1;

  bool get sitting => _sitting;
  bool get sleeping => _sleeping;
  bool get thinking => _thinking;
  bool get reading => _reading;
  bool get presenting => _presenting;

  /// True while a small idle gesture plays, so another waits its turn.
  bool get fidgeting =>
      _yawn.activeAt(_clock) ||
      _wiggle.activeAt(_clock) ||
      _curious.activeAt(_clock) ||
      _shift.activeAt(_clock) ||
      _swing.activeAt(_clock);

  /// True while Pip is off its spot: walking, or slipping and climbing back.
  bool get wandering => _walk.activeAt(_clock) || _slip.activeAt(_clock);

  /// True while a frame is being asked for. Exposed for tests.
  bool get moving => _ticker?.isActive ?? false;

  bool get reduceMotion => _reduceMotion;
  set reduceMotion(bool value) {
    if (_reduceMotion == value) return;
    _reduceMotion = value;
    if (value) {
      for (final clip in _clips) {
        clip.stop();
      }
      for (final spring in _springs) {
        spring.snap();
      }
      _ticker?.stop();
      _notify();
    }
  }

  void attach(TickerProvider vsync) {
    _ticker?.dispose();
    _ticker = vsync.createTicker(_onTick);
  }

  void detach() {
    _ticker?.dispose();
    _ticker = null;
  }

  @override
  void dispose() {
    _disposed = true;
    detach();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _run() {
    if (_disposed) return;
    if (_reduceMotion) {
      for (final spring in _springs) {
        spring.snap();
      }
      _notify();
      return;
    }
    final ticker = _ticker;
    if (ticker == null || ticker.isActive) return;
    _last = Duration.zero;
    ticker.start();
  }

  void _onTick(Duration elapsed) {
    // Pip keeps to the wall clock, so a dropped frame skips ahead instead of
    // slowing everything down. The springs integrate in small steps to stay
    // stable whatever the gap between frames.
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.25);
    _last = elapsed;
    _clock += dt;
    for (var left = dt; left > 0; left -= 1 / 120) {
      final step = math.min(left, 1 / 120);
      for (final spring in _springs) {
        spring.step(step);
      }
    }
    // The landing jolts the antenna once.
    if (!_landed && _hop.start >= 0 && _clock - _hop.start >= _landAt) {
      _landed = true;
      _kick(-2.2);
    }
    // A wave and a cheer hold their arms up only while they play.
    if (!_wave.activeAt(_clock) && _rightArm.target == waveArm) {
      _rightArm.target = _armRest;
    }
    if (_cheer.start >= 0 && !_cheer.activeAt(_clock)) {
      _cheer.stop();
      _leftArm.target = _presenting ? presentArm : _armRest;
      _rightArm.target = _thinking ? 1.15 : _armRest;
    }
    _notify();
    final busy =
        _springs.any((s) => !s.settled) ||
        _clips.any((c) => c.activeAt(_clock));
    if (!busy) _ticker?.stop();
  }

  double get _armRest => _sleeping ? 0.3 : (_sitting ? 0.38 : restArm);

  /// Sets the antenna swinging; it settles on its own.
  void _kick(double velocity) {
    if (_reduceMotion) return;
    _sway.velocity += velocity;
  }

  // A hop: a crouch, the jump, then a squash on landing. A startled hop
  // skips the crouch.
  double get _crouch => _startle.activeAt(_hop.start) ? 0 : 0.16;
  double get _airEnd => _crouch + 0.56;
  double get _landAt => _hop.length * _airEnd;

  void _playHop(double seconds) {
    _hop.play(_clock, seconds);
    _landed = false;
  }

  // -- Gestures ---------------------------------------------------------------

  void blink() {
    if (_sleeping || _reduceMotion) return;
    _blink.play(_clock, 0.19);
    _run();
  }

  /// A raised right hand, waving.
  void wave({double seconds = 1.6}) {
    if (_sleeping) return;
    _rightArm.target = waveArm;
    if (!_reduceMotion) _wave.play(_clock, seconds);
    _run();
    if (_reduceMotion) {
      // No motion: a raised hand, put back down on the next change.
      _rightArm.target = _armRest;
    }
  }

  /// A quick hop with a squint, for a tap or a finished task.
  void cheer() {
    if (_sleeping || _reduceMotion) return;
    _playHop(0.74);
    _squint.play(_clock, 0.95);
    _cheer.play(_clock, 0.74);
    _kick(1.4);
    _leftArm.target = 2.3;
    _rightArm.target = 2.3;
    _run();
  }

  /// Opens and closes the mouth for [seconds], as if speaking.
  void talk({double seconds = 1.1}) {
    if (_sleeping || _reduceMotion) return;
    _talk.play(_clock, seconds);
    _run();
  }

  /// One slow breath: the head and body rise and settle.
  void breathe() {
    if (_sleeping || _reduceMotion) return;
    _breath.play(_clock, 2.2);
    _run();
  }

  /// One gentle sleeping "z", drifting up from the head.
  void puff() {
    if (!_sleeping || _reduceMotion) return;
    _puff.play(_clock, 1.7);
    _run();
  }

  void lookAt(double x, double y) {
    if (_sleeping) return;
    _kick((_lookX.target - x.clamp(-1.0, 1.0)) * 0.9);
    _lookX.target = x.clamp(-1.0, 1.0);
    _lookY.target = y.clamp(-1.0, 1.0);
    _run();
  }

  void lookAhead() => lookAt(0, 0);

  /// Holds an open book and reads it, eyes down, until set false.
  set reading(bool value) {
    if (_reading == value || (value && _sleeping)) return;
    _reading = value;
    _read.target = value ? 1 : 0;
    if (!_thinking) {
      _leftArm.target = value ? readArm : (_presenting ? presentArm : _armRest);
      _rightArm.target = value ? readArm : _armRest;
      _lookX.target = 0;
      _lookY.target = value ? 0.55 : 0;
    }
    _run();
  }

  /// A slow yawn with a stretch, arms up: before a nap, or on waking.
  void yawn() {
    if (_sleeping || _reduceMotion) return;
    _yawn.play(_clock, 2.1);
    _kick(0.6);
    _run();
  }

  /// A happy little shimmy, eyes smiling, for good news.
  void wiggle() {
    if (_sleeping || _reduceMotion || wandering) return;
    _wiggle.play(_clock, 1.3);
    _run();
  }

  /// Tilts its head to one side, [side] −1 for left and 1 for right, the
  /// way a toddler looks at something new.
  void tiltCurious([double side = 1]) {
    if (_sleeping || _reduceMotion) return;
    _curiousSide = side < 0 ? -1 : 1;
    _curious.play(_clock, 1.7);
    _kick(-0.5 * _curiousSide);
    _run();
  }

  /// Shifts its weight from one foot to the other while it stands about.
  void shiftWeight([double side = 1]) {
    if (_sleeping || _sitting || _reduceMotion || wandering) return;
    _shiftSide = side < 0 ? -1 : 1;
    _shift.play(_clock, 2.6);
    _run();
  }

  /// Swings its feet while sitting.
  void swingFeet() {
    if (!_sitting || _sleeping || _reduceMotion) return;
    _swing.play(_clock, 3.4);
    _run();
  }

  /// Two small nods, as if listening.
  void nod() {
    if (_sleeping || _reduceMotion || _nod.activeAt(_clock)) return;
    _nod.play(_clock, 0.9);
    _run();
  }

  /// Reads three lines: the eye runs along each and darts back.
  void readLines() {
    if (!_reading || _sleeping || _reduceMotion) return;
    _scan.play(_clock, 2.6);
    _run();
  }

  /// Turns one page of the book.
  void flipPage() {
    if (!_reading || _sleeping || _reduceMotion) return;
    _page.play(_clock, 0.7);
    _kick(0.4);
    _run();
  }

  /// A short stroll along the bar and back, [distance] of its own widths
  /// (negative is left).
  void walk({double distance = -0.9, double seconds = 4.4}) {
    if (_sleeping || _sitting || _reduceMotion || wandering) return;
    reading = false;
    _walkDistance = distance;
    _walk.play(_clock, seconds);
    _run();
  }

  /// Walks [edge] of its widths to the end of the bar, slips off, hangs on,
  /// climbs back up and walks home.
  void slip({double edge = 0.35}) {
    if (_sleeping || _sitting || _reduceMotion || wandering) return;
    reading = false;
    _edge = edge;
    _slip.play(_clock, 3.8);
    _run();
  }

  // -- States -----------------------------------------------------------------

  /// Points the left arm toward a speech bubble on Pip's left.
  set presenting(bool value) {
    if (_presenting == value) return;
    if (value) reading = false;
    _presenting = value;
    if (_sleeping) return;
    _leftArm.target = value ? presentArm : _armRest;
    _run();
  }

  set thinking(bool value) {
    if (_thinking == value) return;
    _thinking = value;
    _think.target = value ? 1 : 0;
    _tilt.target = value ? -0.07 : (_sleeping ? 0.09 : 0);
    _kick(value ? 0.8 : -0.6);
    if (!_sleeping) {
      _rightArm.target = value ? 1.15 : _armRest;
      if (value) {
        _lookX.target = 0.55;
        _lookY.target = -0.75;
      } else {
        _lookX.target = 0;
        _lookY.target = 0;
      }
    }
    if (value && !_reduceMotion) _antenna.play(_clock, 2.4);
    _run();
  }

  void sitDown() {
    if (_sitting) return;
    _sitting = true;
    _sit.target = 1;
    _leftArm.target = _presenting ? presentArm : _armRest;
    _rightArm.target = _armRest;
    _run();
  }

  void standUp() {
    if (!_sitting && !_sleeping) return;
    if (_sleeping) wake();
    _sitting = false;
    _sit.target = 0;
    _leftArm.target = _presenting ? presentArm : _armRest;
    _rightArm.target = _armRest;
    _run();
  }

  void fallAsleep() {
    if (_sleeping) return;
    reading = false;
    _walk.stop();
    _slip.stop();
    _sitting = true;
    _sleeping = true;
    _thinking = false;
    _think.target = 0;
    _sit.target = 1;
    _sleep.target = 1;
    _tilt.target = 0.09;
    _lookX.target = 0;
    _lookY.target = 0.3;
    _leftArm.target = _armRest;
    _rightArm.target = _armRest;
    _run();
  }

  /// Wakes with a small start: eyes wide, a little jump.
  void wake() {
    if (!_sleeping) return;
    _sleeping = false;
    _sleep.target = 0;
    _tilt.target = 0;
    _lookY.target = 0;
    _puff.stop();
    if (!_reduceMotion) {
      _startle.play(_clock, 0.7);
      _playHop(0.5);
      _kick(2.6);
    }
    _run();
  }

  // -- Pose -------------------------------------------------------------------

  MascotPose get pose {
    final now = _clock;

    var blink = 0.0;
    if (_blink.activeAt(now)) {
      // Lids drop fast and lift a little slower, both eased.
      final d = now - _blink.start;
      blink = d < 0.07
          ? Curves.easeIn.transform(d / 0.07)
          : 1 - Curves.easeOutCubic.transform(((d - 0.07) / 0.12).clamp(0, 1));
    }

    var rightArm = _rightArm.value;
    var tilt = _tilt.value;
    if (_wave.activeAt(now)) {
      final d = now - _wave.start;
      final envelope = _smooth(d / 0.25) * _smooth((_wave.length - d) / 0.3);
      rightArm += math.sin(2 * math.pi * 2.6 * d) * 0.3 * envelope;
      // The head sways along, at half the hand's beat.
      tilt += math.sin(2 * math.pi * 1.3 * d) * 0.035 * envelope;
    }

    var hop = 0.0;
    var squash = 0.0;
    var headLag = 0.0;
    if (_hop.activeAt(now)) {
      final p = _hop.progressAt(now);
      final height = _startle.activeAt(now) ? 18.0 : 42.0;
      final crouch = _crouch;
      final airEnd = _airEnd;
      if (p < crouch) {
        // Anticipation: a quick crouch before the jump.
        squash = 0.45 * Curves.easeOut.transform(p / crouch);
      } else if (p < airEnd) {
        final u = (p - crouch) / (airEnd - crouch);
        hop = height * 4 * u * (1 - u);
        // Out of the crouch into a stretch, round at the top, a slight
        // stretch again on the way down.
        squash = u < 0.14
            ? _lerp(crouch > 0 ? 0.45 : 0, -0.28, _smooth(u / 0.14))
            : u < 0.5
            ? -0.28 * (1 - _smooth((u - 0.14) / 0.36))
            : -0.1 * math.sin(math.pi * (u - 0.5) / 0.5);
        // The head trails the body: low on the way up, high on the way down.
        headLag = 0.12 * height * math.sin(2 * math.pi * u);
      } else {
        final v = (p - airEnd) / (1 - airEnd);
        // Landing: squash, a small rebound, settle.
        squash = v < 0.45
            ? 0.6 * math.sin(math.pi * v / 0.45)
            : -0.1 * math.sin(math.pi * (v - 0.45) / 0.55);
        headLag = 6 * math.sin(math.pi * v) * (1 - v);
      }
    }

    var shiftX = 0.0;
    var dropY = 0.0;
    var lean = 0.0;
    var step = 0.0;
    var armsUp = 0.0;
    var alarm = 0.0;
    var roll = 0.0;
    var armSwing = 0.0;
    var lookShift = 0.0;

    /// One leg of a walk, [progress] 0–1 of [distance] widths in direction
    /// [dir]. The steps follow the ground covered, so feet never slide, and
    /// land on the last one.
    void stride(double progress, double distance, double dir) {
      final halfSteps = math.max(2, (distance.abs() * 6).round());
      final phase = math.pi * halfSteps * progress;
      final swing = math.sin(phase);
      final going = _bell(progress.clamp(0.0, 1.0) / 2 + 0.25);
      step = swing;
      // The body rises over each planted foot and dips between steps.
      hop += 6 * swing.abs() * going;
      // Leaning into the walk, arms swinging against the legs, eyes ahead.
      roll += 0.05 * dir * going;
      armSwing = 0.24 * swing;
      lookShift += 0.55 * dir * going;
      tilt += 0.02 * swing;
    }

    if (_walk.activeAt(now)) {
      // Out, a pause to look around, and back.
      final p = _walk.progressAt(now);
      final out = _smooth(p / 0.45);
      final back = _smooth((p - 0.55) / 0.45);
      shiftX = _walkDistance * (out - back);
      final away = _walkDistance.sign;
      if (p < 0.45) {
        stride(out, _walkDistance, away);
      } else if (p > 0.55) {
        stride(back, _walkDistance, -away);
      } else {
        final look = _bell((p - 0.45) / 0.1);
        tilt += 0.08 * look * away;
        lookShift += 0.7 * away * look;
      }
    }
    if (_slip.activeAt(now)) {
      final p = _slip.progressAt(now);
      final t = now - _slip.start;
      final edge = _edge;
      if (p < 0.2) {
        // Strolls to the end of the bar.
        shiftX = edge * _smooth(p / 0.2);
        stride(_smooth(p / 0.2), edge, 1);
      } else if (p < 0.3) {
        // A foot goes over: a tip, arms flung up, eyes wide.
        final u = (p - 0.2) / 0.1;
        shiftX = edge + 0.08 * _smooth(u);
        lean = 0.55 * _smooth(u);
        armsUp = _smooth(u);
        alarm = Curves.easeOutCubic.transform(u);
      } else if (p < 0.4) {
        // Drops, catching the edge with both hands.
        final u = (p - 0.3) / 0.1;
        shiftX = edge + 0.08;
        lean = _lerp(0.55, 0.12, _smooth(u));
        dropY = 0.42 * Curves.easeIn.transform(u);
        armsUp = 1;
        alarm = 1;
      } else if (p < 0.8) {
        // Climbs back up in two pulls, feet kicking.
        final u = (p - 0.4) / 0.4;
        final pulls =
            0.5 * _smooth(u / 0.42) + 0.5 * _smooth((u - 0.55) / 0.42);
        shiftX = edge + 0.08 * (1 - _smooth(u));
        dropY = 0.42 * (1 - pulls);
        lean = 0.12 * (1 - _smooth(u));
        armsUp = 1 - _smooth((u - 0.82) / 0.18);
        alarm = 1 - _smooth(u);
        step = math.sin(2 * math.pi * 3 * t) * (1 - _smooth((u - 0.6) / 0.4));
      } else {
        // Dusts off and walks home.
        final u = (p - 0.8) / 0.2;
        shiftX = edge * (1 - _smooth(u));
        stride(_smooth(u), edge, -1);
      }
    }
    var yawning = 0.0;
    var kick = 0.0;
    var happy = 0.0;
    if (_yawn.activeAt(now)) {
      // Mouth opens slowly, holds, closes; arms reach up; the body stretches.
      final p = _yawn.progressAt(now);
      yawning = _smooth(p / 0.35) * (1 - _smooth((p - 0.72) / 0.28));
      armsUp = math.max(armsUp, 0.8 * yawning);
      squash = math.min(squash, -0.24 * yawning);
      tilt -= 0.05 * yawning;
    }
    if (_wiggle.activeAt(now)) {
      final t = now - _wiggle.start;
      final env = _bell(_wiggle.progressAt(now));
      tilt += 0.09 * math.sin(2 * math.pi * 2.6 * t) * env;
      shiftX += 0.035 * math.sin(2 * math.pi * 1.3 * t) * env;
      step += 0.6 * math.sin(2 * math.pi * 2.6 * t) * env;
      happy = env;
    }
    if (_curious.activeAt(now)) {
      final p = _curious.progressAt(now);
      final hold = _smooth(p / 0.25) * (1 - _smooth((p - 0.7) / 0.3));
      tilt += 0.16 * _curiousSide * hold;
      lookShift += 0.5 * _curiousSide * hold;
    }
    if (_shift.activeAt(now)) {
      final lean = math.sin(math.pi * _shift.progressAt(now)) * _shiftSide;
      tilt += 0.035 * lean;
      shiftX += 0.015 * lean;
      step += 0.35 * lean;
    }
    if (_swing.activeAt(now)) {
      final t = now - _swing.start;
      kick =
          0.3 * math.sin(2 * math.pi * 1.4 * t) * _bell(_swing.progressAt(now));
    }
    if (_scan.activeAt(now)) {
      // Along a line, then a quick dart back to the start of the next.
      final line = (_scan.progressAt(now) * 3) % 1;
      lookShift += line < 0.82
          ? _lerp(-0.35, 0.35, _smooth(line / 0.82))
          : _lerp(0.35, -0.35, _smooth((line - 0.82) / 0.18));
    }
    if (_nod.activeAt(now)) {
      final t = now - _nod.start;
      headLag +=
          7 *
          (0.5 - 0.5 * math.cos(2 * math.pi * 2.2 * t)) *
          _bell(_nod.progressAt(now));
    }
    final leftArm = _lerp(_leftArm.value + armSwing, 2.5, armsUp);
    rightArm = _lerp(rightArm - armSwing, 2.5, armsUp);

    var mouth = 0.0;
    if (_talk.activeAt(now)) {
      final d = now - _talk.start;
      final envelope = _smooth((_talk.length - d) / 0.18);
      mouth = (0.5 - 0.5 * math.cos(2 * math.pi * 4.2 * d)) * envelope;
    }

    mouth = math.max(mouth, 1.35 * yawning);

    var squint = 0.0;
    if (_squint.activeAt(now)) squint = _bell(_squint.progressAt(now));

    var surprise = 0.0;
    if (_startle.activeAt(now)) {
      // Startled at once, calm again slowly.
      final p = _startle.progressAt(now);
      surprise = p < 0.18
          ? Curves.easeOutCubic.transform(p / 0.18)
          : 1 - _smooth((p - 0.18) / 0.82);
    }
    surprise = math.max(surprise, alarm);
    squint = math.max(squint, math.max(happy, 0.8 * yawning));

    var breath = 0.0;
    if (_breath.activeAt(now)) breath = _bell(_breath.progressAt(now));

    var antenna = 0.0;
    if (_antenna.activeAt(now)) {
      final d = now - _antenna.start;
      antenna = 0.5 - 0.5 * math.cos(2 * math.pi * 1.25 * d);
    } else if (_thinking) {
      antenna = _reduceMotion ? 1 : 0;
    }

    return MascotPose(
      sit: _sit.value,
      sleep: _sleep.value,
      blink: blink.clamp(0.0, 1.0),
      squint: squint,
      lookX: (_lookX.value + lookShift).clamp(-1.0, 1.0),
      lookY: _lookY.value,
      leftArm: leftArm,
      rightArm: rightArm,
      tilt: tilt,
      hop: hop,
      squash: squash,
      mouth: mouth,
      surprise: surprise,
      think: _think.value,
      thinkPhase: _reduceMotion ? 1 : (now * 0.9) % 1,
      antenna: antenna,
      breath: breath,
      sway: (_sway.value - 0.6 * lean).clamp(-0.45, 0.45),
      headLag: headLag,
      read: _read.value.clamp(0.0, 1.0),
      page: _page.activeAt(now) ? _smooth(_page.progressAt(now)) : -1,
      shiftX: shiftX,
      dropY: dropY,
      lean: lean,
      step: step.clamp(-1.0, 1.0),
      kick: kick,
      roll: roll,
      zPuff: _puff.activeAt(now)
          ? _puff.progressAt(now)
          : (_reduceMotion && _sleeping ? 0.45 : -1),
    );
  }

  /// 0 to 1 with no speed at either end.
  static double _smooth(double t) {
    final x = t.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  /// Up and back down over 0–1, starting and ending at rest.
  static double _bell(double t) => 0.5 - 0.5 * math.cos(2 * math.pi * t);

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
