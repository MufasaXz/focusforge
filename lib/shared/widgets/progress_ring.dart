import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';


/// Circular progress ring with a gradient sweep, a glowing leading cap and an
/// optional ambient pulse.
///
/// The depth comes from two separately painted layers: a blurred bloom under
/// the arc, and the crisp gradient arc with a lit cap on top. [innerGlow] adds
/// a soft radial wash behind the child so the centre of the ring reads as
/// illuminated rather than empty.
///
/// The layers are split because blurring a stroked arc is one of the most
/// expensive things Skia can be asked to do, and the pulse used to force that
/// blur to be re-rasterised every frame. Now the bloom is painted once into its
/// own repaint boundary and the pulse only changes the opacity of the cached
/// picture — compositing is cheap, re-blurring is not.
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
    this.semanticLabel,
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

  /// Spoken in place of the ring, e.g. "3 hours 12 minutes of a 5 hour goal,
  /// 64 percent". The ring only knows the fraction, so a caller that knows the
  /// units should say so; otherwise the bare percentage is announced.
  final String? semanticLabel;

  @override
  State<ProgressRing> createState() => _ProgressRingState();
}

class _ProgressRingState extends State<ProgressRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant ProgressRing old) {
    super.didUpdateWidget(old);
    _syncPulse();
  }

  void _syncPulse() {
    final running = widget.pulse && !MediaQuery.disableAnimationsOf(context);
    if (running && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!running && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors = widget.colors ?? [cs.primary, cs.secondary];
    final reduce = MediaQuery.disableAnimationsOf(context);
    final value = widget.value.clamp(0.0, 1.0);

    final content = widget.innerGlow <= 0
        ? widget.child
        : DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  colors.first.withValues(alpha: 0.16 * widget.innerGlow),
                  colors.first.withValues(alpha: 0),
                ],
                stops: const [0, 0.85],
              ),
            ),
            child: Center(child: widget.child),
          );

    return Semantics(
      label: widget.semanticLabel ?? '${(value * 100).round()} percent',
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 1500),
        curve: Curves.easeOutCubic,
        builder: (context, animated, _) => AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final glow = !widget.pulse || reduce
                ? 0.7
                : 0.45 + 0.55 * _pulse.value;
            return SizedBox(
              width: widget.size,
              height: widget.size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: Opacity(
                      opacity: glow,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _GlowPainter(
                            value: animated,
                            stroke: widget.stroke,
                            colors: colors,
                          ),
                        ),
                      ),
                    ),
                  ),
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
                          dot: cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                  Center(child: content),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The blurred bloom: a wide pass, a tight pass and the halo around the leading
/// cap, all painted at full strength. The pulse scales the whole layer through
/// [Opacity] instead of repainting these paths.
class _GlowPainter extends CustomPainter {
  _GlowPainter({
    required this.value,
    required this.stroke,
    required this.colors,
  });

  final double value;
  final double stroke;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (value <= 0) return;

    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
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
        ..color = colors.first.withValues(alpha: 0.22),
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
        ..color = colors.first.withValues(alpha: 0.45),
    );

    final angle = -math.pi / 2 + sweep;
    final capCenter = Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );
    canvas.drawCircle(
      capCenter,
      stroke * 0.75,
      Paint()
        ..color = colors.last.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 0.7),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      old.value != value ||
      old.stroke != stroke ||
      !listEquals(old.colors, colors);
}

/// Track, ticks, the crisp arc and the leading dot — nothing blurred.
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
            colors: [Color.lerp(track, colors.first, 0.10)!, track],
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
    final cs = Theme.of(context).colorScheme;
    return ProgressRing(
      value: value,
      size: size,
      stroke: stroke,
      pulse: false,
      innerGlow: 0.25,
      colors: [color, Color.lerp(color, cs.secondary, 0.5)!],
      child: label == null
          ? null
          : Text(
              label!,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: cs.onSurface,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}
