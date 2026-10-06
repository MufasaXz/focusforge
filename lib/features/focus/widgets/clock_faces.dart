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
  });

  final Duration remaining;
  final ClockFace face;
  final Color accent;
  final double height;

  /// How much of the segment is behind us, 0 to 1. Only the minimal face
  /// draws it — the others have the ring around them for that.
  final double progress;

  @override
  Widget build(BuildContext context) {
    final text = formatClock(remaining);

    switch (face) {
      case ClockFace.digits:
        return AnimatedDigits(
          text: text,
          style: _baseStyle(context).copyWith(fontSize: height),
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
    }
  }

  TextStyle _baseStyle(BuildContext context) => Theme.of(context)
      .textTheme
      .displayLarge!
      .copyWith(
        height: 1.02,
        letterSpacing: -height * 0.042,
        fontWeight: FontWeight.w600,
      );
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
      fontSize: height * 0.62,
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
    final radius = widget.height * 0.14;
    final background = cs.surfaceContainerHighest;
    final divider = Color.alphaBlend(
      cs.surface.withValues(alpha: 0.55),
      cs.onSurface.withValues(alpha: 0.22),
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

          return DecoratedBox(
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(radius),
            ),
            child: Stack(
              children: [
                // The halves the flap will uncover.
                _Half(
                  glyph: _current,
                  style: widget.style,
                  top: true,
                  width: widget.width,
                  height: widget.height,
                ),
                _Half(
                  glyph: falling ? _outgoing : _current,
                  style: widget.style,
                  top: false,
                  width: widget.width,
                  height: widget.height,
                ),
                if (falling)
                  _FlippingHalf(
                    glyph: _outgoing,
                    style: widget.style,
                    top: true,
                    width: widget.width,
                    height: widget.height,
                    angle: -math.pi / 2 * (t / 0.5),
                  )
                else
                  _FlippingHalf(
                    glyph: _current,
                    style: widget.style,
                    top: false,
                    width: widget.width,
                    height: widget.height,
                    angle: math.pi / 2 * (1 - (t - 0.5) / 0.5),
                  ),
                // The hinge line, drawn over both halves.
                Positioned(
                  left: 0,
                  right: 0,
                  top: widget.height / 2 - 0.5,
                  child: Container(height: 1, color: divider),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Half a card, unrotated.
class _Half extends StatelessWidget {
  const _Half({
    required this.glyph,
    required this.style,
    required this.top,
    required this.width,
    required this.height,
  });

  final String glyph;
  final TextStyle style;
  final bool top;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.vertical(
      top: top ? Radius.circular(height * 0.14) : Radius.zero,
      bottom: top ? Radius.zero : Radius.circular(height * 0.14),
    ),
    child: Align(
      alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
      heightFactor: 0.5,
      child: SizedBox(
        width: width,
        height: height,
        child: Center(child: Text(glyph, style: style, maxLines: 1)),
      ),
    ),
  );
}

/// Half a card, hinged at its inner edge and turned in 3D.
class _FlippingHalf extends StatelessWidget {
  const _FlippingHalf({
    required this.glyph,
    required this.style,
    required this.top,
    required this.width,
    required this.height,
    required this.angle,
  });

  final String glyph;
  final TextStyle style;
  final bool top;
  final double width;
  final double height;
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
