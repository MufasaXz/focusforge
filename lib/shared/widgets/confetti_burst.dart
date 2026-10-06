import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';


/// A single burst of particles, drawn by hand.
///
/// The `confetti` package is available, but its defaults — long rainbow ribbons
/// that keep falling — fight the rest of the interface. The particles here are
/// short ticks in the app's own accent palette, which reads as a quiet "well
/// done" rather than a party popper. Positions are closed-form functions of
/// time, so nothing is integrated frame to frame and the burst looks the same
/// on a janky frame as on a smooth one.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key, this.trigger = 0, this.particleCount = 60});

  /// Bump this to fire. A burst also plays when the widget mounts with a
  /// non-zero trigger, which covers the "insert it when the event happens"
  /// usage as well as the "keep it mounted and count" one.
  final int trigger;

  final int particleCount;

  /// Fires a one-shot burst over the nearest [Overlay] and removes it when the
  /// animation has finished.
  static void fire(BuildContext context, {int particles = 60}) {
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
              palette: [cs.primary, cs.secondary, cs.tertiary, cs.tertiary],
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

  static const duration = Duration(milliseconds: 1500);
  static const gravity = 520.0;
  static const drag = 2.4;

  final List<_Particle> particles;

  static _Burst spawn(int count, {required int seed}) {
    final rnd = math.Random(seed);
    return _Burst._([for (var i = 0; i < count; i++) _Particle.random(rnd)]);
  }
}

class _Particle {
  const _Particle({
    required this.offset,
    required this.velocity,
    required this.size,
    required this.spin,
    required this.angle,
    required this.colorIndex,
    required this.round,
  });

  /// Weighted towards the accent pair so the burst stays in the app's palette;
  /// success and gold are seasoning, not the base.
  static const _weights = [0, 0, 0, 1, 1, 2, 3];

  factory _Particle.random(math.Random rnd) {
    final direction = rnd.nextDouble() * 2 * math.pi;
    final speed = 170 + rnd.nextDouble() * 430;
    return _Particle(
      offset: Offset(rnd.nextDouble() * 12 - 6, rnd.nextDouble() * 12 - 6),
      // A little upward bias so the cloud arcs instead of splashing flat.
      velocity: Offset(
        math.cos(direction) * speed,
        math.sin(direction) * speed - 150,
      ),
      size: 3.5 + rnd.nextDouble() * 4.5,
      spin: (rnd.nextDouble() - 0.5) * 9,
      angle: rnd.nextDouble() * math.pi,
      colorIndex: _weights[rnd.nextInt(_weights.length)],
      round: rnd.nextBool(),
    );
  }

  final Offset offset;
  final Offset velocity;
  final double size;
  final double spin;
  final double angle;
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
    final origin = size.center(Offset.zero);
    final fade = progress < 0.55
        ? 1.0
        : (1 - (progress - 0.55) / 0.45).clamp(0.0, 1.0);
    // Closed-form drag: velocity decays exponentially, so the cloud blooms
    // outward and then slows instead of travelling at a constant speed.
    final travel = (1 - math.exp(-_Burst.drag * seconds)) / _Burst.drag;
    final fall = 0.5 * _Burst.gravity * seconds * seconds;
    final shrink = 1 - 0.3 * progress;

    final paint = Paint();
    for (final p in burst.particles) {
      final x = origin.dx + p.offset.dx + p.velocity.dx * travel;
      final y = origin.dy + p.offset.dy + p.velocity.dy * travel + fall;
      paint.color = palette[p.colorIndex % palette.length].withValues(
        alpha: fade * 0.9,
      );

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.angle + p.spin * seconds);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size * 0.5 * shrink, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.size * shrink,
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
