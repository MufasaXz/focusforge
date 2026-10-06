import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/glass_theme.dart';

/// Circular progress ring with a gradient sweep, a glowing leading cap and an
/// optional ambient pulse.
///
/// The depth comes from three passes: a blurred bloom under the arc, the crisp
/// gradient arc, and a lit cap. [innerGlow] adds a soft radial wash behind the
/// child so the centre of the ring reads as illuminated rather than empty.
class ProgressRing extends StatefulWidget {
  const ProgressRing({
    super.key,
    required this.value,
    this.size = 180,
    this.stroke = 10,
    this.child,
    this.pulse = true,
    this.trackVisible = true,
    this.ticks = 0,
    this.colors,
    this.innerGlow = 0.5,
  });

  /// 0..1
  final double value;
  final double size;
  final double stroke;
  final Widget? child;

  /// Slow breathing glow while the ring is showing progress.
  final bool pulse;

  final bool trackVisible;

  /// Number of faint tick marks drawn just inside the track.
  final int ticks;

  /// Overrides the accent gradient (used by subject-coloured mini rings).
  final List<Color>? colors;

  /// 0..1 strength of the radial wash behind [child].
  final double innerGlow;

  @override
  State<ProgressRing> createState() => _ProgressRingState();
}

class _ProgressRingState extends State<ProgressRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final colors = widget.colors ?? [t.accentPrimary, t.accentSecondary];

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: widget.value.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) => CustomPaint(
          painter: _RingPainter(
            value: value,
            stroke: widget.stroke,
            colors: colors,
            track: t.track,
            trackVisible: widget.trackVisible,
            ticks: widget.ticks,
            glow: widget.pulse ? 0.45 + 0.55 * _pulse.value : 0.7,
            dot: t.textPrimary,
          ),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Center(
              child: widget.innerGlow <= 0
                  ? widget.child
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            colors.first
                                .withValues(alpha: 0.16 * widget.innerGlow),
                            colors.first.withValues(alpha: 0),
                          ],
                          stops: const [0, 0.85],
                        ),
                      ),
                      child: Center(child: widget.child),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.stroke,
    required this.colors,
    required this.track,
    required this.trackVisible,
    required this.ticks,
    required this.glow,
    required this.dot,
  });

  final double value;
  final double stroke;
  final List<Color> colors;
  final Color track;
  final bool trackVisible;
  final int ticks;
  final double glow;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    if (trackVisible) {
      // Slightly lighter at the top, so even the empty track has a light
      // direction.
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(track, colors.first, 0.10)!,
              track,
            ],
          ).createShader(rect),
      );
    }

    if (ticks > 0) {
      final tickPaint = Paint()
        ..color = track.withValues(alpha: track.a * 1.6)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      final tickRadius = radius - stroke * 0.95;
      for (var i = 0; i < ticks; i++) {
        final a = -math.pi / 2 + (2 * math.pi * i / ticks);
        final inner = Offset(
          center.dx + (tickRadius - 4) * math.cos(a),
          center.dy + (tickRadius - 4) * math.sin(a),
        );
        final outer = Offset(
          center.dx + tickRadius * math.cos(a),
          center.dy + tickRadius * math.sin(a),
        );
        canvas.drawLine(inner, outer, tickPaint);
      }
    }

    if (value <= 0) return;

    final sweep = 2 * math.pi * value;
    final shader = SweepGradient(
      startAngle: -math.pi / 2,
      endAngle: 3 * math.pi / 2,
      colors: [colors.first, colors.last],
    ).createShader(rect);

    final arc = Path()..addArc(rect, -math.pi / 2, sweep);

    // Wide, soft bloom.
    canvas.drawPath(
      arc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 2.2
        ..strokeCap = StrokeCap.round
        ..shader = shader
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 1.5)
        ..color = colors.first.withValues(alpha: 0.22 * glow),
    );

    // Tight bloom hugging the stroke.
    canvas.drawPath(
      arc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 1.4
        ..strokeCap = StrokeCap.round
        ..shader = shader
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 0.55)
        ..color = colors.first.withValues(alpha: 0.45 * glow),
    );

    // Crisp arc.
    canvas.drawPath(
      arc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );

    // Leading cap.
    final angle = -math.pi / 2 + sweep;
    final capCenter = Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );
    canvas.drawCircle(
      capCenter,
      stroke * 0.75,
      Paint()
        ..color = colors.last.withValues(alpha: 0.55 * glow)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 0.7),
    );
    canvas.drawCircle(capCenter, stroke * 0.32, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value ||
      old.glow != glow ||
      old.stroke != stroke ||
      old.colors != colors ||
      old.track != track ||
      old.ticks != ticks;
}

/// Compact ring for goals and subject targets.
class MiniRing extends StatelessWidget {
  const MiniRing({
    super.key,
    required this.value,
    required this.color,
    this.size = 56,
    this.stroke = 5,
    this.label,
  });

  final double value;
  final Color color;
  final double size;
  final double stroke;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    return ProgressRing(
      value: value,
      size: size,
      stroke: stroke,
      pulse: false,
      innerGlow: 0.25,
      colors: [color, Color.lerp(color, t.accentSecondary, 0.5)!],
      child: label == null
          ? null
          : Text(
              label!,
              style: context.type.labelMedium?.copyWith(
                color: t.textPrimary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}
