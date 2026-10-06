import 'package:flutter/material.dart';

import '../../app/theme/color_tokens.dart';
import '../../app/theme/glass_theme.dart';
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
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? accent;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final a = accent ?? t.accentPrimary;
    final thumb = height - 6;

    return Pressable(
      scale: 0.92,
      onTap: onChanged == null ? null : () => onChanged!(!value),
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
          color: value ? null : t.track,
          border: Border.all(
            color: value
                ? a.withValues(alpha: 0.9)
                : t.glassL2Border,
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
              color: value ? Colors.white : t.textTertiary,
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
    );
  }
}

/// Thin labelled progress bar used in lists.
///
/// Note the explicit [StackFit.expand] and full-width box: a bare Stack sizes
/// itself from its non-positioned children, so a [FractionallySizedBox] inside
/// one collapses to zero width and the fill silently disappears.
class GlassProgressBar extends StatelessWidget {
  const GlassProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 5,
    this.trackColor,
  });

  final double value;
  final Color color;
  final double height;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final v = value.clamp(0.0, 1.0);

    return SizedBox(
      width: double.infinity,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.pill),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: trackColor ?? t.track),
            Align(
              alignment: Alignment.centerLeft,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: v),
                duration: const Duration(milliseconds: 950),
                curve: Curves.easeOutCubic,
                builder: (context, animated, _) => FractionallySizedBox(
                  widthFactor: animated.clamp(0.0, 1.0),
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          color.withValues(alpha: 0.88),
                          color,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
