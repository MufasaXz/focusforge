import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import 'glass_surface.dart';

/// The provider marks the account surfaces draw: the Google "G" and the mail
/// envelope, each sitting in the rounded square every sign-in sheet puts them
/// in.
///
/// Google is painted rather than lettered. The Material icon that reads as a
/// "G" is a monochrome glyph of a different shape, and on a sign-in screen the
/// four-colour mark is the thing that says *Google* before the label is read —
/// a grey G says "generic provider". Painting it also keeps the dependency
/// list at zero: an SVG asset would need a renderer, and a bundled PNG would
/// blur at whatever size the badge lands on.
class GoogleMark extends StatelessWidget {
  const GoogleMark({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: const _GooglePainter(),
    isComplex: false,
  );
}

/// The mail mark: an envelope in the red the account sheets use for mail.
class MailMark extends StatelessWidget {
  const MailMark({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.mail_rounded, size: size, color: const Color(0xFFEA4335));
}

/// A provider mark in its rounded square: the box every account screen draws
/// behind the logo, on the tonal surface the rest of the app uses.
class ProviderBadge extends StatelessWidget {
  const ProviderBadge({super.key, required this.child, this.size = 38});

  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: cs.outlineVariant, width: 1),
      ),
      child: Center(child: child),
    );
  }
}

/// The four-colour G.
///
/// The mark is a ring with a bite taken out of its upper right, plus the bar
/// that turns the bite into a G. Four arcs of one circle and one rectangle
/// reproduce it; the colours and where each arc hands over to the next are
/// what make it recognisable, so they are named rather than inlined.
class _GooglePainter extends CustomPainter {
  const _GooglePainter();

  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2);
    final stroke = s * 0.23;
    final radius = (s - stroke) / 2;
    final ring = Rect.fromCircle(center: center, radius: radius);

    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    // Angles run clockwise from due east, the same convention `drawArc` uses.
    // The spans are the mark's own: the mouth is the gap the bar turns into
    // the G's tongue, and it sits on the upper right, just above the
    // horizontal — not at three o'clock, and nowhere near as wide as a
    // quarter.
    void arc(double fromDegrees, double sweepDegrees, Color color) {
      canvas.drawArc(
        ring,
        fromDegrees * math.pi / 180,
        sweepDegrees * math.pi / 180,
        false,
        pen..color = color,
      );
    }

    arc(-153, 105, _red); // the top, from the left shoulder over to two
    arc(-10, 59, _blue); // the right, from just above the bar down to 4:30
    arc(49, 104, _green); // the bottom
    arc(153, 54, _yellow); // the left, closing back onto the red
    // Nothing is drawn from -48° to -10°: that gap is the mouth.

    // The bar, straddling the middle — it sits half above the centre line and
    // half below, the way the mark draws it — and running out to the ring's
    // edge, where it meets the blue. It is what closes the mouth into a G
    // rather than a C.
    canvas.drawRect(
      Rect.fromLTRB(
        center.dx,
        center.dy - stroke * 0.45,
        center.dx + radius + stroke / 2,
        center.dy + stroke * 0.5,
      ),
      Paint()..color = _blue,
    );
  }

  @override
  bool shouldRepaint(_GooglePainter oldDelegate) => false;
}

/// The provider rows the account surfaces share: the Google and email options,
/// with their marks in the same rounded squares.
///
/// Shared because the sign-in screen and the profile's link-account sheet have
/// to offer the same two choices; a second hand-built row would drift from
/// this one the first time either is touched.
class ProviderRow extends StatefulWidget {
  const ProviderRow({
    super.key,
    required this.label,
    required this.leading,
    this.subtitle,
    this.onTap,
    this.busy = false,
    this.done = false,
  });

  final String label;
  final Widget leading;
  final String? subtitle;

  /// Null when the backend cannot mint this credential: the row stays on
  /// screen, dimmed and inert, so the option is explained rather than hidden.
  final VoidCallback? onTap;
  final bool busy;

  /// True for the beat after this row's call succeeded.
  final bool done;

  @override
  State<ProviderRow> createState() => _ProviderRowState();
}

class _ProviderRowState extends State<ProviderRow> {
  bool _pressed = false;

  bool get _live => widget.onTap != null && !widget.busy && !widget.done;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduce = MediaQuery.disableAnimationsOf(context);

    return Listener(
      // A raw pointer listener rather than a gesture recogniser: it does not
      // enter the gesture arena, so the row's own onTap still fires normally.
      onPointerDown: _live ? (_) => setState(() => _pressed = true) : null,
      onPointerUp: _live ? (_) => setState(() => _pressed = false) : null,
      onPointerCancel: _live ? (_) => setState(() => _pressed = false) : null,
      child: AnimatedScale(
        scale: _pressed && !reduce ? 0.975 : 1,
        duration: reduce ? Duration.zero : const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: GlassCard(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.item),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            subtitle: widget.subtitle == null
                ? null
                : Text(
                    widget.subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
            onTap: _live ? widget.onTap : null,
            // Null makes the row informational: the provider is explained
            // rather than hidden, and the disabled palette says so.
            enabled: _live,
            leading: AnimatedSwitcher(
              duration: reduce ? Duration.zero : Motion.base,
              child: widget.done
                  ? ProviderBadge(
                      key: const ValueKey('done'),
                      size: 44,
                      child: Icon(
                        Icons.check_rounded,
                        size: 20,
                        color: cs.primary,
                      ),
                    )
                  : ProviderBadge(
                      key: const ValueKey('mark'),
                      size: 44,
                      child: widget.leading,
                    ),
            ),
            title: Text(widget.label, style: theme.textTheme.titleSmall),
            trailing: widget.busy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  )
                : Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
          ),
        ),
      ),
    );
  }
}
