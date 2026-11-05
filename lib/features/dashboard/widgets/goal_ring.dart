import '../../../core/localization/app_strings.dart';

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';

/// Completed focus fills the daily-goal ring; the center stays readable.
///
/// The ring moves in two ways. The fill follows the day: it sweeps up from
/// empty the first time the ring is drawn and glides to each new value after
/// that. And every [milestone] the day reaches — every five focused minutes on
/// Home, and every finished block — it celebrates: a light runs along the
/// filled arc to its head, the head pops, and a thin ripple leaves the ring.
/// The markers inside light up as the fill passes them. None of it runs with
/// reduce-motion on, and none of it is a glow: every effect is a crisp stroke.
class GoalRing extends StatefulWidget {
  const GoalRing({
    super.key,
    required this.value,
    required this.child,
    this.size = 224,
    this.stroke = 16,
    this.semanticLabel,
    this.milestone,
  });

  /// 0..1.
  final double value;
  final Widget child;
  final double size;
  final double stroke;

  /// Spoken in place of the ring — the painter only knows the fraction, so a
  /// caller that knows the units says so.
  final String? semanticLabel;

  /// A count that rises as the day does, such as focused minutes in steps of
  /// five. Each rise plays the celebration once; null never celebrates.
  final int? milestone;

  @override
  State<GoalRing> createState() => _GoalRingState();
}

class _GoalRingState extends State<GoalRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  /// The first fill is the ring's entrance: slower and emphasised. After
  /// that the value ticks up while a block runs, and a long tween would
  /// still be chasing the previous second when the next arrives.
  Duration _fill = const Duration(milliseconds: 1300);
  Curve _curve = Motion.emphasized;

  @override
  void didUpdateWidget(covariant GoalRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _fill = const Duration(milliseconds: 700);
      _curve = Curves.easeOutCubic;
    }
    final before = oldWidget.milestone;
    final now = widget.milestone;
    if (before != null &&
        now != null &&
        now > before &&
        !MediaQuery.disableAnimationsOf(context)) {
      _pulse.forward(from: 0);
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
    final brightness = Theme.of(context).brightness;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final target = widget.value.clamp(0.0, 1.0);

    return Semantics(
      label:
          widget.semanticLabel ??
          context.tr("{0} percent", [(target * 100).round()]),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: target),
        duration: reduce ? Duration.zero : _fill,
        curve: _curve,
        builder: (context, animated, child) => SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) => CustomPaint(
                      painter: _GoalRingPainter(
                        value: animated,
                        pulse: reduce || !_pulse.isAnimating ? 0 : _pulse.value,
                        stroke: widget.stroke,
                        colors: GoalRingPalette.forBrightness(brightness),
                        track: cs.surfaceContainerHighest,
                        // From the ink rather than the track: on a pure-black
                        // screen the track is #1A1A1A, and markers drawn in
                        // it vanished.
                        tick: cs.onSurfaceVariant.withValues(
                          alpha: brightness == Brightness.dark ? 0.38 : 0.32,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Center(child: child),
            ],
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

class _GoalRingPainter extends CustomPainter {
  const _GoalRingPainter({
    required this.value,
    required this.pulse,
    required this.stroke,
    required this.colors,
    required this.track,
    required this.tick,
  });

  final double value;

  /// 0..1 through a milestone's celebration, or 0 when none is playing.
  final double pulse;
  final double stroke;
  final List<Color> colors;
  final Color track;
  final Color tick;

  static const _start = -math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = 2 * math.pi * value;
    final lit = Color.lerp(tick, colors.first, .85)!;

    // Fine inner markers make small gains easy to judge. The ones the fill
    // has passed take the ring's colour, so the day reads on the inside too.
    for (var i = 0; i < 48; i++) {
      final angle = i * math.pi / 24 + _start;
      final passed = value > 0 && i / 48 <= value;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + direction * (radius - stroke - (i % 4 == 0 ? 6 : 3)),
        center + direction * (radius - stroke),
        Paint()
          ..color = passed ? lit : tick
          ..strokeWidth = i % 4 == 0 ? 1.6 : 1
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );

    // The ripple leaves the ring's outer edge and fades as it goes: a ring
    // of stroke, never a blur.
    if (pulse > 0) {
      final out = Curves.easeOutCubic.transform(pulse);
      canvas.drawCircle(
        center,
        radius + stroke / 2 + stroke * 0.9 * out,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - out) + 0.5
          ..color = colors.first.withValues(alpha: 0.55 * (1 - out)),
      );
    }

    if (value <= 0) return;

    // The gradient is fixed to the circle rather than to the arc, so the sweep
    // reads the same colour at the same angle however far the day has got —
    // which is what keeps a 20% morning and a 90% evening the same gauge.
    canvas.drawPath(
      Path()..addArc(rect, _start, sweep),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          transform: const GradientRotation(_start),
          colors: [...colors, colors.first],
        ).createShader(rect),
    );
    // A slim highlight gives the filled arc a rounded, softly lit edge.
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius + stroke * .27),
      _start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: .28),
    );

    // The light: a short bright band that runs from the start of the fill to
    // its head over the first two-thirds of the celebration, then fades.
    if (pulse > 0) {
      final travel = Curves.easeInOutCubic.transform(
        (pulse / .66).clamp(0.0, 1.0),
      );
      final fade = pulse < .66 ? 1.0 : 1 - (pulse - .66) / .34;
      const band = 0.55;
      final head = _start + sweep * travel;
      final tail = math.max(_start, head - band);
      if (head > tail) {
        canvas.drawArc(
          rect,
          tail,
          head - tail,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke * 0.62
            ..strokeCap = StrokeCap.round
            ..shader = SweepGradient(
              transform: GradientRotation(tail),
              endAngle: head - tail,
              colors: [
                Colors.white.withValues(alpha: 0),
                Colors.white.withValues(alpha: 0.75 * fade),
              ],
            ).createShader(rect),
        );
      }
    }

    if (value < .995) {
      final angle = sweep + _start;
      // The head pops as the light reaches it, then settles.
      final pop = pulse <= .5
          ? 0.0
          : math.sin(math.pi * ((pulse - .5) / .5).clamp(0.0, 1.0));
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * radius,
        stroke * (.16 + .16 * pop),
        Paint()..color = Colors.white.withValues(alpha: .85),
      );
    }
  }

  @override
  bool shouldRepaint(_GoalRingPainter old) =>
      old.value != value ||
      old.pulse != pulse ||
      old.stroke != stroke ||
      old.track != track ||
      old.tick != tick ||
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
