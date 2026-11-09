import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import 'pressable.dart';

/// The two option chips used wherever a glyph or a colour is picked: a new
/// subject, an avatar.
///
/// Each has a name, because a screen reader cannot describe a glyph or a
/// colour by itself, and the same name shows as a tooltip on a long press
/// or a hover. The visible chip is 44dp inside a 48dp target; lay them out
/// with [spacing] so the chips sit [Gap.sm] apart.
abstract final class ChoiceSwatch {
  static const double spacing = Gap.xs;
}

/// One glyph to choose: an icon, or an avatar's initials. Selection shows as
/// colour and as a check badge, so it does not depend on telling the colours
/// apart.
class GlyphChoice extends StatelessWidget {
  const GlyphChoice({
    super.key,
    required this.label,
    required this.accent,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  /// Drawn in the chip's ink colour, through [IconTheme] and the default
  /// text style.
  final Widget child;
  final String label;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final still = MediaQuery.disableAnimationsOf(context);
    return _Target(
      label: label,
      selected: selected,
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: still ? Duration.zero : Motion.quick,
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.18)
                  : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(Radii.tile),
              border: Border.all(
                color: selected ? accent : cs.outlineVariant,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Center(
              child: IconTheme.merge(
                data: IconThemeData(
                  size: 19,
                  color: selected ? accent : cs.onSurfaceVariant,
                ),
                child: DefaultTextStyle.merge(
                  style: TextStyle(
                    color: selected ? accent : cs.onSurfaceVariant,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
          if (selected)
            PositionedDirectional(
              top: -4,
              end: -4,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: cs.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: accent, width: 1.4),
                ),
                child: Icon(Icons.check_rounded, size: 11, color: accent),
              ),
            ),
        ],
      ),
    );
  }
}

/// One colour to choose. The selected one trades its dot for a check, so
/// the choice reads by shape as well as by ring.
class ColorChoice extends StatelessWidget {
  const ColorChoice({
    super.key,
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final still = MediaQuery.disableAnimationsOf(context);
    return _Target(
      label: label,
      selected: selected,
      onTap: onTap,
      child: AnimatedContainer(
        duration: still ? Duration.zero : Motion.quick,
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: selected ? 0.22 : 0.10),
          border: Border.all(
            color: selected ? color : cs.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Center(
          child: selected
              ? Icon(Icons.check_rounded, size: 20, color: color)
              : Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                  ),
                ),
        ),
      ),
    );
  }
}

/// A 48dp target with a name, a selected state and a tooltip.
class _Target extends StatelessWidget {
  const _Target({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Pressable(
        onTap: onTap,
        scale: 0.88,
        child: SizedBox.square(dimension: 48, child: Center(child: child)),
      ),
    ),
  );
}
