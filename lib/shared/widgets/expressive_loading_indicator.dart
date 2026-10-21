import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A small morphing shape for indeterminate account work.
class ExpressiveLoadingIndicator extends StatefulWidget {
  const ExpressiveLoadingIndicator({super.key, this.size = 48});
  final double size;

  @override
  State<ExpressiveLoadingIndicator> createState() =>
      _ExpressiveLoadingIndicatorState();
}

class _ExpressiveLoadingIndicatorState extends State<ExpressiveLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.stop();
      _motion.value = 0;
    } else {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: widget.size,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _motion,
          builder: (context, _) => CustomPaint(
            painter: _ShapePainter(
              _motion.value,
              Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
    ),
  );
}

class _ShapePainter extends CustomPainter {
  const _ShapePainter(this.progress, this.color);
  final double progress;
  final Color color;

  double _radius(int shape, double angle) => switch (shape % 4) {
    0 => 0.88,
    1 => 0.78 + 0.16 * math.cos(4 * angle),
    2 => 0.78 + 0.16 * math.cos(5 * angle),
    _ => 0.82 + 0.12 * math.cos(3 * angle),
  };

  @override
  void paint(Canvas canvas, Size size) {
    final phase = progress * 4;
    final shape = phase.floor();
    final blend = Curves.easeInOutCubic.transform(phase - shape);
    final path = Path();
    final center = size.center(Offset.zero);
    for (var i = 0; i <= 96; i++) {
      final angle = i * math.pi * 2 / 96;
      final radius =
          (_radius(shape, angle) * (1 - blend) +
              _radius(shape + 1, angle) * blend) *
          size.shortestSide /
          2;
      final turn = angle + progress * math.pi * 2;
      final point = center + Offset(math.cos(turn), math.sin(turn)) * radius;
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ShapePainter oldDelegate) =>
      progress != oldDelegate.progress || color != oldDelegate.color;
}
