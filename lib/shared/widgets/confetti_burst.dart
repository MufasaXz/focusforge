import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A single burst of particles, drawn by hand.
///
/// The `confetti` package is available, but its defaults — long rainbow ribbons
/// that keep falling — fight the rest of the interface. The particles here are
/// short ticks in the theme's own primary/secondary/tertiary, which reads as a
/// quiet "well done" rather than a party popper.
///
/// Two things make it read as a cracker rather than as a splash. It fires from
/// two points near the bottom corners, angled inwards and up, the way a pair of
/// party poppers does — and each particle leaves on its own delay, so the cloud
/// blooms over a fifth of a second instead of appearing all at once. Positions
/// are closed-form functions of time, so nothing is integrated frame to frame
/// and the burst looks the same on a janky frame as on a smooth one.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key, this.trigger = 0, this.particleCount = 64});

  /// Bump this to fire. A burst also plays when the widget mounts with a
  /// non-zero trigger, which covers the "insert it when the event happens"
  /// usage as well as the "keep it mounted and count" one.
  final int trigger;

  final int particleCount;

  /// Fires a one-shot burst over the nearest [Overlay] and removes it when the
  /// animation has finished.
  static void fire(BuildContext context, {int particles = 64}) {
    if (MediaQuery.disableAnimationsOf(context)) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    late final OverlayEntry entry;
    var removed = false;
    void remove() {
      if (removed) return;
      removed = true;
      // The overlay may already be gone if the app tore down mid-burst, and
      // `remove()` asserts on an entry that is no longer mounted.
      if (entry.mounted) entry.remove();
    }

    entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: _BurstSurface(count: particles, trigger: 1, onCompleted: remove),
      ),
    );
    overlay.insert(entry);
  }

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst> {
  @override
  Widget build(BuildContext context) =>
      _BurstSurface(count: widget.particleCount, trigger: widget.trigger);
}

/// The burst itself, shared by the in-tree widget and the overlay helper.
///
/// Fills whatever space it is given, so it belongs in a [Stack] or a
/// [Positioned.fill] rather than an unbounded column.
class _BurstSurface extends StatefulWidget {
  const _BurstSurface({
    required this.count,
    required this.trigger,
    this.onCompleted,
  });

  final int count;
  final int trigger;
  final VoidCallback? onCompleted;

  @override
  State<_BurstSurface> createState() => _BurstSurfaceState();
}

class _BurstSurfaceState extends State<_BurstSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _Burst.duration,
  )..addStatusListener(_onStatus);

  late _Burst _burst = _Burst.spawn(widget.count, seed: 1);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || widget.trigger == 0) return;
    _started = true;
    if (!MediaQuery.disableAnimationsOf(context)) _play();
  }

  @override
  void didUpdateWidget(covariant _BurstSurface old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) _play();
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final done = widget.onCompleted;
    if (done == null) return;
    // Deferred by a frame so the overlay entry is not removed from inside the
    // controller's own notification.
    WidgetsBinding.instance.addPostFrameCallback((_) => done());
  }

  void _play() {
    _burst = _Burst.spawn(
      widget.count,
      seed: DateTime.now().microsecondsSinceEpoch,
    );
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _BurstPainter(
              burst: _burst,
              progress: _c.value,
              palette: [cs.primary, cs.secondary, cs.tertiary],
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

/// One run of the particle simulation.
class _Burst {
  const _Burst._(this.particles);

  static const duration = Duration(milliseconds: 2200);
  static const gravity = 640.0;
  static const drag = 1.9;

  /// Where the poppers sit, in the surface's own coordinates. Inset from the
  /// corners and low down, so the cloud crosses the screen rather than
  /// hugging its edges.
  static const origins = [Alignment(-0.84, 0.94), Alignment(0.84, 0.94)];

  /// The cone each popper fires into, in radians measured from the positive
  /// x axis. The left one throws up and to the right; the right one mirrors
  /// it. Both stay above the horizon, because a particle fired downwards is
  /// gone before it is seen.
  static const _cones = [
    (-math.pi * 0.62, -math.pi * 0.22),
    (-math.pi * 0.78, -math.pi * 0.38),
  ];

  final List<_Particle> particles;

  static _Burst spawn(int count, {required int seed}) {
    final rnd = math.Random(seed);
    return _Burst._([
      for (var i = 0; i < count; i++)
        // Alternate the popper so the two sides fill at the same rate.
        _Particle.random(rnd, origin: i % origins.length),
    ]);
  }
}

class _Particle {
  const _Particle({
    required this.originIndex,
    required this.offset,
    required this.velocity,
    required this.size,
    required this.stretch,
    required this.spin,
    required this.angle,
    required this.delay,
    required this.colorIndex,
    required this.round,
  });

  /// Weighted towards the primary pair so the burst stays in the app's
  /// palette; tertiary is seasoning, not the base.
  static const _weights = [0, 0, 0, 1, 1, 2];

  factory _Particle.random(math.Random rnd, {required int origin}) {
    final (from, to) = _Burst._cones[origin];
    final direction = from + rnd.nextDouble() * (to - from);
    final speed = 620 + rnd.nextDouble() * 560;
    return _Particle(
      originIndex: origin,
      offset: Offset(rnd.nextDouble() * 14 - 7, rnd.nextDouble() * 10 - 5),
      velocity: Offset(
        math.cos(direction) * speed,
        math.sin(direction) * speed,
      ),
      size: 3.5 + rnd.nextDouble() * 4.5,
      // A few long ticks among the short ones: confetti that is all one shape
      // reads as noise.
      stretch: rnd.nextDouble() < 0.22 ? 2.6 : 1.0,
      spin: (rnd.nextDouble() - 0.5) * 11,
      angle: rnd.nextDouble() * math.pi,
      // Up to a fifth of a second of spread. The bloom is the difference
      // between a cracker and a splash.
      delay: rnd.nextDouble() * 0.19,
      colorIndex: _weights[rnd.nextInt(_weights.length)],
      round: rnd.nextBool() && rnd.nextDouble() < 0.4,
    );
  }

  final int originIndex;
  final Offset offset;
  final Offset velocity;
  final double size;
  final double stretch;
  final double spin;
  final double angle;
  final double delay;
  final int colorIndex;
  final bool round;
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({
    required this.burst,
    required this.progress,
    required this.palette,
  });

  final _Burst burst;
  final double progress;
  final List<Color> palette;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;

    final seconds = progress * _Burst.duration.inMilliseconds / 1000;
    final shortest = size.shortestSide;
    final origins = [
      for (final a in _Burst.origins) a.withinRect(Offset.zero & size),
    ];

    _paintFlash(canvas, origins, shortest);
    _paintParticles(canvas, origins, seconds);
  }

  /// The pop: a flash and a ring at each popper, gone inside the first third
  /// of the burst.
  ///
  /// Without it the particles simply exist from the first frame, which is what
  /// made the old burst read as a splash rather than as something that fired.
  void _paintFlash(Canvas canvas, List<Offset> origins, double shortest) {
    final t = (progress / 0.32).clamp(0.0, 1.0);
    if (t >= 1) return;
    final ease = Curves.easeOutCubic.transform(t);

    for (final origin in origins) {
      final glow = Paint()
        ..shader =
            RadialGradient(
              colors: [
                palette.first.withValues(alpha: 0.45 * (1 - t)),
                palette.first.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromCircle(center: origin, radius: shortest * 0.24),
            );
      canvas.drawCircle(origin, shortest * 0.24, glow);

      canvas.drawCircle(
        origin,
        shortest * (0.03 + 0.24 * ease),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5 * (1 - ease) + 0.5
          ..color = palette.first.withValues(alpha: 0.55 * (1 - ease)),
      );
    }
  }

  void _paintParticles(Canvas canvas, List<Offset> origins, double seconds) {
    // Closed-form drag: velocity decays exponentially, so the cloud blooms
    // outward and then slows instead of travelling at a constant speed.
    final paint = Paint();
    final floor = origins.first.dy;

    for (final p in burst.particles) {
      final age = seconds - p.delay;
      if (age <= 0) continue;

      final travel = (1 - math.exp(-_Burst.drag * age)) / _Burst.drag;
      final fall = 0.5 * _Burst.gravity * age * age;
      final origin = origins[p.originIndex];
      final x = origin.dx + p.offset.dx + p.velocity.dx * travel;
      final y = origin.dy + p.offset.dy + p.velocity.dy * travel + fall;

      // A particle fades as it drops out of frame rather than on a shared
      // clock: a fixed cut-off made the whole cloud vanish in mid-air.
      final below = ((y - floor) / (floor * 0.9)).clamp(0.0, 1.0);
      final alpha = (1 - below) * 0.92;
      if (alpha <= 0.02) continue;

      final shrink = 1 - 0.28 * progress;
      paint.color = palette[p.colorIndex % palette.length].withValues(
        alpha: alpha,
      );

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.angle + p.spin * age);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size * 0.5 * shrink, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.size * p.stretch * shrink,
              height: p.size * 0.6 * shrink,
            ),
            const Radius.circular(1.4),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) =>
      old.progress != progress ||
      old.burst != burst ||
      !listEquals(old.palette, palette);
}
