import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

/// Related glass surfaces share a backdrop group to reuse the blur.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final black = cs.surface == const Color(0xFF000000);
    return BackdropGroup(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surface,
          gradient: black
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    cs.surface,
                    Color.alphaBlend(
                      cs.primary.withValues(alpha: dark ? 0.055 : 0.045),
                      cs.surface,
                    ),
                    cs.surfaceContainerLow,
                  ],
                ),
        ),
        child: child,
      ),
    );
  }
}

/// Frosted material with a bright upper rim and a quiet lower shadow.
/// Only the background is blurred; text, charts and taps stay crisp.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.color,
    this.shape,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final Color? color;
  final ShapeBorder? shape;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final black = cs.surface == const Color(0xFF000000);
    final edge =
        shape ??
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card));
    final tint = color ?? cs.surfaceContainerLow;
    return Container(
      decoration: ShapeDecoration(
        shape: edge,
        shadows: black
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.20 : 0.045),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: edge),
        clipBehavior: clipBehavior,
        child: BackdropFilter.grouped(
          enabled: !black,
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              shape: edge,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                    Colors.white.withValues(alpha: dark ? 0.065 : 0.52),
                    tint,
                  ).withValues(alpha: black ? 1 : 0.78),
                  tint.withValues(alpha: black ? 1 : 0.62),
                ],
              ),
            ),
            child: CustomPaint(
              foregroundPainter: _GlassEdge(
                shape: edge,
                top: Colors.white.withValues(alpha: dark ? 0.16 : 0.88),
                bottom: cs.outlineVariant.withValues(alpha: 0.30),
              ),
              child: Material(type: MaterialType.transparency, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassEdge extends CustomPainter {
  const _GlassEdge({
    required this.shape,
    required this.top,
    required this.bottom,
  });

  final ShapeBorder shape;
  final Color top;
  final Color bottom;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.5);
    canvas.drawPath(
      shape.getOuterPath(rect),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, bottom],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GlassEdge old) =>
      old.shape != shape || old.top != top || old.bottom != bottom;
}
