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
/// Tide or AMOLED without looking pasted on. The head is the brightest part;
/// the arms, body, ears and legs step down in tone below it.
@immutable
class MascotColors {
  const MascotColors({
    required this.body,
    required this.bodyLight,
    required this.bodyDeep,
    required this.headLow,
    required this.torso,
    required this.torsoLow,
    required this.arm,
    required this.armShade,
    required this.limb,
    required this.foot,
    required this.footShade,
    required this.face,
    required this.handRim,
    required this.pupil,
    required this.blush,
    required this.pocket,
    required this.shadow,
    required this.ink,
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
      bodyLight: tone(hct.tone + 5),
      bodyDeep: tone(hct.tone - 10),
      headLow: tone(hct.tone - 4),
      torso: tone(hct.tone - 5),
      torsoLow: tone(hct.tone - 17),
      arm: tone(hct.tone - 6),
      armShade: tone(hct.tone - 14),
      limb: tone(hct.tone - 13),
      foot: tone(hct.tone - 21),
      footShade: tone(hct.tone - 27),
      face: tone(99, chroma: 3),
      handRim: tone(hct.tone - 12, chroma: hct.chroma * 0.45),
      pupil: tone(15, chroma: 18),
      blush: tone(76, chroma: 54, hueShift: 8).withValues(alpha: 0.72),
      pocket: tone(99, chroma: 2),
      shadow: cs.shadow.withValues(alpha: dark ? 0.5 : 0.2),
      ink: cs.onSurfaceVariant,
    );
  }

  /// The head's middle tone, and the colour that names Pip elsewhere.
  final Color body;

  /// The top of the head, and the antenna's light while Pip thinks.
  final Color bodyLight;
  final Color bodyDeep;

  /// The bottom of the head.
  final Color headLow;

  /// The body, from just under the head ([torso]) to its base ([torsoLow]).
  final Color torso;
  final Color torsoLow;

  /// An arm's side toward the light, and its underside.
  final Color arm;
  final Color armShade;

  /// Ears and the antenna's stem.
  final Color limb;

  /// Legs, and the shade under the body and on the soles.
  final Color foot;
  final Color footShade;

  /// The face ring, eye, hands and antenna bulb.
  final Color face;

  /// The outline round each hand.
  final Color handRim;
  final Color pupil;
  final Color blush;
  final Color pocket;
  final Color shadow;
  final Color ink;

  List<Color> get _all => [
    body,
    bodyLight,
    bodyDeep,
    headLow,
    torso,
    torsoLow,
    arm,
    armShade,
    limb,
    foot,
    footShade,
    face,
    handRim,
    pupil,
    blush,
    pocket,
    shadow,
    ink,
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
/// the open ring for a face and the ring's dot for an eye, on a soft round
/// body with a pocket, arms that grow out from behind it and short legs.
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

    // Contact shadow: smaller while Pip is in the air.
    _floorShadow(canvas, walked, (lift / 60).clamp(0.0, 0.6), p.sit);

    canvas.save();
    // A step to the side, in a wiggle or a weight shift.
    canvas.translate(walked, 0);
    // Squash on landing, anchored at the floor.
    canvas.translate(512, 858);
    canvas.scale(1 + 0.05 * p.squash, 1 - 0.07 * p.squash);
    canvas.translate(-512, -858 - lift);

    if (p.sit < 0.98) _standingLegs(canvas, 1 - p.sit, p.step);

    // The arms grow from the shoulders, tucked under the head, and lie over
    // the body's upper sides.
    canvas.save();
    canvas.translate(0, bodyY);
    _body(canvas);
    final hands = _arms(canvas, p);
    canvas.restore();

    if (p.sit > 0.02) _seatedLegs(canvas, p.sit, p.kick);

    canvas.save();
    canvas.translate(0, headY);
    _tiltAroundNeck(canvas, p.tilt);
    _head(canvas, p);
    canvas.restore();

    // Hands last, so a raised hand stays in front of the head.
    canvas.save();
    canvas.translate(0, bodyY);
    for (final hand in hands) {
      _hand(canvas, hand);
    }
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

  /// A soft pool of shade under Pip, wider while it sits with its legs out.
  void _floorShadow(Canvas canvas, double x, double air, double sit) {
    final radius = (124 + 70 * sit) * (1 - air);
    canvas.save();
    canvas.translate(512 + x, 860);
    canvas.scale(1, 0.12);
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [colors.shadow, colors.shadow.withValues(alpha: 0)],
          stops: const [0.45, 1],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius)),
    );
    canvas.restore();
  }

  void _standingLegs(Canvas canvas, double opacity, double step) {
    // A step lifts one leg at a time: the left on positive, the right on
    // negative. Each leg is in shade where it meets the body.
    for (final (double x, double lift) in [
      (436.0, 24.0 * math.max(0.0, step)),
      (528.0, 24.0 * math.max(0.0, -step)),
    ]) {
      final leg = Rect.fromLTWH(x, 790 - lift, 60, 68);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          leg,
          topLeft: const Radius.circular(12),
          topRight: const Radius.circular(12),
          bottomLeft: const Radius.circular(26),
          bottomRight: const Radius.circular(26),
        ),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colors.footShade.withValues(alpha: opacity),
              colors.foot.withValues(alpha: opacity),
            ],
            stops: const [0.4, 0.75],
          ).createShader(leg),
      );
    }
  }

  void _seatedLegs(Canvas canvas, double opacity, double kick) {
    // Sitting, the legs reach forward and out with the soles toward us. A
    // kick lifts one foot as the other drops, like legs swinging off a
    // ledge.
    for (final side in const [-1.0, 1.0]) {
      final hip = Offset(512 + side * 56, 846);
      canvas.save();
      canvas.translate(hip.dx, hip.dy);
      canvas.rotate(-kick);
      canvas.translate(-hip.dx, -hip.dy);
      final knee = Offset(512 + side * 124, 836);
      canvas.drawLine(
        hip,
        knee,
        Paint()
          ..color = colors.foot.withValues(alpha: opacity)
          ..strokeWidth = 50
          ..strokeCap = StrokeCap.round,
      );
      // The foot turned up, its sole facing out: a rim round a darker pad.
      final sole = Offset(512 + side * 152, 820);
      canvas.save();
      canvas.translate(sole.dx, sole.dy);
      canvas.rotate(side * 0.3);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 76, height: 90),
        Paint()..color = colors.torsoLow.withValues(alpha: opacity),
      );
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(0, 5), width: 56, height: 70),
        Paint()..color = colors.footShade.withValues(alpha: opacity),
      );
      canvas.restore();
      canvas.restore();
    }
  }

  /// The body: a soft bean, narrower under the head and round at the base.
  static final Path _torso = Path()
    ..moveTo(512, 626)
    ..lineTo(566, 626)
    ..cubicTo(596, 626, 618, 640, 620, 668)
    ..cubicTo(622, 694, 632, 712, 631, 748)
    ..cubicTo(630, 792, 588, 816, 512, 816)
    ..cubicTo(436, 816, 394, 792, 393, 748)
    ..cubicTo(392, 712, 402, 694, 404, 668)
    ..cubicTo(406, 640, 428, 626, 458, 626)
    ..close();

  /// The pocket: a half-moon with its opening along the top.
  static final Path _pocket = Path()
    ..moveTo(448, 718)
    ..lineTo(576, 718)
    ..quadraticBezierTo(584, 718, 584, 726)
    ..cubicTo(584, 758, 552, 780, 512, 780)
    ..cubicTo(472, 780, 440, 758, 440, 726)
    ..quadraticBezierTo(440, 718, 448, 718)
    ..close();

  void _body(Canvas canvas) {
    const bounds = Rect.fromLTRB(393, 626, 631, 816);
    canvas.drawPath(
      _torso,
      Paint()
        ..shader = LinearGradient(
          begin: const Alignment(-0.45, -1),
          end: const Alignment(0.45, 1),
          colors: [colors.torso, colors.torsoLow],
        ).createShader(bounds),
    );
    // The head's shade on the body, just below it.
    canvas.save();
    canvas.clipPath(_torso);
    const neck = Rect.fromLTRB(393, 640, 631, 676);
    canvas.drawRect(
      neck,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.footShade.withValues(alpha: 0.45),
            colors.footShade.withValues(alpha: 0),
          ],
        ).createShader(neck),
    );
    canvas.restore();

    const pocket = Rect.fromLTRB(440, 718, 584, 780);
    canvas.drawPath(_pocket, Paint()..color = colors.pocket);
    // A little shade inside the opening, so the pocket reads as a pocket.
    canvas.save();
    canvas.clipPath(_pocket);
    canvas.drawRect(
      pocket,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.handRim.withValues(alpha: 0.32),
            colors.handRim.withValues(alpha: 0),
          ],
          stops: const [0, 0.32],
        ).createShader(pocket),
    );
    canvas.restore();
  }

  /// Draws both arms and returns where their hands go.
  List<Offset> _arms(Canvas canvas, MascotPose p) {
    final hands = <Offset>[];
    for (final side in const [-1.0, 1.0]) {
      final raised = _smooth(0.9, 2.1, side < 0 ? p.leftArm : p.rightArm);
      // A hanging arm swings a little wide of the body, so it shows from
      // shoulder to hand; a raised one reaches clear of the head.
      final angle = (side < 0 ? p.leftArm : p.rightArm) + 0.1 * (1 - raised);
      final shoulder = side < 0 ? _shoulders[0] : _shoulders[1];
      final reach = lerpDouble(106, 126, raised)!;
      var hand =
          shoulder +
          Offset(side * math.sin(angle) * reach, math.cos(angle) * reach);
      // Sitting, a resting hand lies on top of its foot.
      hand = Offset.lerp(
        hand,
        Offset(512 + side * 152, 738),
        p.sit * (1 - raised),
      )!;
      // The arm starts under the head and bows outward on its way to the
      // hand, like an elbow.
      final root = Offset(512 + side * 80, 636);
      final along = hand - root;
      var bow = Offset(-along.dy, along.dx) / along.distance;
      if (side * bow.dx + 0.5 * bow.dy < 0) bow = -bow;
      final bend = (root + hand) / 2 + bow * (along.distance * 0.16);
      final shade = Paint()..color = colors.armShade;
      canvas.drawPath(_taper(root, bend, hand, 46, 36), shade);
      // A round shoulder, in case a tilted head uncovers the arm's top.
      canvas.drawCircle(root, 23, shade);
      canvas.drawPath(
        _taper(root, bend, hand, 36, 28).shift(const Offset(-2.5, -3)),
        Paint()..color = colors.arm,
      );
      hands.add(hand);
    }
    return hands;
  }

  static const _shoulders = [Offset(410, 698), Offset(614, 698)];

  /// A tube along the curve from [a] through [c] to [b], [from] wide at [a]
  /// and [to] wide at [b]. Its ends hide under the head and the hand.
  static Path _taper(Offset a, Offset c, Offset b, double from, double to) {
    const steps = 14;
    final left = <Offset>[];
    final right = <Offset>[];
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final u = 1 - t;
      final point = a * (u * u) + c * (2 * u * t) + b * (t * t);
      final tangent = (c - a) * (2 * u) + (b - c) * (2 * t);
      final length = math.max(tangent.distance, 1e-6);
      final normal = Offset(-tangent.dy, tangent.dx) / length;
      final half = lerpDouble(from, to, t)! / 2;
      left.add(point + normal * half);
      right.add(point - normal * half);
    }
    return Path()..addPolygon([...left, ...right.reversed], true);
  }

  /// A white hand with a soft rim, a little shaded away from the light.
  void _hand(Canvas canvas, Offset at) {
    const radius = 31.0;
    canvas.drawCircle(
      at,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [colors.face, Color.lerp(colors.face, colors.handRim, 0.22)!],
          stops: const [0.5, 1],
        ).createShader(Rect.fromCircle(center: at, radius: radius)),
    );
    canvas.drawCircle(
      at,
      radius,
      Paint()
        ..color = colors.handRim
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6,
    );
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
        ..strokeWidth = 11
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

    // Head: the app icon's rounded square, lit from above.
    const head = Rect.fromLTWH(290, 244, 444, 400);
    canvas.drawRRect(
      RRect.fromRectAndRadius(head, const Radius.circular(112)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.bodyLight, colors.body, colors.headLow],
          stops: const [0, 0.5, 1],
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

    // Face: the logo's open ring, its lower half softening into the face.
    const ring = Offset(512, 452);
    canvas.drawPath(
      Path()..addArc(
        Rect.fromCircle(center: ring, radius: 122),
        -57 * math.pi / 180,
        294 * math.pi / 180,
      ),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.face,
            colors.face,
            colors.face.withValues(alpha: 0.5),
          ],
          stops: const [0, 0.5, 1],
        ).createShader(Rect.fromCircle(center: ring, radius: 136))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 31
        ..strokeCap = StrokeCap.round,
    );

    _eye(canvas, p);
    _mouth(canvas, p);
    _blush(canvas, p);
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

    final white = 54 + 6 * p.surprise;
    canvas.save();
    canvas.translate(_eyeCentre.dx, _eyeCentre.dy);
    canvas.scale(1, 1 - closed);
    canvas.translate(-_eyeCentre.dx, -_eyeCentre.dy);
    canvas.drawCircle(
      _eyeCentre,
      white,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.35),
          colors: [colors.face, Color.lerp(colors.face, colors.handRim, 0.12)!],
          stops: const [0.6, 1],
        ).createShader(Rect.fromCircle(center: _eyeCentre, radius: white)),
    );
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

  /// Rosy cheeks that fade into the face, a little warmer when Pip smiles.
  void _blush(Canvas canvas, MascotPose p) {
    final tint = colors.blush.withValues(
      alpha: (colors.blush.a + 0.25 * p.squint).clamp(0.0, 1.0),
    );
    const radius = 36.0;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [tint, tint.withValues(alpha: 0)],
        stops: const [0.35, 1],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius));
    for (final x in const [346.0, 678.0]) {
      canvas.save();
      canvas.translate(x, 548);
      canvas.scale(1, 0.55);
      canvas.drawCircle(Offset.zero, radius, paint);
      canvas.restore();
    }
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
