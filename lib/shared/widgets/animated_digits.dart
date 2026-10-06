import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Timer text that rolls.
///
/// Only the glyphs that actually changed animate: an [AnimatedSwitcher] keyed
/// on the whole string would re-run the transition for all five characters
/// every second, which reads as a flicker rather than a clock. Each glyph sits
/// in a box measured from the glyph itself, so tabular figures stay aligned and
/// the row never jitters sideways when a `1` replaces a `0`.
class AnimatedDigits extends StatelessWidget {
  const AnimatedDigits({
    super.key,
    required this.text,
    required this.style,
    this.duration = const Duration(milliseconds: 260),
  });

  final String text;
  final TextStyle style;
  final Duration duration;

  @override
  Widget build(BuildContext context) =>
      _RollingText(text: text, style: style, duration: duration);
}

class _RollingText extends StatefulWidget {
  const _RollingText({
    required this.text,
    required this.style,
    required this.duration,
  });

  final String text;
  final TextStyle style;
  final Duration duration;

  @override
  State<_RollingText> createState() => _RollingTextState();
}

class _RollingTextState extends State<_RollingText> {
  /// What was on screen before this build — the source of the "did it change?"
  /// decision, and the reason the widget has to hold state at all.
  late String _previous = widget.text;

  final Map<String, double> _advances = {};
  TextStyle? _measuredStyle;
  TextScaler? _measuredScaler;

  @override
  void didUpdateWidget(covariant _RollingText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _previous = old.text;
  }

  /// Width of a single glyph, measured once per style/scale. Measuring beats a
  /// `fontSize * 0.6` guess because Inter's colon is roughly half a digit wide,
  /// and a guessed width would push the string out of alignment with every
  /// plain [Text] around it.
  double _advanceOf(BuildContext context, String glyph) {
    if (glyph.isEmpty) return 0;
    final scaler = MediaQuery.textScalerOf(context);
    if (_measuredStyle != widget.style || _measuredScaler != scaler) {
      _advances.clear();
      _measuredStyle = widget.style;
      _measuredScaler = scaler;
    }
    return _advances.putIfAbsent(glyph, () {
      final painter = TextPainter(
        text: TextSpan(text: glyph, style: widget.style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cells = math.max(widget.text.length, _previous.length);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : widget.duration;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [for (var i = 0; i < cells; i++) _cell(context, i, duration)],
    );
  }

  Widget _cell(BuildContext context, int index, Duration duration) {
    final glyph = index < widget.text.length ? widget.text[index] : '';
    final key = ValueKey<String>('$index:$glyph');

    return SizedBox(
      width: _advanceOf(context, glyph),
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: duration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          // Incoming rises from below, outgoing continues upward. The two
          // tweens are asymmetric because AnimatedSwitcher plays the outgoing
          // animation in reverse — this is what makes the pair read as one
          // roll instead of a cross-fade.
          transitionBuilder: (child, animation) {
            final incoming = child.key == key;
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position:
                    (incoming
                            ? Tween<Offset>(
                                begin: const Offset(0, 0.85),
                                end: Offset.zero,
                              )
                            : Tween<Offset>(
                                begin: const Offset(0, -0.85),
                                end: Offset.zero,
                              ))
                        .animate(animation),
                child: child,
              ),
            );
          },
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.center,
            children: [...previous, ?current],
          ),
          child: glyph.isEmpty
              ? SizedBox.shrink(key: key)
              : Text(
                  glyph,
                  key: key,
                  style: widget.style,
                  maxLines: 1,
                  softWrap: false,
                ),
        ),
      ),
    );
  }
}
