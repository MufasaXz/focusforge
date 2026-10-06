import 'package:flutter/material.dart';

/// Rounded tonal badge used for app icons and section glyphs.
///
/// Takes either a Material [icon] or a short text [glyph] — never an emoji, so
/// every badge in the app shares one weight and corner radius.
///
/// The tint is the caller's colour at low alpha with the colour itself as the
/// foreground. That is the Material 3 tonal-container pairing: it keeps an
/// arbitrary hue (a subject colour, a feed's brand colour) legible on any
/// surface without a gradient or an outer bloom, both of which read as
/// decoration rather than as state.
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    this.icon,
    this.glyph,
    required this.color,
    this.size = 40,
    this.radius = 12,
    this.semanticLabel,
  });

  final IconData? icon;
  final String? glyph;
  final Color color;
  final double size;
  final double radius;

  /// Decorative by default: the badge normally sits beside a label that already
  /// names it, and hearing "M" announced for a maths tile is noise. Pass a
  /// label only when the badge is the thing that carries the meaning.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: glyph != null
          ? Text(
              glyph!,
              style: TextStyle(
                fontSize: size * 0.34,
                height: 1,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: -0.2,
              ),
            )
          : Icon(icon, size: size * 0.50, color: color),
    );

    if (semanticLabel == null) return ExcludeSemantics(child: badge);
    return Semantics(label: semanticLabel, image: true, child: badge);
  }
}
