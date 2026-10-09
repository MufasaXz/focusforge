import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

/// A decorative preview of a focus block; never presented as a live session.
class FocusPreview extends StatelessWidget {
  const FocusPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: MediaQuery.withNoTextScaling(
        child: SizedBox(
          height: 180,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(280, 180),
                painter: _PreviewPainter(cs),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.spa_outlined, size: 20, color: cs.primary),
                  const SizedBox(height: Gap.sm),
                  Text(
                    '25:00',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      letterSpacing: -2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: Gap.xs),
                  Text(
                    'ONE CLEAR PRIORITY',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                      letterSpacing: 1.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  const _PreviewPainter(this.cs);
  final ColorScheme cs;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: center, radius: 79);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(
      center,
      79,
      stroke..color = cs.primary.withValues(alpha: .12),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 1.55,
      false,
      stroke..color = cs.primary,
    );
    for (var i = 0; i < 3; i++) {
      final x = i.isEven ? center.dx - 112 : center.dx + 112;
      final y = 45.0 + i * 45;
      canvas.drawCircle(
        Offset(x, y),
        4 + i.toDouble(),
        Paint()..color = cs.tertiary.withValues(alpha: .3),
      );
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter oldDelegate) => oldDelegate.cs != cs;
}
