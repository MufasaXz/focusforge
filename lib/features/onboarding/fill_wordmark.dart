import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A word that starts as empty outlines and is filled with [color] one letter
/// at a time, like ink poured into each shape.
///
/// Straight letters fill from the bottom up. Round letters (o, c, u, e, a…)
/// fill around their bowl, starting at the top and sweeping clockwise. An S
/// fills from its top terminal down, the way it is written. Each letter
/// starts a little before the previous one finishes, so the colour seems to
/// travel along the word.
///
/// Runs once. With reduce motion the word is simply drawn filled.
class FillWordmark extends StatefulWidget {
  const FillWordmark({
    super.key,
    required this.text,
    required this.style,
    required this.color,
    this.outline,
    this.delay = const Duration(milliseconds: 250),
    this.perLetter = const Duration(milliseconds: 420),
  });

  final String text;
  final TextStyle style;

  /// The fill.
  final Color color;

  /// The empty letters' outline; defaults to a faint onSurface.
  final Color? outline;
  final Duration delay;
  final Duration perLetter;

  @override
  State<FillWordmark> createState() => _FillWordmarkState();
}

class _FillWordmarkState extends State<FillWordmark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<String> _letters = widget.text.characters.toList();

  /// Each letter overlaps the previous one by this share of its own time.
  static const _overlap = 0.45;

  Duration get _total {
    final steps = 1 + (_letters.length - 1) * (1 - _overlap);
    return widget.delay + widget.perLetter * steps;
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _total);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (_controller.value == 0 && !_controller.isAnimating) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 0..1 fill of letter [i] at overall time [t] (0..1).
  double _progress(int i, double t) {
    final total = _total.inMicroseconds;
    final start =
        widget.delay.inMicroseconds +
        widget.perLetter.inMicroseconds * i * (1 - _overlap);
    final local = (t * total - start) / widget.perLetter.inMicroseconds;
    return Curves.easeInOutCubic.transform(local.clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final outline =
        widget.outline ??
        Theme.of(context).colorScheme.onSurface.withValues(alpha: .35);
    final strokeWidth = math.max(1.0, (widget.style.fontSize ?? 32) / 34);
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            for (final (i, letter) in _letters.indexed)
              _Letter(
                letter: letter,
                style: widget.style,
                color: widget.color,
                outline: outline,
                strokeWidth: strokeWidth,
                progress: _progress(i, _controller.value),
              ),
          ],
        ),
      ),
    );
  }
}

class _Letter extends StatelessWidget {
  const _Letter({
    required this.letter,
    required this.style,
    required this.color,
    required this.outline,
    required this.strokeWidth,
    required this.progress,
  });

  final String letter;
  final TextStyle style;
  final Color color;
  final Color outline;
  final double strokeWidth;
  final double progress;

  static const _round = {'o', 'c', 'u', 'e', 'a', 'g', 'O', 'C', 'U', 'G', 'Q'};

  @override
  Widget build(BuildContext context) {
    final fill = Text(letter, style: style.copyWith(color: color));
    final Widget filled;
    if (progress <= 0) {
      filled = const SizedBox.shrink();
    } else if (progress >= 1) {
      filled = fill;
    } else {
      filled = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => _mask(rect),
        child: fill,
      );
    }
    return Stack(
      children: [
        // The empty letter: just its outline until the ink arrives. The
        // outline fades as the fill completes, so no rim is left behind.
        Opacity(
          opacity: 1 - progress,
          child: Text(
            letter,
            style: style.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = strokeWidth
                ..color = outline,
            ),
          ),
        ),
        Positioned.fill(
          child: Align(alignment: Alignment.topLeft, child: filled),
        ),
      ],
    );
  }

  Shader _mask(Rect rect) {
    const on = Colors.white;
    const off = Colors.transparent;
    // A soft edge a few percent wide reads as liquid rather than a cut.
    const edge = 0.06;
    final p = progress;
    if (_round.contains(letter)) {
      // Around the bowl, clockwise from twelve o'clock.
      return SweepGradient(
        colors: const [on, on, off, off],
        stops: [0, p, math.min(1, p + edge), 1],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
    }
    if (letter == 's' || letter == 'S') {
      // Down from the top terminal, the way the stroke is written.
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [on, on, off, off],
        stops: [0, p, math.min(1, p + edge), 1],
      ).createShader(rect);
    }
    // Up from the baseline.
    return LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: const [on, on, off, off],
      stops: [0, p, math.min(1, p + edge), 1],
    ).createShader(rect);
  }
}
