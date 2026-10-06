import 'package:flutter/material.dart';

import '../../../app/theme/color_tokens.dart';
import '../../../app/theme/glass_theme.dart';

/// Month heatmap — a 7-column calendar where each cell is shaded by focus
/// intensity. Reads left-to-right, oldest week first.
///
/// Intensity is quantised into five steps rather than interpolated: discrete
/// levels are far easier to compare at a glance than a continuous ramp.
class FocusHeatmap extends StatelessWidget {
  const FocusHeatmap({
    super.key,
    required this.weeks,
    this.weekdayLabels = const ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
  });

  final List<List<double>> weeks;
  final List<String> weekdayLabels;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;

    return Column(
      children: [
        Row(
          children: [
            for (final label in weekdayLabels)
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: context.type.labelSmall?.copyWith(
                      color: t.textTertiary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 7),
        for (var w = 0; w < weeks.length; w++)
          Row(
            children: [
              for (var d = 0; d < weeks[w].length; d++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: _Cell(
                      intensity: weeks[w][d],
                      // Newest week animates in last.
                      delay: Duration(milliseconds: (w * 7 + d) * 12),
                      isLast: w == weeks.length - 1 && d == 3,
                    ),
                  ),
                ),
            ],
          ),
        const SizedBox(height: Gap.lg),
        Row(
          children: [
            Text(
              'Less',
              style: context.type.labelSmall?.copyWith(
                fontSize: 10,
                color: t.textTertiary,
              ),
            ),
            const SizedBox(width: Gap.sm),
            for (var level = 0; level < 5; level++) ...[
              _Swatch(level: level, delay: Duration.zero, radius: 3, t: t),
              const SizedBox(width: 4),
            ],
            const SizedBox(width: Gap.sm),
            Text(
              'More',
              style: context.type.labelSmall?.copyWith(
                fontSize: 10,
                color: t.textTertiary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Maps a 0..1 intensity onto one of five discrete levels.
int _levelFor(double intensity) {
  if (intensity <= 0.05) return 0;
  if (intensity < 0.3) return 1;
  if (intensity < 0.55) return 2;
  if (intensity < 0.8) return 3;
  return 4;
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.intensity,
    required this.delay,
    required this.isLast,
  });

  final double intensity;
  final Duration delay;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        children: [
          Positioned.fill(
            child: _Swatch(
              level: _levelFor(intensity),
              delay: delay,
              radius: 6,
              t: t,
            ),
          ),
          if (isLast)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: t.textPrimary.withValues(alpha: 0.75),
                    width: 1.4,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Fades + scales in after [delay], then holds.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.level,
    required this.delay,
    required this.radius,
    required this.t,
  });

  final int level;
  final Duration delay;
  final double radius;
  final GlassTokens t;

  Color get _color => switch (level) {
        0 => t.track.withValues(alpha: t.track.a * 0.55),
        1 => t.accentPrimary.withValues(alpha: 0.24),
        2 => t.accentPrimary.withValues(alpha: 0.46),
        3 => t.accentPrimary.withValues(alpha: 0.74),
        _ => t.accentSecondary,
      };

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 460),
      curve: Curves.easeOutCubic,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          color: _color,
          border: Border.all(
            color: level >= 4
                ? t.accentSecondary.withValues(alpha: 0.7)
                : t.hairline,
          ),
          boxShadow: level >= 4
              ? [
                  BoxShadow(
                    color: t.accentSecondary.withValues(alpha: 0.40),
                    blurRadius: 12,
                    spreadRadius: -3,
                  ),
                ]
              : null,
        ),
      ),
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.scale(scale: 0.72 + 0.28 * v, child: child),
      ),
    );
  }
}
