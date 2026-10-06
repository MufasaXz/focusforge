import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The FocusForge mark.
///
/// A focus reticle: a ring broken by a gap — the same progress ring the
/// dashboard is built around — around a solid core. It is drawn rather than
/// shipped as a bitmap so it stays crisp at every size it is used at, from the
/// 28px chip in a list to the 108px badge on the start screen, and so the
/// launcher icon can be rendered from exactly the same geometry.
///
/// It reads as a mark rather than an illustration on purpose: two shapes, one
/// weight, no gradient and no shadow, so it survives being scaled down to a
/// notification icon without turning to mush.
class AppMark extends StatelessWidget {
  const AppMark({
    super.key,
    this.size = 40,
    this.background,
    this.foreground,
    this.semanticLabel,
  });

  final double size;

  /// Defaults to the scheme's primary. The launcher icon passes the seed
  /// directly, because a launcher icon is not themed.
  final Color? background;
  final Color? foreground;

  /// Decorative by default — the mark normally sits above or beside the app
  /// name. Pass a label only where the mark is the only thing carrying it.
  final String? semanticLabel;

  /// The seed the whole app is tinted from. Named here so the icon generator
  /// and the theme cannot drift apart.
  static const seed = Color(0xFFE8672A);

  /// Corner radius as a fraction of the side. Matches the mask Android and iOS
  /// apply to a launcher icon, so the drawn square is not visibly double
  /// rounded.
  static const _cornerRatio = 0.235;

  /// How much of the ring is missing, as a fraction of a full turn. Small
  /// enough that the shape still reads as a ring at 24px rather than as an
  /// open C.
  static const _gapRatio = 0.155;

  /// The gap is centred on the top of the ring.
  static const _gapCentre = -math.pi / 2;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = background ?? cs.primary;
    final fg = foreground ?? cs.onPrimary;

    final mark = SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _MarkPainter(background: bg, foreground: fg),
        isComplex: false,
      ),
    );

    if (semanticLabel == null) return ExcludeSemantics(child: mark);
    return Semantics(label: semanticLabel, image: true, child: mark);
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.background, required this.foreground});

  final Color background;
  final Color foreground;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    if (s <= 0) return;
    final centre = Offset(size.width / 2, size.height / 2);

    // The plate.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(s * AppMark._cornerRatio),
      ),
      Paint()..color = background,
    );

    // The ring, with its gap centred on the top so the mark has an obvious
    // "up" and reads the same at every size.
    final gap = 2 * math.pi * AppMark._gapRatio;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.085
      ..strokeCap = StrokeCap.round
      ..color = foreground;
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: s * 0.285),
      AppMark._gapCentre + gap / 2,
      2 * math.pi - gap,
      false,
      ring,
    );

    // The core. Solid, so the centre of the mark has a definite point of focus
    // rather than being an empty hole.
    canvas.drawCircle(centre, s * 0.115, Paint()..color = foreground);
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.background != background || old.foreground != foreground;
}
