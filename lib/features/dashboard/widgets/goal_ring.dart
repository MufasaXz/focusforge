import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';

/// Completed focus fills the daily-goal ring; the center stays readable.
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

    // Fine inner markers make small gains easy to judge.
    for (var i = 0; i < 48; i++) {
      final angle = i * math.pi / 24 - math.pi / 2;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + direction * (radius - stroke - (i % 4 == 0 ? 6 : 3)),
        center + direction * (radius - stroke),
        Paint()
          ..color = track
          ..strokeWidth = i % 4 == 0 ? 1.6 : 1,
      );
    }
    canvas.drawCircle(
      center + const Offset(0, 2),
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + 2
        ..color = Colors.black.withValues(alpha: .06)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
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
          transform: const GradientRotation(-math.pi / 2),
          colors: [...colors, colors.first],
        ).createShader(rect),
    );
    // A slim highlight gives the filled arc a rounded, softly lit edge.
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius + stroke * .27),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: .28),
    );
    if (value < .995) {
      final angle = value * 2 * math.pi - math.pi / 2;
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * radius,
        stroke * .16,
        Paint()..color = Colors.white.withValues(alpha: .85),
      );
    }
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
    canvas.save();
    canvas.scale(size.shortestSide / 32);
    final stem = Path()
      ..moveTo(16, 29)
      ..cubicTo(15, 23, 17, 16, 22, 10);
    canvas.drawPath(
      stem,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round,
    );
    final leaves = [
      Path()
        ..moveTo(16, 21)
        ..cubicTo(6, 22, 3, 15, 4, 9)
        ..cubicTo(12, 9, 18, 12, 16, 21)
        ..close(),
      Path()
        ..moveTo(17, 17)
        ..cubicTo(15, 7, 22, 3, 29, 3)
        ..cubicTo(29, 11, 25, 17, 17, 17)
        ..close(),
    ];
    for (final leaf in leaves) {
      canvas.drawPath(
        leaf,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color.lerp(color, Colors.white, .22)!, color],
          ).createShader(const Rect.fromLTWH(3, 3, 26, 21)),
      );
    }
    final vein = Paint()
      ..color = Colors.white.withValues(alpha: .35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(7, 12)
        ..quadraticBezierTo(11, 13, 15, 19),
      vein,
    );
    canvas.drawPath(
      Path()
        ..moveTo(19, 14)
        ..quadraticBezierTo(22, 9, 26, 6),
      vein,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SproutPainter old) => old.color != color;
}
