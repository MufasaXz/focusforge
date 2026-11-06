import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart' as mcu;

import '../../../app/theme/app_theme.dart';
import '../../../core/models/user.dart';
import 'mascot_rig.dart';

/// Pip's colours, all derived from the live theme.
///
/// The body is the brand orange — the Ember palette's seed — pulled toward the
/// theme's primary with [harmonize], the same treatment a subject colour gets.
/// Every other colour is a tone of that one hue, so Pip sits in Parchment,
/// Tide or AMOLED without looking pasted on.
@immutable
class MascotColors {
  const MascotColors({
    required this.body,
    required this.bodyLight,
    required this.bodyDeep,
    required this.limb,
    required this.foot,
    required this.face,
    required this.pupil,
    required this.blush,
    required this.pocket,
    required this.shadow,
    required this.ink,
    required this.book,
  });

  factory MascotColors.of(ThemeData theme) {
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final base = harmonize(
      AppPalette.ember.seedFor(theme.brightness),
      cs.primary,
    );
    final hct = mcu.Hct.fromInt(base.toARGB32());
    Color tone(double tone, {double? chroma, double hueShift = 0}) => Color(
      mcu.Hct.from(
        (hct.hue + hueShift) % 360,
        chroma ?? hct.chroma,
        tone.clamp(0.0, 100.0),
      ).toInt(),
    );
    return MascotColors(
      body: base,
      bodyLight: tone(hct.tone + 7),
      bodyDeep: tone(hct.tone - 10),
      limb: tone(hct.tone - 13),
      foot: tone(hct.tone - 19),
      face: tone(99, chroma: 3),
      pupil: tone(15, chroma: 18),
      blush: tone(76, chroma: 54, hueShift: 8).withValues(alpha: 0.55),
      pocket: tone(97, chroma: 7),
      shadow: cs.shadow.withValues(alpha: dark ? 0.42 : 0.14),
      ink: cs.onSurfaceVariant,
      // The book's cover: the body's hue turned to its complement, so it
      // reads as a separate object without leaving Pip's palette.
      book: tone(dark ? 60 : 44, chroma: 40, hueShift: 180),
    );
  }

  final Color body;
  final Color bodyLight;
  final Color bodyDeep;
  final Color limb;
  final Color foot;
  final Color face;
  final Color pupil;
  final Color blush;
  final Color pocket;
  final Color shadow;
  final Color ink;
  final Color book;

  List<Color> get _all => [
    body,
    bodyLight,
    bodyDeep,
    limb,
    foot,
    face,
    pupil,
    blush,
    pocket,
    shadow,
    ink,
    book,
  ];

  @override
  bool operator ==(Object other) =>
      other is MascotColors &&
      List.generate(
        _all.length,
        (i) => _all[i] == other._all[i],
      ).every((s) => s);

  @override
  int get hashCode => Object.hashAll(_all);
}

/// Draws Pip from the logo's shapes: the app icon's rounded square for a head,
/// the open ring for a face and the ring's dot for an eye, with a pocket on
/// the belly.
///
/// Coordinates are in the units of the 1024-wide source drawing, so the
/// numbers here match the published artwork one for one.
class MascotPainter extends CustomPainter {
  MascotPainter({
    required this.rig,
    required this.colors,
    this.headOnly = false,
  }) : super(repaint: rig);

  final MascotRig rig;
  final MascotColors colors;
  final bool headOnly;

  /// Room for the whole figure, a raised arm and a drifting "z".
  static const Rect fullBox = Rect.fromLTWH(237, 120, 550, 780);

  /// The head with its ears and antenna, for an avatar.
  static const Rect headBox = Rect.fromLTWH(250, 126, 524, 528);

  /// Height over width of the whole figure.
  static double get fullAspect => fullBox.height / fullBox.width;

  /// Where the feet meet the floor, as a fraction of the full box's height.
  static double get floorFraction => (858 - fullBox.top) / fullBox.height;

  /// The centre of the eye, as fractions of the full box.
  static Offset get eyeFraction => Offset(
    (512 - fullBox.left) / fullBox.width,
    (440 - fullBox.top) / fullBox.height,
  );

  static const _neck = Offset(512, 640);
  static const _eyeCentre = Offset(512, 440);

  @override
  void paint(Canvas canvas, Size size) {
    final pose = rig.pose;
    final box = headOnly ? headBox : fullBox;
    canvas.save();
    canvas.scale(size.width / box.width);
    canvas.translate(-box.left, -box.top);
    if (headOnly) {
      canvas.save();
      // A nod still shows when only the head is drawn.
      canvas.translate(0, pose.headLag * 0.6);
      _tiltAroundNeck(canvas, pose.tilt);
      _head(canvas, pose);
      canvas.restore();
    } else {
      _figure(canvas, pose);
    }
    canvas.restore();
  }

  void _figure(Canvas canvas, MascotPose p) {
    final lift = p.hop;
    final sitDrop = 30 * p.sit;
    final bodyY = sitDrop - 3 * p.breath;
    final headY = sitDrop - 6 * p.breath + p.headLag;
    final walked = p.shiftX * fullBox.width;

    // Contact shadow: smaller while Pip is in the air, gone while it hangs
    // off the edge.
    final air = math.max(
      (lift / 60).clamp(0.0, 0.6),
      (p.dropY * 3).clamp(0.0, 1.0),
    );
    if (air < 1) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(512 + walked, 860),
          width: 236 * (1 - air),
          height: 22 * (1 - air),
        ),
        Paint()..color = colors.shadow,
      );
    }

    canvas.save();
    // Walking along the bar, dropping off its end, and the tip of a slip,
    // which pivots on the right foot.
    canvas.translate(walked, p.dropY * fullBox.height);
    if (p.roll != 0) {
      canvas.translate(512, 858);
      canvas.rotate(p.roll);
      canvas.translate(-512, -858);
    }
    if (p.lean != 0) {
      canvas.translate(590, 858);
      canvas.rotate(p.lean);
      canvas.translate(-590, -858);
    }
    // Squash on landing, anchored at the floor.
    canvas.translate(512, 858);
    canvas.scale(1 + 0.05 * p.squash, 1 - 0.07 * p.squash);
    canvas.translate(-512, -858 - lift);

    if (p.sit < 0.98) _standingFeet(canvas, 1 - p.sit, p.step);

    canvas.save();
    canvas.translate(0, bodyY);
    _body(canvas);
    canvas.restore();

    if (p.sit > 0.02) _seatedFeet(canvas, p.sit, p.kick);

    canvas.save();
    canvas.translate(0, headY);
    _tiltAroundNeck(canvas, p.tilt);
    _head(canvas, p);
    canvas.restore();

    canvas.save();
    canvas.translate(0, bodyY);
    _arms(canvas, p);
    canvas.restore();

    canvas.restore();

    _thoughts(canvas, p, headY - lift);
    _sleepyZ(canvas, p, headY - lift);
  }

  void _tiltAroundNeck(Canvas canvas, double tilt) {
    if (tilt == 0) return;
    canvas.translate(_neck.dx, _neck.dy);
    canvas.rotate(tilt);
    canvas.translate(-_neck.dx, -_neck.dy);
  }

  void _standingFeet(Canvas canvas, double opacity, double step) {
    final paint = Paint()..color = colors.foot.withValues(alpha: opacity);
    // A step lifts one foot at a time: the left on positive, the right on
    // negative.
    for (final (double x, double lift) in [
      (436.0, 24.0 * math.max(0.0, step)),
      (526.0, 24.0 * math.max(0.0, -step)),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 812 - lift, 62, 46),
          const Radius.circular(22),
        ),
        paint,
      );
    }
  }

  void _seatedFeet(Canvas canvas, double opacity, double kick) {
    final paint = Paint()..color = colors.foot.withValues(alpha: opacity);
    // A kick lifts one foot as the other drops, like legs swinging off a
    // ledge.
    for (final (x, angle) in [(440.0, -0.32 - kick), (584.0, 0.32 - kick)]) {
      canvas.save();
      canvas.translate(x, 848);
      canvas.rotate(angle);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 62, height: 34),
          const Radius.circular(17),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  void _body(Canvas canvas) {
    const rect = Rect.fromLTWH(396, 628, 232, 200);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(78)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.body, colors.bodyDeep],
        ).createShader(rect),
    );

    // The pocket: a half-moon with its opening along the top.
    final pocket = Path()
      ..moveTo(458, 708)
      ..lineTo(566, 708)
      ..arcToPoint(
        const Offset(458, 708),
        radius: const Radius.elliptical(54, 50),
      );
    canvas.drawPath(pocket, Paint()..color = colors.pocket);
    canvas.drawLine(
      const Offset(460, 708),
      const Offset(564, 708),
      Paint()
        ..color = colors.limb
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round,
    );
  }

  void _arms(Canvas canvas, MascotPose p) {
    final stroke = Paint()
      ..color = colors.limb
      ..style = PaintingStyle.stroke
      ..strokeWidth = 30
      ..strokeCap = StrokeCap.round;
    final hand = Paint()..color = colors.face;
    final hands = <Offset>[];
    for (final side in const [-1.0, 1.0]) {
      final angle = side < 0 ? p.leftArm : p.rightArm;
      final shoulder = Offset(side < 0 ? 404 : 620, 694);
      // A raised arm reaches a little further, clear of the head.
      final reach = lerpDouble(86, 124, _smooth(0.9, 2.1, angle))!;
      Offset along(double a, double length) =>
          shoulder + Offset(side * math.sin(a) * length, math.cos(a) * length);
      final end = along(angle, reach);
      final bend = along(angle + 0.28, reach * 0.55);
      canvas.drawPath(
        Path()
          ..moveTo(shoulder.dx, shoulder.dy)
          ..quadraticBezierTo(bend.dx, bend.dy, end.dx, end.dy),
        stroke,
      );
      hands.add(end);
    }
    // The book sits between the arms, under the hands that hold it.
    if (p.read > 0.01) _book(canvas, p);
    for (final end in hands) {
      canvas.drawCircle(end, 23, hand);
    }
  }

  /// An open book held up at the chest, tipped toward Pip: a cover, two
  /// pages that curve up from the spine, the edges of the pages beneath, a
  /// few lines of text and, now and then, a page turning over.
  void _book(Canvas canvas, MascotPose p) {
    final t = p.read;
    canvas.save();
    canvas.translate(512, 712);
    canvas.scale(0.55 + 0.45 * t);
    // Tipped toward Pip, the far (top) edge reads a little narrower.
    const top = -60.0;
    const bottom = 62.0;
    const topHalf = 130.0;
    const bottomHalf = 150.0;
    final cover = colors.book.withValues(alpha: t);
    final edges = Color.lerp(
      colors.pocket,
      colors.ink,
      0.22,
    )!.withValues(alpha: t);
    final paper = colors.pocket.withValues(alpha: t);
    final ink = colors.ink.withValues(alpha: 0.32 * t);

    // The cover, a little larger than the pages, its corners rounded.
    final coverShape = Path()
      ..moveTo(-topHalf - 10, top - 4)
      ..quadraticBezierTo(-topHalf * 0.45, top - 18, 0, top + 4)
      ..quadraticBezierTo(topHalf * 0.45, top - 18, topHalf + 10, top - 4)
      ..lineTo(bottomHalf + 12, bottom + 12)
      ..quadraticBezierTo(bottomHalf * 0.45, bottom + 2, 0, bottom + 20)
      ..quadraticBezierTo(
        -bottomHalf * 0.45,
        bottom + 2,
        -bottomHalf - 12,
        bottom + 12,
      )
      ..close();
    canvas.drawPath(
      coverShape,
      Paint()
        ..color = cover
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(coverShape, Paint()..color = cover);

    // The pages underneath, seen as two thin bands along the bottom edge.
    for (final drop in const [8.0, 4.0]) {
      for (final side in const [-1.0, 1.0]) {
        canvas.drawPath(
          Path()
            ..moveTo(0, bottom + 6 + drop)
            ..quadraticBezierTo(
              side * bottomHalf * 0.45,
              bottom - 4 + drop,
              side * (bottomHalf + 2),
              bottom + drop - 2,
            ),
          Paint()
            ..color = edges
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
    }

    Path page(double side) => Path()
      ..moveTo(0, top + 8)
      ..quadraticBezierTo(side * topHalf * 0.45, top - 10, side * topHalf, top)
      ..lineTo(side * bottomHalf, bottom)
      ..quadraticBezierTo(side * bottomHalf * 0.45, bottom - 8, 0, bottom + 8)
      ..close();
    for (final side in const [-1.0, 1.0]) {
      canvas.drawPath(page(side), Paint()..color = paper);
      // A soft fold where the page meets the spine.
      canvas.drawPath(
        Path()
          ..moveTo(0, top + 8)
          ..quadraticBezierTo(side * 16, top + 4, side * 22, top + 6)
          ..lineTo(side * 24, bottom - 2)
          ..quadraticBezierTo(side * 14, bottom + 2, 0, bottom + 8)
          ..close(),
        Paint()..color = edges.withValues(alpha: 0.35 * t),
      );
      // Lines of text, following the curve of the page.
      for (var i = 0; i < 5; i++) {
        final y = top + 22.0 + i * 18;
        final end = i == 4 ? 70.0 : 108.0 - (i.isOdd ? 8 : 0);
        canvas.drawPath(
          Path()
            ..moveTo(side * 32, y + 2)
            ..quadraticBezierTo(side * 70, y - 3, side * end, y),
          Paint()
            ..color = ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round,
        );
      }
    }
    if (p.page >= 0) {
      // A page lifting off the right side and laying itself down on the
      // left, foreshortened as it passes over the spine.
      canvas.save();
      canvas.translate(0, -14 * math.sin(math.pi * p.page));
      canvas.scale(math.cos(math.pi * p.page), 1);
      canvas.drawPath(page(1), Paint()..color = paper);
      canvas.drawPath(
        page(1),
        Paint()
          ..color = edges
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      canvas.restore();
    }
    canvas.restore();
  }

  void _head(Canvas canvas, MascotPose p) {
    final limb = Paint()..color = colors.limb;

    // Ears sit behind the head.
    for (final x in const [262.0, 718.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 398, 44, 112),
          const Radius.circular(20),
        ),
        limb,
      );
    }

    // Antenna, with a ring that pulses out while Pip is thinking. It swings
    // from its base, trailing the head.
    canvas.save();
    canvas.translate(512, 250);
    canvas.rotate(p.sway);
    canvas.translate(-512, -250);
    canvas.drawPath(
      Path()
        ..moveTo(512, 250)
        ..quadraticBezierTo(510, 214, 530, 186),
      Paint()
        ..color = colors.limb
        ..style = PaintingStyle.stroke
        ..strokeWidth = 13
        ..strokeCap = StrokeCap.round,
    );
    const bulb = Offset(536, 170);
    if (p.antenna > 0.01) {
      canvas.drawCircle(
        bulb,
        19 + 14 * p.antenna,
        Paint()
          ..color = colors.bodyLight.withValues(alpha: 0.55 * p.antenna)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5,
      );
    }
    canvas.drawCircle(
      bulb,
      19 * (1 + 0.18 * p.antenna),
      Paint()
        ..color = Color.lerp(colors.face, colors.bodyLight, p.antenna * 0.7)!,
    );
    canvas.restore();

    // Head: the app icon's rounded square.
    const head = Rect.fromLTWH(290, 244, 444, 400);
    canvas.drawRRect(
      RRect.fromRectAndRadius(head, const Radius.circular(112)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.bodyLight, colors.body],
        ).createShader(head),
    );
    final shine = Paint()..color = colors.face.withValues(alpha: 0.22);
    canvas.save();
    canvas.translate(372, 304);
    canvas.rotate(-24 * math.pi / 180);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 108, height: 40),
      shine,
    );
    canvas.restore();
    canvas.drawCircle(const Offset(436, 282), 8, shine);

    // Face: the logo's open ring.
    canvas.drawPath(
      Path()..addArc(
        Rect.fromCircle(center: const Offset(512, 452), radius: 122),
        -57 * math.pi / 180,
        294 * math.pi / 180,
      ),
      Paint()
        ..color = colors.face
        ..style = PaintingStyle.stroke
        ..strokeWidth = 28
        ..strokeCap = StrokeCap.round,
    );

    _eye(canvas, p);
    _mouth(canvas, p);

    final blush = Paint()
      ..color = colors.blush.withValues(
        alpha: (colors.blush.a + 0.25 * p.squint).clamp(0.0, 1.0),
      );
    for (final x in const [346.0, 678.0]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, 548), width: 60, height: 34),
        blush,
      );
    }
  }

  void _eye(Canvas canvas, MascotPose p) {
    final closed = math.max(p.blink, _smooth(0.25, 0.75, p.sleep));
    final line = Paint()
      ..color = colors.face
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.round;

    if (p.squint > 0.5) {
      // Happy: a soft arch.
      canvas.drawPath(
        Path()
          ..moveTo(470, 456)
          ..quadraticBezierTo(512, 396, 554, 456),
        line,
      );
      return;
    }
    if (closed >= 0.85) {
      // Asleep or mid-blink: a gentle curve.
      canvas.drawPath(
        Path()
          ..moveTo(474, 440)
          ..quadraticBezierTo(512, 470, 550, 440),
        line,
      );
      return;
    }

    final grow = 6 * p.surprise;
    canvas.save();
    canvas.translate(_eyeCentre.dx, _eyeCentre.dy);
    canvas.scale(1, 1 - closed);
    canvas.translate(-_eyeCentre.dx, -_eyeCentre.dy);
    canvas.drawCircle(_eyeCentre, 54 + grow, Paint()..color = colors.face);
    final pupil = Offset(516 + 15 * p.lookX, 444 + 13 * p.lookY);
    canvas.drawCircle(
      pupil,
      33 - 9 * p.surprise,
      Paint()..color = colors.pupil,
    );
    final glint = Paint()..color = colors.face;
    canvas.drawCircle(pupil + const Offset(14, -15), 11, glint);
    canvas.drawCircle(pupil + const Offset(-11, 13), 5, glint);
    canvas.restore();
  }

  void _mouth(Canvas canvas, MascotPose p) {
    final ink = Paint()..color = colors.pupil;
    if (p.surprise > 0.05) {
      canvas.drawOval(
        Rect.fromCenter(
          center: const Offset(512, 526),
          width: 6 + 16 * p.surprise,
          height: 8 + 20 * p.surprise,
        ),
        ink,
      );
      return;
    }
    if (p.mouth > 0.04) {
      final depth = 8 + 26 * p.mouth;
      canvas.drawPath(
        Path()
          ..moveTo(494, 516)
          ..quadraticBezierTo(512, 521, 530, 516)
          ..quadraticBezierTo(512, 516 + depth, 494, 516)
          ..close(),
        ink,
      );
      return;
    }
    final sleepy = p.sleep > 0.5;
    canvas.drawPath(
      sleepy
          ? (Path()
              ..moveTo(498, 522)
              ..quadraticBezierTo(512, 530, 526, 522))
          : (Path()
              ..moveTo(492, 518)
              ..quadraticBezierTo(512, 536, 532, 518)),
      Paint()
        ..color = colors.pupil
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
  }

  /// Three rising dots, like a thought taking shape.
  void _thoughts(Canvas canvas, MascotPose p, double dy) {
    if (p.think < 0.01) return;
    const dots = [
      (Offset(682, 216), 11.0),
      (Offset(716, 178), 16.0),
      (Offset(752, 138), 21.0),
    ];
    for (var i = 0; i < dots.length; i++) {
      final (centre, radius) = dots[i];
      final shown = (p.think * 3 - i).clamp(0.0, 1.0);
      if (shown <= 0) continue;
      final pulse = 1 + 0.08 * math.sin(2 * math.pi * (p.thinkPhase - i * 0.2));
      canvas.drawCircle(
        centre + Offset(0, dy),
        radius * shown * pulse,
        Paint()..color = colors.ink.withValues(alpha: 0.7 * shown),
      );
    }
  }

  /// One "z" drifting up and fading while Pip sleeps.
  void _sleepyZ(Canvas canvas, MascotPose p, double dy) {
    final t = p.zPuff;
    if (t < 0) return;
    final x = lerpDouble(648, 724, t)!;
    final y = lerpDouble(236, 164, t)! + dy;
    final s = lerpDouble(26, 46, t)!;
    final fade = t < 0.2 ? t / 0.2 : (t > 0.6 ? (1 - t) / 0.4 : 1.0);
    canvas.drawPath(
      Path()
        ..moveTo(x - s / 2, y - s / 2)
        ..lineTo(x + s / 2, y - s / 2)
        ..lineTo(x - s / 2, y + s / 2)
        ..lineTo(x + s / 2, y + s / 2),
      Paint()
        ..color = colors.ink.withValues(alpha: 0.85 * fade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  static double _smooth(double from, double to, double value) {
    final t = ((value - from) / (to - from)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  @override
  bool shouldRepaint(MascotPainter oldDelegate) =>
      oldDelegate.rig != rig ||
      oldDelegate.colors != colors ||
      oldDelegate.headOnly != headOnly;
}
