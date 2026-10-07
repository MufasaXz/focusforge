import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';

/// The daily-goal ring: the app's own mark, filled by the day's focus.
///
/// The arc carries the brand gradient rather than a scheme role — this is the
/// one gauge in the app that is identity first — and it is drawn without the
/// leading cap dot the timer ring wears: at this stroke the round cap is
/// already the terminal, and a dot on top of it reads as a bead on a wire.
///
/// [value] is drawn from the day's own reading, so the ring moves while a
/// block is running and settles when it is banked.
class GoalRing extends StatelessWidget {
  const GoalRing({
    super.key,
    required this.value,
    required this.child,
    this.size = 224,
    this.stroke = 16,
    this.semanticLabel,
  });

  /// 0..1.
  final double value;
  final Widget child;
  final double size;
  final double stroke;

  /// Spoken in place of the ring — the painter only knows the fraction, so a
  /// caller that knows the units says so.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final target = value.clamp(0.0, 1.0);

    return Semantics(
      label: semanticLabel ?? '${(target * 100).round()} percent',
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: target),
        // Short on purpose: the value ticks up while a block runs, and a long
        // tween would still be chasing the previous second when the next
        // arrives.
        duration: reduce ? Duration.zero : const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, animated, _) => SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _GoalRingPainter(
                      value: animated,
                      stroke: stroke,
                      colors: GoalRingPalette.forBrightness(brightness),
                      track: cs.surfaceContainerHighest,
                    ),
                  ),
                ),
              ),
              Center(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalRingPainter extends CustomPainter {
  const _GoalRingPainter({
    required this.value,
    required this.stroke,
    required this.colors,
    required this.track,
  });

  final double value;
  final double stroke;
  final List<Color> colors;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );

    if (value <= 0) return;

    // The gradient is fixed to the circle rather than to the arc, so the sweep
    // reads the same colour at the same angle however far the day has got —
    // which is what keeps a 20% morning and a 90% evening the same gauge.
    canvas.drawPath(
      Path()..addArc(rect, -math.pi / 2, 2 * math.pi * value),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: 3 * math.pi / 2,
          colors: colors,
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GoalRingPainter old) =>
      old.value != value ||
      old.stroke != stroke ||
      old.track != track ||
      !listEquals(old.colors, colors);
}

/// The sprout above the readout — the app's mark, drawn rather than set in a
/// glyph so its weight keeps up with the ring at any size.
class SproutMark extends StatelessWidget {
  const SproutMark({super.key, this.size = 28, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _SproutPainter(color)),
  );
}

class _SproutPainter extends CustomPainter {
  const _SproutPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // The mark is designed on a 24 unit grid and scaled from there.
    final s = size.shortestSide / 24;
    final paint = Paint()..color = color;

    // The stem first, so the leaves sit over its top.
    canvas.drawLine(
      Offset(12 * s, 22.2 * s),
      Offset(12 * s, 15.2 * s),
      Paint()
        ..color = color
        ..strokeWidth = 1.6 * s
        ..strokeCap = StrokeCap.round,
    );

    _leaf(
      canvas,
      paint,
      base: Offset(11.4 * s, 16.6 * s),
      angle: -1.20,
      length: 8.2 * s,
      width: 0.36,
    );
    _leaf(
      canvas,
      paint,
      base: Offset(12.6 * s, 16.6 * s),
      angle: 1.20,
      length: 8.2 * s,
      width: 0.36,
    );
    // Last, so the pair tucks under it rather than crowding its base.
    _leaf(
      canvas,
      paint,
      base: Offset(12 * s, 14.6 * s),
      angle: 0,
      length: 11.4 * s,
      width: 0.32,
    );
  }

  /// One pointed leaf growing from [base] at [angle] — zero points straight
  /// up, and [width] is its half-width as a fraction of its length.
  ///
  /// Widest a little under halfway up and tapered at both ends: a leaf that
  /// stayed wide at its base would merge into the two beside it, and three
  /// leaves in a heap read as one blob rather than as a sprout.
  void _leaf(
    Canvas canvas,
    Paint paint, {
    required Offset base,
    required double angle,
    required double length,
    required double width,
  }) {
    final w = length * width;
    final path = Path()
      ..moveTo(0, -length)
      ..quadraticBezierTo(-w * 0.42, -length * 0.86, -w, -length * 0.44)
      ..quadraticBezierTo(-w * 0.66, -length * 0.10, 0, 0)
      ..quadraticBezierTo(w * 0.66, -length * 0.10, w, -length * 0.44)
      ..quadraticBezierTo(w * 0.42, -length * 0.86, 0, -length)
      ..close();

    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(angle);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SproutPainter old) => old.color != color;
}
