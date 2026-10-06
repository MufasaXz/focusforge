import '../../app/theme/app_theme.dart';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'pressable.dart';

// Interaction primitives moved to their own file to keep this one to the
// surfaces. Re-exported so every existing `glass_surface.dart` import keeps
// resolving `Pressable` and `GlassIconBadge` unchanged.
export 'pressable.dart';

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
    final cs = Theme.of(context).colorScheme;
    final isL2 = level >= 2;

    final fill = isL2 ? cs.surfaceContainer : cs.surfaceContainerLow;
    final border = isL2 ? cs.outlineVariant : cs.outlineVariant;
    final shadow = isL2 ? cs.shadow : cs.shadow;
    final r = BorderRadius.circular(radius);

    final borderColor = accent == null
        ? border
        : Color.lerp(
            border,
            accent,
            0.55,
          )!.withValues(alpha: (0.55 + 0.35 * glowStrength).clamp(0, 1));

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
                      colors: [Colors.white.withValues(alpha: 0.06), Colors.white.withValues(alpha: 0.06).withValues(alpha: 0)],
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
                    border: Border.all(color: cs.outlineVariant),
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
                      Colors.white.withValues(alpha: 0.14).withValues(alpha: 0),
                      Colors.white.withValues(alpha: 0.14),
                      Colors.white.withValues(alpha: 0.14).withValues(alpha: 0),
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
    final cs = Theme.of(context).colorScheme;
    final a = accent ?? cs.primary;

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: selected ? a.withValues(alpha: 0.22) : cs.surfaceContainer.withValues(alpha: 0.6),
        border: Border.all(
          color: selected ? a.withValues(alpha: 0.70) : cs.outlineVariant,
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
          color: selected ? cs.onSurface : cs.onSurfaceVariant,
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
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, Gap.md),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: cs.onSurfaceVariant),
            const SizedBox(width: Gap.sm),
          ],
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
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
