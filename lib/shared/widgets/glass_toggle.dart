import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_theme.dart';
import 'glass_surface.dart';

/// Glass capsule toggle with a spring-loaded thumb and an accent glow when on.
class GlassToggle extends StatelessWidget {
  const GlassToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.accent,
    this.width = 50,
    this.height = 30,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? accent;
  final double width;
  final double height;

  /// What the switch controls, e.g. "Block Instagram Reels". Without it a
  /// screen reader announces a bare "switch, on" in a list of twenty.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = accent ?? cs.primary;
    final thumb = height - 6;
    final enabled = onChanged != null;

    return Semantics(
      toggled: value,
      enabled: enabled,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: enabled ? () => _toggle() : null,
      child: Pressable(
        scale: 0.92,
        onTap: enabled ? _toggle : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          width: width,
          height: height,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.pill),
            gradient: value
                ? LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      a.withValues(alpha: 0.85),
                      a.withValues(alpha: 0.55),
                    ],
                  )
                : null,
            color: value ? null : cs.surfaceContainerHighest,
            border: Border.all(
              color: value ? a.withValues(alpha: 0.9) : cs.outlineVariant,
            ),
            boxShadow: value
                ? [
                    BoxShadow(
                      color: a.withValues(alpha: 0.42),
                      blurRadius: 16,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: thumb,
              height: thumb,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? Colors.white : cs.onSurfaceVariant,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _toggle() {
    // A flip is a commitment — the tap that made it should be felt, not just
    // seen.
    HapticFeedback.lightImpact();
    onChanged!(!value);
  }
}

/// Thin labelled progress bar used in lists.
///
/// The fill is a [FractionallySizedBox] inside an [Align] inside a
/// [StackFit.expand] stack: a bare Stack sizes itself from its non-positioned
/// children, so the fraction would collapse to zero width and the fill would
/// silently disappear. At 0 the fill is replaced by an empty box rather than a
/// zero-width fraction, and at 1 the fraction is exactly full width — both ends
/// of the range have to render, not just the interesting middle.
class GlassProgressBar extends StatelessWidget {
  const GlassProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 5,
    this.trackColor,
    this.semanticLabel,
  });

  final double value;
  final Color color;
  final double height;
  final Color? trackColor;

  /// Announced as "<label>, 64 percent" when provided.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = value.clamp(0.0, 1.0);

    final bar = SizedBox(
      width: double.infinity,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.pill),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: trackColor ?? cs.surfaceContainerHighest),
            Align(
              alignment: Alignment.centerLeft,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: v),
                duration: const Duration(milliseconds: 950),
                curve: Curves.easeOutCubic,
                builder: (context, animated, _) {
                  final fraction = animated.clamp(0.0, 1.0);
                  if (fraction <= 0) return const SizedBox.shrink();
                  return FractionallySizedBox(
                    widthFactor: fraction,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [color.withValues(alpha: 0.88), color],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (semanticLabel == null) return bar;
    return Semantics(
      label: semanticLabel,
      value: '${(v * 100).round()} percent',
      child: bar,
    );
  }
}
