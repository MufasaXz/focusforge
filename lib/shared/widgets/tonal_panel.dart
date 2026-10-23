import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

/// A quiet, theme-aware surface for the app's primary content.
class TonalPanel extends StatelessWidget {
  const TonalPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Gap.xl),
    this.accent = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.hero),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: accent
              ? [cs.primaryContainer, cs.surfaceContainerLow]
              : [cs.surfaceContainerLow, cs.surfaceContainer],
        ),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// A lifted hero surface: the soft primary wash and quiet shadow that marks
/// the one card on a page meant to be read as a cover rather than a tile.
///
/// The same treatment was being assembled by hand in the profile hero and the
/// first-run goal card, which is how two cards that should read identically
/// drift a few alpha points apart. One primitive keeps the hero look in one
/// place; `accent` keeps the wash in the live palette rather than a hard hue.
class HeroSurface extends StatelessWidget {
  const HeroSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Gap.xl),
    this.borderRadius = Radii.hero,
    this.accentStrength = 0.10,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  /// How much of the scheme's primary bleeds into the surface and the glow.
  /// Lower reads flatter; the two callers that started this pattern sit at 0.10
  /// and 0.12, so the default splits them and a stronger lift is a deliberate
  /// choice rather than a drift.
  final double accentStrength;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              cs.primary.withValues(alpha: accentStrength),
              cs.surface,
            ),
            cs.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: cs.primary.withValues(alpha: accentStrength * 2.2),
        ),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: accentStrength),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.label, {super.key, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: Gap.sm),
        ],
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.primary,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
