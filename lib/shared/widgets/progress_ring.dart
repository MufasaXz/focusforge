import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Circular progress ring: a tonal track, a sweep-gradient arc and a leading
/// cap dot.
///
/// There is deliberately no bloom under the arc. A blurred stroke is one of the
/// most expensive things Skia can be asked to draw, and at Material 3's contrast
/// levels the crisp arc already reads as the foreground — the glow was adding a
/// raster cost and a colour cast without adding legibility.
class ProgressRing extends StatefulWidget {
  const ProgressRing({
    super.key,
    required this.value,
    this.size = 180,
    this.stroke = 10,
    this.child,
    this.trackVisible = true,
    this.ticks = 0,
    this.colors,
    this.semanticLabel,
  });

  /// 0..1
  final double value;
  final double size;
  final double stroke;
  final Widget? child;

  final bool trackVisible;

  /// Number of faint tick marks drawn just inside the track.
  final int ticks;

  /// Overrides the arc gradient (used by subject-coloured mini rings).
  final List<Color>? colors;

  /// Spoken in place of the ring, e.g. "3 hours 12 minutes of a 5 hour goal,
  /// 64 percent". The ring only knows the fraction, so a caller that knows the
  /// units should say so; otherwise the bare percentage is announced.
  final String? semanticLabel;

  @override
  State<ProgressRing> createState() => _ProgressRingState();
}

class _ProgressRingState extends State<ProgressRing> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors = widget.colors ?? [cs.primary, cs.tertiary];
    final reduce = MediaQuery.disableAnimationsOf(context);
    final value = widget.value.clamp(0.0, 1.0);

    return Semantics(
      label: widget.semanticLabel ?? '${(value * 100).round()} percent',
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 1500),
        curve: Curves.easeOutCubic,
        builder: (context, animated, _) => SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _RingPainter(
                      value: animated,
                      stroke: widget.stroke,
                      colors: colors,
                      track: cs.surfaceContainerHighest,
                      trackVisible: widget.trackVisible,
                      ticks: widget.ticks,
                      dot: cs.primary,
                    ),
                  ),
                ),
              ),
              if (widget.child != null) Center(child: widget.child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Track, ticks, the crisp arc and the leading dot.
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.stroke,
    required this.colors,
    required this.track,
    required this.trackVisible,
    required this.ticks,
    required this.dot,
  });

  final double value;
  final double stroke;
  final List<Color> colors;
  final Color track;
  final bool trackVisible;
  final int ticks;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    if (trackVisible) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = track,
      );
    }

    if (ticks > 0) {
      final tickPaint = Paint()
        ..color = track.withValues(alpha: 0.9)
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

    canvas.drawPath(
      arc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );

    final angle = -math.pi / 2 + sweep;
    final capCenter = Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );
    canvas.drawCircle(capCenter, stroke * 0.32, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value ||
      old.stroke != stroke ||
      !listEquals(old.colors, colors) ||
      old.track != track ||
      old.trackVisible != trackVisible ||
      old.ticks != ticks ||
      old.dot != dot;
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
    final theme = Theme.of(context);
    return ProgressRing(
      value: value,
      size: size,
      stroke: stroke,
      colors: [color, Color.lerp(color, theme.colorScheme.tertiary, 0.5)!],
      child: label == null
          ? null
          : Text(
              label!,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}
