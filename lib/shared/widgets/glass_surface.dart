import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/theme/color_tokens.dart';
import '../../app/theme/glass_theme.dart';

/// The base glass surface.
///
/// Four stacked details turn a translucent rectangle into something that reads
/// as a physical pane:
///   1. a translucent fill with a hairline border,
///   2. an inset second rim, which reads as edge *thickness*,
///   3. a soft sheen falling across the upper half,
///   4. a bright specular line along the top edge.
///
/// [blur] is intentionally opt-in: a real [BackdropFilter] is expensive, so it
/// is reserved for the few surfaces that genuinely float (the navigation bar,
/// hero cards, sheets). Everything else fakes it, which over a soft background
/// is visually indistinguishable and costs nothing.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.level = 1,
    this.radius = Radii.card,
    this.blur = 0,
    this.padding,
    this.width,
    this.height,
    this.accent,
    this.glowStrength = 0,
    this.gradient,
    this.sheen = true,
  });

  final Widget child;

  /// 1 = base panels, 2 = elevated.
  final int level;

  final double radius;

  /// Sigma for the backdrop blur. 0 disables the backdrop filter entirely.
  final double blur;

  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;

  /// Tints the border and enables the accent glow.
  final Color? accent;

  /// 0..1 multiplier for the accent glow.
  final double glowStrength;

  /// Optional fill override (used by the nav pill and progress tracks).
  final Gradient? gradient;

  /// Set false for tiny surfaces where the sheen would just add noise.
  final bool sheen;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final isL2 = level >= 2;

    final fill = isL2 ? t.glassL2Fill : t.glassL1Fill;
    final border = isL2 ? t.glassL2Border : t.glassL1Border;
    final shadow = isL2 ? t.glassL2Shadow : t.glassL1Shadow;
    final r = BorderRadius.circular(radius);

    final borderColor = accent == null
        ? border
        : Color.lerp(border, accent, 0.55)!
            .withValues(alpha: (0.55 + 0.35 * glowStrength).clamp(0, 1));

    final shadows = <BoxShadow>[
      // Ambient occlusion — wide and soft.
      BoxShadow(
        color: shadow.withValues(alpha: shadow.a * 0.55),
        blurRadius: isL2 ? 34 : 44,
        spreadRadius: -6,
        offset: Offset(0, isL2 ? 14 : 20),
      ),
      // Key light — tight contact shadow.
      BoxShadow(
        color: shadow.withValues(alpha: shadow.a * 0.85),
        blurRadius: isL2 ? 10 : 14,
        offset: Offset(0, isL2 ? 3 : 5),
      ),
      if (accent != null && glowStrength > 0)
        BoxShadow(
          color: accent!.withValues(alpha: 0.32 * glowStrength),
          blurRadius: 30 * glowStrength + 10,
          spreadRadius: glowStrength * 1.5,
        ),
    ];

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: gradient == null ? fill : null,
        gradient: gradient,
        borderRadius: r,
        border: Border.all(
          color: borderColor,
          width: accent != null && glowStrength > 0.4 ? 1.3 : 1,
        ),
        boxShadow: shadows,
      ),
      child: Stack(
        children: [
          if (sheen)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: r,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [t.sheen, t.sheen.withValues(alpha: 0)],
                      stops: const [0, 0.62],
                    ),
                  ),
                ),
              ),
            ),
          // Inset rim — the "second edge" that implies thickness.
          Positioned.fill(
            child: IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.all(1),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius - 1),
                    border: Border.all(color: t.innerRim),
                  ),
                ),
              ),
            ),
          ),
          // Specular top edge.
          Positioned(
            top: 0,
            left: radius * 0.5,
            right: radius * 0.5,
            child: IgnorePointer(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      t.specular.withValues(alpha: 0),
                      t.specular,
                      t.specular.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ],
      ),
    );

    if (blur > 0) {
      surface = ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: surface,
        ),
      );
    }

    if (width != null || height != null) {
      surface = SizedBox(width: width, height: height, child: surface);
    }

    return surface;
  }
}

/// Scale-on-press wrapper. Springs back with a slight overshoot so taps feel
/// physical rather than binary.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.965,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool value) {
    if (_down == value) return;
    setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        // Fast in, springy out — the asymmetry is what makes it feel like a
        // physical control rather than a CSS transition.
        duration: Duration(milliseconds: _down ? 90 : 340),
        curve: _down ? Curves.easeOutCubic : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// Rounded gradient badge used for app icons and section glyphs.
///
/// Takes either a Material [icon] or a short text [glyph] — never an emoji, so
/// that every badge in the app shares one weight, corner radius and lighting.
class GlassIconBadge extends StatelessWidget {
  const GlassIconBadge({
    super.key,
    this.icon,
    this.glyph,
    required this.color,
    this.size = 40,
    this.radius = 12,
    this.glow = 0,
  });

  final IconData? icon;
  final String? glyph;
  final Color color;
  final double size;
  final double radius;

  /// 0..1 — adds an outer accent bloom.
  final double glow;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.38),
            color.withValues(alpha: 0.16),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.48)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.18 + 0.30 * glow),
            blurRadius: 12 + 14 * glow,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Top-left inner highlight, matching the panel treatment.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [t.sheen, t.sheen.withValues(alpha: 0)],
                    stops: const [0, 0.7],
                  ),
                ),
              ),
            ),
          ),
          Center(
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
          ),
        ],
      ),
    );
  }
}

/// Small translucent pill — status badges, tags, segmented controls.
class GlassPill extends StatelessWidget {
  const GlassPill({
    super.key,
    required this.child,
    this.selected = false,
    this.accent,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    this.onTap,
    this.radius = Radii.pill,
  });

  final Widget child;
  final bool selected;
  final Color? accent;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final a = accent ?? t.accentPrimary;

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: selected
            ? a.withValues(alpha: 0.22)
            : t.glassL2At(0.6),
        border: Border.all(
          color: selected ? a.withValues(alpha: 0.70) : t.glassL2Border,
          width: selected ? 1.2 : 1,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: a.withValues(alpha: 0.30),
                  blurRadius: 18,
                  spreadRadius: -3,
                ),
              ]
            : null,
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: selected ? t.textPrimary : t.textSecondary,
          fontWeight: FontWeight.w600,
          fontSize: 13,
          letterSpacing: -0.1,
        ),
        child: child,
      ),
    );

    if (onTap == null) return content;
    return Pressable(onTap: onTap, child: content);
  }
}

/// Section label used above grouped cards.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.icon,
  });

  final String title;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, Gap.md),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: t.textTertiary),
            const SizedBox(width: Gap.sm),
          ],
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: context.type.labelMedium?.copyWith(
                color: t.textTertiary,
                letterSpacing: 1.3,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Horizontal fade mask — applied to the edges of horizontally scrolling rows
/// so items dissolve instead of being sliced off mid-chip.
class EdgeFade extends StatelessWidget {
  const EdgeFade({
    super.key,
    required this.child,
    this.leading = 0,
    this.trailing = 24,
  });

  final Widget child;
  final double leading;
  final double trailing;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => LinearGradient(
        colors: [
          leading > 0 ? Colors.transparent : Colors.black,
          Colors.black,
          Colors.black,
          trailing > 0 ? Colors.transparent : Colors.black,
        ],
        stops: [
          0,
          leading > 0 ? (leading / rect.width).clamp(0.0, 0.4) : 0.0,
          trailing > 0 ? 1 - (trailing / rect.width).clamp(0.0, 0.4) : 1.0,
          1,
        ],
      ).createShader(rect),
      child: child,
    );
  }
}
