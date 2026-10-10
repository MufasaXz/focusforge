import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/models/user.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/animated_digits.dart';

/// The focus timer's remaining time, drawn in the face the user chose.
///
/// One entry point for the three places a clock is drawn — the ring on the
/// focus tab, the full-screen clock and the preview tiles in the profile — so
/// a face cannot look like one thing in the picker and another on the timer.
///
/// The face only decides how the figures are drawn. The value, the colour and
/// the ticking all come from the caller, which is what keeps every face
/// honest: none of them owns a clock, they all render the one the engine has.
///
/// [height] is the natural size of the figures; the caller scales the result
/// to fit its slot, so the same face works at 40dp and at 200dp.
class ClockDisplay extends StatelessWidget {
  const ClockDisplay({
    super.key,
    required this.remaining,
    required this.face,
    required this.accent,
    required this.height,
    this.progress = 0,
    this.phaseLabel = 'FOCUS',
  });

  final Duration remaining;
  final ClockFace face;
  final String phaseLabel;
  final Color accent;
  final double height;

  /// How much of the segment is behind us, 0 to 1. Only the minimal face
  /// draws it — the others have the ring around them for that.
  final double progress;

  @override
  Widget build(BuildContext context) {
    final text = formatClock(remaining);

    switch (face) {
      case ClockFace.retro:
        return RetroClock(
          remaining: remaining,
          accent: accent,
          size: height,
          progress: progress,
        );
      case ClockFace.flip:
        return _FlipBoard(text: text, accent: accent, height: height);
      case ClockFace.segments:
        return _SegmentDisplay(text: text, accent: accent, height: height);
      case ClockFace.minimal:
        return _MinimalClock(
          text: text,
          accent: accent,
          height: height,
          progress: progress,
        );
      case ClockFace.analog:
        return _AnalogClock(
          remaining: remaining,
          accent: accent,
          height: height,
          progress: progress,
        );
      case ClockFace.neon:
        return _NeonClock(text: text, accent: accent, height: height);
    }
  }
}

// ---------------------------------------------------------------------------
// Flip — split-flap cards
// ---------------------------------------------------------------------------

/// The classic departure board: one card per character, each flipping in two
/// halves as it changes.
///
/// The halves are what make it read as a flip rather than as a rotation: the
/// top half of the old figure falls away while the top half of the new one is
/// already behind it, and only then does the new bottom half rise. That is the
/// order a real split-flap moves in, and the eye notices when it is wrong.
class _FlipBoard extends StatelessWidget {
  const _FlipBoard({
    required this.text,
    required this.accent,
    required this.height,
  });

  final String text;
  final Color accent;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.displayLarge!.copyWith(
      fontSize: height * 0.68,
      height: 1,
      fontWeight: FontWeight.w700,
      color: cs.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // Cards are sized from the glyphs they have to hold, so the board does not
    // jump when a `1` replaces a `0`.
    final painter = TextPainter(
      text: TextSpan(text: '0', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = math.max(painter.width, height * 0.42) + height * 0.16;
    painter.dispose();

    final card = height * 0.98;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < text.length; i++)
          Padding(
            padding: EdgeInsets.only(
              right: i == text.length - 1 ? 0 : height * 0.05,
            ),
            child: text[i] == ':'
                ? _FlipColon(accent: accent, height: card)
                : _FlipCard(
                    // Keyed from the right, because the string grows and
                    // shrinks: "9:59" becoming "10:00" shifts every character
                    // one place to the right, and without a key that is stable
                    // across the shift each card would flip to a figure that
                    // belonged to its neighbour.
                    key: ValueKey<int>(text.length - i),
                    glyph: text[i],
                    style: style,
                    accent: accent,
                    width: width,
                    height: card,
                  ),
          ),
      ],
    );
  }
}

/// One card. Holds the figure it is showing and the one it is leaving.
class _FlipCard extends StatefulWidget {
  const _FlipCard({
    super.key,
    required this.glyph,
    required this.style,
    required this.accent,
    required this.width,
    required this.height,
  });

  final String glyph;
  final TextStyle style;
  final Color accent;
  final double width;
  final double height;

  @override
  State<_FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<_FlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 1,
  );

  late String _current = widget.glyph;
  late String _outgoing = widget.glyph;

  @override
  void didUpdateWidget(covariant _FlipCard old) {
    super.didUpdateWidget(old);
    if (old.glyph == widget.glyph) return;
    _outgoing = _current;
    _current = widget.glyph;
    // A reduced-motion setting gets the new figure with no travel. It still
    // arrives in halves, so the card does not lose its shape.
    if (MediaQuery.disableAnimationsOf(context)) {
      _flip.value = 1;
    } else {
      _flip.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = widget.height * 0.09;
    final divider = Color.alphaBlend(
      cs.surface.withValues(alpha: 0.35),
      cs.onSurface.withValues(alpha: 0.30),
    );

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _flip,
        builder: (context, _) {
          final t = Curves.easeInOutCubic.transform(_flip.value);
          // First half: the old top falls. Second half: the new bottom rises.
          final falling = t < 0.5;

          // Every child is positioned, and that is load-bearing: a Stack
          // aligns its non-positioned children to the top-left, so both halves
          // would land in the top half of the card and the bottom would stay
          // blank. The halves are anchored to the edge they belong to.
          return Stack(
            children: [
              // The halves the flap will uncover.
              _HalfSlot(
                top: true,
                height: widget.height,
                child: _Half(
                  glyph: _current,
                  style: widget.style,
                  top: true,
                  width: widget.width,
                  height: widget.height,
                  radius: radius,
                ),
              ),
              _HalfSlot(
                top: false,
                height: widget.height,
                child: _Half(
                  glyph: falling ? _outgoing : _current,
                  style: widget.style,
                  top: false,
                  width: widget.width,
                  height: widget.height,
                  radius: radius,
                ),
              ),
              if (falling)
                _HalfSlot(
                  top: true,
                  height: widget.height,
                  child: _FlippingHalf(
                    glyph: _outgoing,
                    style: widget.style,
                    top: true,
                    width: widget.width,
                    height: widget.height,
                    radius: radius,
                    angle: -math.pi / 2 * (t / 0.5),
                  ),
                )
              else
                _HalfSlot(
                  top: false,
                  height: widget.height,
                  child: _FlippingHalf(
                    glyph: _current,
                    style: widget.style,
                    top: false,
                    width: widget.width,
                    height: widget.height,
                    radius: radius,
                    angle: math.pi / 2 * (1 - (t - 0.5) / 0.5),
                  ),
                ),
              // The hinge: a hairline in the fold, and the shade the top
              // half casts on the one below it. Together they are what the
              // eye reads as a seam rather than as a line drawn on a panel.
              Positioned(
                left: 0,
                right: 0,
                top: widget.height / 2 - 0.5,
                child: Container(height: 1, color: divider),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: widget.height / 2 + 0.5,
                height: widget.height * 0.07,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        cs.shadow.withValues(alpha: 0.16),
                        cs.shadow.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Pins one half of a card to the top or the bottom of it.
///
/// A half is half a card tall and carries a full-height glyph inside it, so it
/// only reads correctly when it is anchored to the edge whose half it shows.
class _HalfSlot extends StatelessWidget {
  const _HalfSlot({
    required this.top,
    required this.height,
    required this.child,
  });

  final bool top;

  /// The full card's height. The slot takes half of it.
  final double height;

  final Widget child;

  @override
  Widget build(BuildContext context) => Positioned(
    left: 0,
    right: 0,
    top: top ? 0 : null,
    bottom: top ? null : 0,
    height: height / 2,
    child: child,
  );
}

/// Half a card, unrotated.
///
/// A half is a *window* on the figure, not a smaller figure: the glyph is laid
/// out at the card's full height and the window clips it to the half it owns.
/// Laying the glyph out at the window's own height instead is the mistake that
/// makes the board read as doubled — both halves then show a complete figure
/// and the card looks like two stacked clocks. The [OverflowBox] is what lets
/// the glyph keep its full height inside a slot half that tall.
///
/// Each half also paints its own fill. Light falls from above, so the top half
/// is the lighter of the two and the bottom sits in shade: that difference is
/// what makes the hinge read as a fold.
class _Half extends StatelessWidget {
  const _Half({
    required this.glyph,
    required this.style,
    required this.top,
    required this.width,
    required this.height,
    required this.radius,
  });

  final String glyph;
  final TextStyle style;
  final bool top;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = cs.surfaceContainerHighest;
    final fill = top
        ? base
        : Color.alphaBlend(cs.shadow.withValues(alpha: 0.10), base);

    return ClipRRect(
      borderRadius: BorderRadius.vertical(
        top: top ? Radius.circular(radius) : Radius.zero,
        bottom: top ? Radius.zero : Radius.circular(radius),
      ),
      child: ColoredBox(
        color: fill,
        child: OverflowBox(
          alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
          minHeight: height,
          maxHeight: height,
          child: SizedBox(
            width: width,
            height: height,
            child: Center(child: Text(glyph, style: style, maxLines: 1)),
          ),
        ),
      ),
    );
  }
}

/// Half a card, hinged at its inner edge and turned in 3D.
class _FlippingHalf extends StatelessWidget {
  const _FlippingHalf({
    required this.glyph,
    required this.style,
    required this.top,
    required this.width,
    required this.height,
    required this.radius,
    required this.angle,
  });

  final String glyph;
  final TextStyle style;
  final bool top;
  final double width;
  final double height;
  final double radius;
  final double angle;

  @override
  Widget build(BuildContext context) => Transform(
    alignment: top ? Alignment.bottomCenter : Alignment.topCenter,
    // A small perspective term: without it the halves shear flat and the
    // motion reads as a squash rather than as a card turning over.
    transform: Matrix4.identity()
      ..setEntry(3, 2, 0.0016)
      ..rotateX(angle),
    child: _Half(
      glyph: glyph,
      style: style,
      top: top,
      width: width,
      height: height,
      radius: radius,
    ),
  );
}

class _FlipColon extends StatelessWidget {
  const _FlipColon({required this.accent, required this.height});

  final Color accent;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: height * 0.22,
    height: height,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _dot(),
        SizedBox(height: height * 0.22),
        _dot(),
      ],
    ),
  );

  Widget _dot() => Container(
    width: height * 0.13,
    height: height * 0.13,
    decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
  );
}

// ---------------------------------------------------------------------------
// Segments — seven-segment display
// ---------------------------------------------------------------------------

/// The digits of an LED clock: seven segments each, with the unlit ones faint
/// enough to see. That faintness is the whole effect — without it the figures
/// float in space and read as a plain font.
class _SegmentDisplay extends StatelessWidget {
  const _SegmentDisplay({
    required this.text,
    required this.accent,
    required this.height,
  });

  final String text;
  final Color accent;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CustomPaint(
      size: Size(height * 0.62 * text.length, height),
      painter: _SegmentPainter(
        text: text,
        lit: accent,
        unlit: cs.onSurface.withValues(alpha: 0.07),
        colon: cs.onSurface.withValues(alpha: 0.25),
      ),
    );
  }
}

class _SegmentPainter extends CustomPainter {
  const _SegmentPainter({
    required this.text,
    required this.lit,
    required this.unlit,
    required this.colon,
  });

  final String text;
  final Color lit;
  final Color unlit;
  final Color colon;

  /// Which segments each figure lights: a b c d e f g, clockwise from the top,
  /// with g across the middle.
  static const _figures = <String, String>{
    '0': 'abcdef',
    '1': 'bc',
    '2': 'abged',
    '3': 'abgcd',
    '4': 'fgbc',
    '5': 'afgcd',
    '6': 'afgedc',
    '7': 'abc',
    '8': 'abcdefg',
    '9': 'abfgcd',
  };

  @override
  void paint(Canvas canvas, Size size) {
    final digitWidth = size.width / math.max(text.length, 1);
    final thickness = digitWidth * 0.17;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < text.length; i++) {
      final left = i * digitWidth;
      if (text[i] == ':') {
        final cx = left + digitWidth / 2;
        final r = thickness * 0.42;
        canvas.drawCircle(
          Offset(cx, size.height * 0.36),
          r,
          Paint()..color = colon,
        );
        canvas.drawCircle(
          Offset(cx, size.height * 0.64),
          r,
          Paint()..color = colon,
        );
        continue;
      }

      final on = _figures[text[i]] ?? '';
      for (final segment in 'abcdefg'.split('')) {
        canvas.drawPath(
          _pathFor(segment, left, digitWidth, size.height, thickness),
          stroke..color = on.contains(segment) ? lit : unlit,
        );
      }
    }
  }

  /// The segment's line, inset so the rounded caps do not overlap at the
  /// corners.
  Path _pathFor(
    String segment,
    double left,
    double width,
    double height,
    double thickness,
  ) {
    final inset = thickness * 0.75;
    final x0 = left + inset;
    final x1 = left + width - inset;
    final y0 = inset;
    final y1 = height / 2 - inset * 0.5;
    final y2 = height / 2 + inset * 0.5;
    final y3 = height - inset;

    final (from, to) = switch (segment) {
      'a' => (Offset(x0, y0), Offset(x1, y0)),
      'b' => (Offset(x1, y0), Offset(x1, y1)),
      'c' => (Offset(x1, y2), Offset(x1, y3)),
      'd' => (Offset(x0, y3), Offset(x1, y3)),
      'e' => (Offset(x0, y2), Offset(x0, y3)),
      'f' => (Offset(x0, y0), Offset(x0, y1)),
      _ => (Offset(x0, height / 2), Offset(x1, height / 2)),
    };
    return Path()
      ..moveTo(from.dx, from.dy)
      ..lineTo(to.dx, to.dy);
  }

  @override
  bool shouldRepaint(_SegmentPainter old) =>
      old.text != text ||
      old.lit != lit ||
      old.unlit != unlit ||
      old.colon != colon;
}

// ---------------------------------------------------------------------------
// Neon — lit figures with a glow
// ---------------------------------------------------------------------------

/// Figures in the phase colour with a halo around them: the tube-clock look.
///
/// The glow is the effect and the legibility is the constraint, so the two
/// are set separately rather than by tinting the figures with the accent. In
/// the dark scheme the accent is bright enough to read as the tube itself; in
/// the light one the accent on a pale surface is a smudge at this size, so the
/// figures step towards the ink and keep the accent only in the halo.
class _NeonClock extends StatelessWidget {
  const _NeonClock({
    required this.text,
    required this.accent,
    required this.height,
  });

  final String text;
  final Color accent;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;

    final ink = dark ? accent : Color.lerp(accent, cs.onSurface, 0.42)!;
    final halo = accent.withValues(alpha: dark ? 0.55 : 0.28);

    return AnimatedDigits(
      text: text,
      style: theme.textTheme.displayLarge!.copyWith(
        fontSize: height,
        height: 1.02,
        fontWeight: FontWeight.w500,
        letterSpacing: -height * 0.03,
        color: ink,
        shadows: [
          Shadow(color: halo, blurRadius: height * 0.22),
          Shadow(color: halo, blurRadius: height * 0.5),
          if (dark) Shadow(color: halo, blurRadius: height * 0.95),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Minimal — thin figures over a rule
// ---------------------------------------------------------------------------

/// Light figures and a hairline showing how much of the segment is behind us.
/// Nothing else: the face for someone who wants the number and not the dial.
class _MinimalClock extends StatelessWidget {
  const _MinimalClock({
    required this.text,
    required this.accent,
    required this.height,
    required this.progress,
  });

  final String text;
  final Color accent;
  final double height;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ruleWidth = height * 3.6;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedDigits(
          text: text,
          style: Theme.of(context).textTheme.displayLarge!.copyWith(
            fontSize: height,
            height: 1.02,
            fontWeight: FontWeight.w200,
            letterSpacing: -height * 0.02,
          ),
        ),
        SizedBox(height: height * 0.2),
        SizedBox(
          width: ruleWidth,
          height: 2,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: cs.onSurface.withValues(alpha: 0.10),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: ColoredBox(color: accent),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Analog — a dial with hands
// ---------------------------------------------------------------------------

/// The time that is left, on a dial: an hour hand, a minute hand and a second
/// hand, all reading the one value the engine has.
///
/// The hands run *down*, so the dial unwinds as the segment empties and every
/// hand meets at twelve when the block is done. A dial that swept forward
/// would be saying the session had just started; this one says how much of it
/// is left, which is the question the screen exists to answer.
///
/// The segment's own progress runs around the rim, so the dial carries both
/// readings without a second circle around it — a ring outside a dial is a
/// circle around a circle, and the one inside loses the room it needs.
class _AnalogClock extends StatelessWidget {
  const _AnalogClock({
    required this.remaining,
    required this.accent,
    required this.height,
    required this.progress,
  });

  final Duration remaining;
  final Color accent;
  final double height;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CustomPaint(
      // A dial is square, and a little larger than the figures it replaces:
      // the hands need room the glyphs did not. The parent decides how much
      // room that is — this is only the size to ask for when it does not say.
      size: Size.square(height * 1.22),
      painter: _AnalogPainter(
        remaining: remaining,
        accent: accent,
        ink: cs.onSurface,
        marks: cs.onSurfaceVariant,
        progress: progress,
      ),
    );
  }
}

class _AnalogPainter extends CustomPainter {
  const _AnalogPainter({
    required this.remaining,
    required this.accent,
    required this.ink,
    required this.marks,
    required this.progress,
  });

  final Duration remaining;
  final Color accent;
  final Color ink;
  final Color marks;

  /// How much of the segment is behind us, 0 to 1, drawn around the rim.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = s / 2;

    // The rim: the track the session fills, and the marks that make the hands'
    // positions readable as positions. The track is what the line will cover.
    final rim = radius - s * 0.03;
    canvas.drawCircle(
      center,
      rim,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.022
        ..color = marks.withValues(alpha: 0.22),
    );

    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: rim),
        -math.pi / 2,
        2 * math.pi * progress.clamp(0.0, 1.0),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.022
          ..strokeCap = StrokeCap.round
          ..color = accent,
      );
    }

    final mark = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < 60; i++) {
      final major = i % 5 == 0;
      final angle = i * math.pi / 30 - math.pi / 2;
      final outer = radius - s * 0.09;
      final inner = outer - (major ? s * 0.075 : s * 0.035);
      canvas.drawLine(
        center + Offset(math.cos(angle) * inner, math.sin(angle) * inner),
        center + Offset(math.cos(angle) * outer, math.sin(angle) * outer),
        mark
          ..strokeWidth = major ? s * 0.02 : s * 0.008
          ..color = marks.withValues(alpha: major ? 0.55 : 0.25),
      );
    }

    // Each hand reads the remainder of its own cycle — the hour of a twelve-
    // hour one, the minute of an hour, the second of a minute — so all three
    // meet at twelve exactly when the segment runs out.
    final seconds = remaining.inSeconds;
    double turns(int cycle) => (seconds % cycle) / cycle;

    void hand(
      double ofTurn,
      double length,
      double width,
      Color color,
      double tail,
    ) {
      final angle = ofTurn * 2 * math.pi - math.pi / 2;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center - direction * tail,
        center + direction * length,
        Paint()
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }

    hand(turns(43200), radius * 0.44, s * 0.045, ink, 0);
    hand(turns(3600), radius * 0.66, s * 0.030, ink, 0);
    // The second hand is the accent, with a tail past the pin, the way a real
    // one is read at a glance.
    hand(turns(60), radius * 0.76, s * 0.012, accent, radius * 0.16);

    canvas.drawCircle(center, s * 0.036, Paint()..color = ink);
    canvas.drawCircle(center, s * 0.017, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_AnalogPainter old) =>
      old.remaining != remaining ||
      old.accent != accent ||
      old.ink != ink ||
      old.marks != marks ||
      old.progress != progress;
}

/// A retro countdown dial. Marks, hand and figures all read the timer engine.
class RetroClock extends StatelessWidget {
  const RetroClock({
    super.key,
    required this.remaining,
    required this.accent,
    required this.size,
    required this.progress,
  });

  final Duration remaining;
  final Color accent;
  final double size;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RetroDialPainter(
          progress: progress,
          accent: accent,
          ink: cs.onSurface,
          marks: cs.onSurfaceVariant,
          surface: dark ? cs.surfaceContainer : const Color(0xFFDCD0B4),
          dark: dark,
        ),
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: size * 0.14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'REMAINING',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: size * 0.032,
                    letterSpacing: size * 0.007,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: size * 0.022),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    formatClock(remaining),
                    style: TextStyle(
                      fontFamily: 'InterDisplay',
                      fontSize: size * 0.17,
                      height: 1.05,
                      letterSpacing: -size * 0.008,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                SizedBox(height: size * 0.028),
                Container(
                  width: size * 0.11,
                  height: size * 0.012,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RetroDialPainter extends CustomPainter {
  const _RetroDialPainter({
    required this.progress,
    required this.accent,
    required this.ink,
    required this.marks,
    required this.surface,
    required this.dark,
  });

  final double progress;
  final Color accent;
  final Color ink;
  final Color marks;
  final Color surface;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);
    final radius = s * 0.47;
    final rect = Rect.fromCircle(center: c, radius: radius);
    canvas.drawCircle(
      c + Offset(0, s * 0.016),
      radius,
      Paint()
        ..color = Colors.black.withValues(alpha: dark ? 0.25 : 0.10)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.024),
    );
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(surface, Colors.white, dark ? 0.055 : 0.32)!,
            surface,
            Color.lerp(surface, Colors.black, dark ? 0.12 : 0.045)!,
          ],
        ).createShader(rect),
    );
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.004
        ..color = Colors.white.withValues(alpha: dark ? 0.16 : 0.8),
    );
    canvas.drawCircle(
      c,
      radius - s * 0.021,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.002
        ..color = marks.withValues(alpha: 0.22),
    );
    final p = progress.clamp(0.0, 1.0);
    final tick = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < 60; i++) {
      final major = i % 5 == 0;
      final angle = i * math.pi / 30 - math.pi / 2;
      final direction = Offset(math.cos(angle), math.sin(angle));
      final outer = radius - s * 0.045;
      final inner = outer - s * (major ? 0.066 : 0.029);
      canvas.drawLine(
        c + direction * inner,
        c + direction * outer,
        tick
          ..strokeWidth = s * (major ? 0.010 : 0.004)
          ..color = i / 60 < p
              ? accent.withValues(alpha: 0.45)
              : marks.withValues(alpha: major ? 0.85 : 0.52),
      );
      if (major) {
        final label = i == 0 ? '60' : '$i';
        final painter = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              fontFamily: 'InterDisplay',
              fontSize: s * 0.032,
              fontWeight: FontWeight.w600,
              color: marks,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final at = c + direction * (radius - s * 0.143);
        painter.paint(
          canvas,
          at - Offset(painter.width / 2, painter.height / 2),
        );
        painter.dispose();
      }
    }
    final handAngle = p * 2 * math.pi - math.pi / 2;
    final direction = Offset(math.cos(handAngle), math.sin(handAngle));
    canvas.drawLine(
      c + direction * (radius - s * 0.107),
      c + direction * (radius - s * 0.024),
      Paint()
        ..color = accent
        ..strokeWidth = s * 0.014
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      c + direction * (radius - s * 0.026),
      s * 0.017,
      Paint()..color = accent,
    );
  }

  @override
  bool shouldRepaint(_RetroDialPainter old) =>
      old.progress != progress ||
      old.accent != accent ||
      old.ink != ink ||
      old.marks != marks ||
      old.surface != surface ||
      old.dark != dark;
}
