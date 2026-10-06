import 'package:flutter/material.dart';

import '../../app/theme/color_tokens.dart';
import '../../app/theme/glass_theme.dart';
import 'glass_surface.dart';

/// Sliding segmented control. The active segment is a glowing pill that
/// travels between options with a spring settle.
class SegmentedControl extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.options,
    required this.index,
    required this.onChanged,
    this.accent,
    this.height = 46,
  });

  final List<String> options;
  final int index;
  final ValueChanged<int> onChanged;
  final Color? accent;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final a = accent ?? t.accentPrimary;
    final n = options.length;

    return Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.pill),
        color: t.glassL2At(0.55),
        border: Border.all(color: t.glassL2Border),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutBack,
            alignment: Alignment(n == 1 ? 0 : -1 + 2 * index / (n - 1), 0),
            child: FractionallySizedBox(
              widthFactor: 1 / n,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  gradient: LinearGradient(
                    colors: [
                      a.withValues(alpha: 0.30),
                      t.accentSecondary.withValues(alpha: 0.20),
                    ],
                  ),
                  border: Border.all(color: a.withValues(alpha: 0.55)),
                  boxShadow: [
                    BoxShadow(
                      color: a.withValues(alpha: 0.30),
                      blurRadius: 16,
                      spreadRadius: -3,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < n; i++)
                Expanded(
                  child: Pressable(
                    scale: 0.94,
                    onTap: () => onChanged(i),
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 220),
                        style: context.type.labelLarge!.copyWith(
                          fontSize: 13,
                          color: i == index ? t.textPrimary : t.textTertiary,
                          fontWeight:
                              i == index ? FontWeight.w700 : FontWeight.w600,
                        ),
                        child: Text(
                          options[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
