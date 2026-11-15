import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/models/study_avatar.dart';

/// Original vector portraits, drawn locally at any pixel density.
class StudyPortrait extends StatelessWidget {
  const StudyPortrait({super.key, required this.avatar, this.size = 80});
  final StudyAvatar avatar;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: ClipOval(child: CustomPaint(painter: StudyPortraitPainter(avatar))),
  );
}

class StudyPortraitPainter extends CustomPainter {
  const StudyPortraitPainter(this.avatar);
  final StudyAvatar avatar;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    const ink = Color(0xFF182331);
    const cream = Color(0xFFFFF2DE);
    final c = avatar.color;
    final accent = Color.lerp(c, Colors.white, .62)!;
    void oval(Rect r, Color color) =>
        canvas.drawOval(r, Paint()..color = color);
    void circle(double x, double y, double radius, Color color) =>
        canvas.drawCircle(Offset(x, y), radius, Paint()..color = color);
    void line(List<Offset> points, Color color, double width) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    void shape(List<Offset> points, Color color) {
      final path = Path()..addPolygon(points, true);
      canvas.drawPath(path, Paint()..color = color);
    }

    void round(Rect rect, double radius, Color color) => canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()..color = color,
    );
    void star(double x, double y, double radius) {
      shape([
        Offset(x, y - radius),
        Offset(x + radius * .28, y - radius * .28),
        Offset(x + radius, y),
        Offset(x + radius * .28, y + radius * .28),
        Offset(x, y + radius),
        Offset(x - radius * .28, y + radius * .28),
        Offset(x - radius, y),
        Offset(x - radius * .28, y - radius * .28),
      ], accent);
    }

    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 100, 100),
      Paint()
        ..shader = RadialGradient(
          colors: [Color.lerp(avatar.background, c, .23)!, avatar.background],
          center: const Alignment(-.5, -.6),
          radius: 1.3,
        ).createShader(const Rect.fromLTWH(0, 0, 100, 100)),
    );
    canvas.drawCircle(
      const Offset(51, 49),
      39,
      Paint()
        ..color = accent.withValues(alpha: .13)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8,
    );
    star(15, 29, 3);
    star(82, 19, 2);
    circle(84, 68, 1, accent);
    oval(
      const Rect.fromLTWH(19, 74, 62, 43),
      Color.lerp(c, avatar.background, .35)!,
    );
    // A shared jacket collar ties the collection together.
    shape(const [
      Offset(35, 79),
      Offset(50, 88),
      Offset(65, 79),
      Offset(58, 96),
      Offset(42, 96),
    ], accent);
    switch (avatar.kind) {
      case 0: // Scout: an explorer robot, with glass lens and aerial.
        line(const [Offset(52, 26), Offset(55, 16)], c, 2.8);
        circle(55, 15, 4, accent);
        round(const Rect.fromLTWH(16, 44, 9, 19), 4, Color.lerp(c, ink, .2)!);
        round(const Rect.fromLTWH(75, 44, 9, 19), 4, Color.lerp(c, ink, .2)!);
        round(const Rect.fromLTWH(23, 27, 54, 51), 18, c);
        round(const Rect.fromLTWH(28, 35, 44, 30), 14, ink);
        circle(50, 50, 11, cream);
        circle(52, 51, 7, Color(0xFF68BCCF));
        circle(53, 51, 4, ink);
        circle(55, 48, 2, Colors.white);
        line(const [Offset(44, 70), Offset(50, 73), Offset(56, 70)], ink, 2);
      case 1: // Fox / wolf: ears, cheek ruff and split muzzle.
        shape(const [Offset(23, 46), Offset(21, 18), Offset(42, 33)], c);
        shape(const [Offset(58, 33), Offset(79, 18), Offset(77, 46)], c);
        shape(const [Offset(26, 35), Offset(25, 23), Offset(36, 34)], accent);
        shape(const [Offset(64, 34), Offset(75, 23), Offset(74, 35)], accent);
        oval(const Rect.fromLTWH(22, 30, 56, 45), c);
        shape(const [
          Offset(20, 49),
          Offset(32, 55),
          Offset(50, 67),
          Offset(68, 55),
          Offset(80, 49),
          Offset(70, 72),
          Offset(50, 83),
          Offset(30, 72),
        ], cream);
        oval(const Rect.fromLTWH(35, 55, 30, 23), cream);
        for (final x in [37.0, 63.0]) {
          oval(
            Rect.fromCenter(center: Offset(x, 48), width: 7, height: 10),
            ink,
          );
          circle(x + 1, 46, 1.4, Colors.white);
        }
        shape(const [Offset(45, 63), Offset(55, 63), Offset(50, 69)], ink);
        line(const [Offset(50, 69), Offset(50, 73)], ink, 1.5);
      case 2: // Orbital suit with a dark visor and reflected stars.
        circle(50, 50, 30, accent);
        circle(50, 50, 25, Color.lerp(c, ink, .18)!);
        round(const Rect.fromLTWH(28, 32, 44, 34), 16, ink);
        canvas.drawArc(
          const Rect.fromLTWH(32, 34, 35, 28),
          math.pi * 1.1,
          math.pi * .6,
          false,
          Paint()
            ..color = Colors.white.withValues(alpha: .25)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
        oval(const Rect.fromLTWH(35, 49, 9, 5), c);
        oval(const Rect.fromLTWH(56, 49, 9, 5), c);
        round(const Rect.fromLTWH(43, 72, 14, 5), 2, ink);
        star(64, 41, 3);
        if (avatar == StudyAvatar.zenith) {
          star(50, 18, 6);
          circle(24, 65, 3, c);
          circle(76, 65, 3, c);
        }
      case 3: // Owl / phoenix: feather crown and two eye masks.
        shape(const [
          Offset(25, 40),
          Offset(24, 20),
          Offset(41, 31),
          Offset(50, 17),
          Offset(59, 31),
          Offset(76, 20),
          Offset(75, 40),
        ], c);
        oval(const Rect.fromLTWH(22, 28, 56, 53), c);
        oval(const Rect.fromLTWH(26, 35, 27, 32), cream);
        oval(const Rect.fromLTWH(47, 35, 27, 32), cream);
        for (final x in [39.0, 61.0]) {
          circle(x, 49, 8, Color.lerp(c, ink, .3)!);
          circle(x, 49, 4.6, ink);
          circle(x + 1.5, 47, 1.7, Colors.white);
        }
        shape(const [
          Offset(44, 62),
          Offset(56, 62),
          Offset(50, 72),
        ], Color(0xFFEAAA4D));
        for (final x in [39.0, 50.0, 61.0]) {
          line(
            [Offset(x - 2, 73), Offset(x, 76), Offset(x + 2, 73)],
            accent,
            1.5,
          );
        }
      case 4: // Cat / panther: crescent, almond eyes and whiskers.
        shape(const [Offset(23, 45), Offset(23, 19), Offset(42, 34)], c);
        shape(const [Offset(58, 34), Offset(77, 19), Offset(77, 45)], c);
        shape(const [Offset(28, 33), Offset(27, 25), Offset(36, 34)], accent);
        shape(const [Offset(64, 34), Offset(73, 25), Offset(72, 33)], accent);
        oval(const Rect.fromLTWH(22, 30, 56, 49), c);
        for (final x in [37.0, 63.0]) {
          oval(
            Rect.fromCenter(center: Offset(x, 52), width: 12, height: 8),
            ink,
          );
          oval(
            Rect.fromCenter(center: Offset(x, 52), width: 3, height: 6),
            cream,
          );
        }
        circle(51, 39, 5, accent);
        circle(54, 37, 4, c);
        shape(const [Offset(46, 62), Offset(54, 62), Offset(50, 66)], ink);
        line(const [Offset(50, 66), Offset(46, 69), Offset(43, 68)], ink, 1.5);
        line(const [Offset(50, 66), Offset(54, 69), Offset(57, 68)], ink, 1.5);
        line(const [Offset(25, 60), Offset(36, 62)], accent, 1.6);
        line(const [Offset(64, 62), Offset(75, 60)], accent, 1.6);
      case 5: // Axolotl: six branching gills.
        for (final side in [-1, 1]) {
          for (var n = 0; n < 3; n++) {
            final y = 37 + n * 11.0;
            line(
              [
                Offset(50 + side * 23.0, y + 6),
                Offset(50 + side * 36.0, y),
                Offset(50 + side * 39.0, y - 5),
              ],
              c,
              5,
            );
            circle(50 + side * 39.0, y - 5, 3, accent);
          }
        }
        oval(const Rect.fromLTWH(23, 30, 54, 49), c);
        for (final x in [37.0, 63.0]) {
          circle(x, 51, 4, ink);
          circle(x + 1, 50, 1.2, Colors.white);
          oval(
            Rect.fromCenter(center: Offset(x, 61), width: 10, height: 4),
            Color(0xFFED83AC),
          );
        }
        canvas.drawArc(
          const Rect.fromLTWH(43, 58, 14, 9),
          0,
          math.pi,
          false,
          Paint()
            ..color = ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round,
        );
      case 6: // Small dragon: horns, ear fins and a broad muzzle.
        shape(const [Offset(27, 40), Offset(25, 18), Offset(38, 31)], cream);
        shape(const [Offset(62, 31), Offset(75, 18), Offset(73, 40)], cream);
        shape(const [
          Offset(24, 41),
          Offset(13, 36),
          Offset(18, 55),
          Offset(28, 59),
        ], c);
        shape(const [
          Offset(76, 41),
          Offset(87, 36),
          Offset(82, 55),
          Offset(72, 59),
        ], c);
        oval(const Rect.fromLTWH(24, 29, 52, 47), c);
        for (final x in [37.0, 63.0]) {
          oval(
            Rect.fromCenter(center: Offset(x, 49), width: 8, height: 10),
            ink,
          );
          circle(x + 1, 47, 1.6, Colors.white);
        }
        round(const Rect.fromLTWH(30, 58, 40, 22), 11, accent);
        circle(41, 65, 1.7, ink);
        circle(59, 65, 1.7, ink);
        line(const [Offset(42, 73), Offset(50, 75), Offset(58, 73)], ink, 1.6);
        shape(const [
          Offset(44, 34),
          Offset(50, 26),
          Offset(56, 34),
          Offset(50, 42),
        ], accent);
    }
    // Tiny expedition badge on every jacket, with richer late-level details.
    round(const Rect.fromLTWH(66, 87, 8, 5), 1, c);
    if (avatar.unlockLevel >= 30) {
      star(17, 77, 3);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(StudyPortraitPainter oldDelegate) =>
      oldDelegate.avatar != avatar;
}
