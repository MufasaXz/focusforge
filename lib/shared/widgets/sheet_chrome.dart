import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import 'pressable.dart';

/// Frosted bottom-sheet surface.
///
/// A sheet genuinely floats over the page, so its backdrop filter is one of
/// the three the design allows — σ24. The radius is a parameter because the
/// two shapes are both in use: a sheet that runs to the bottom edge rounds
/// only its top corners, while an inset one rounds all four.
class SheetSurface extends StatelessWidget {
  const SheetSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.borderRadius = const BorderRadius.vertical(
      top: Radius.circular(Radii.hero),
    ),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          color: cs.surfaceContainerLow.withValues(alpha: 0.9),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// The grabber at the top of every sheet.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
    ),
  );
}

/// The circular close affordance a sheet header carries.
class SheetCloseButton extends StatelessWidget {
  const SheetCloseButton({
    super.key,
    required this.onTap,
    this.label = 'Close',
  });

  final VoidCallback onTap;

  /// What a screen reader announces. The icon is the same everywhere; the
  /// label is not, because "close" is only right when the sheet is the thing
  /// being dismissed.
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Pressable(
          scale: 0.85,
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Icon(
                Icons.close_rounded,
                size: 20,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
