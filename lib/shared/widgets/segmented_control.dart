import 'dart:math' as math;

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

    // Material's 48dp minimum target. The 4dp inset around the pill is kept
    // whenever the control is tall enough to afford it, and given up when it is
    // not: the segments themselves have to stay tappable, and a 40dp row of
    // three is exactly the kind of control that gets mis-tapped.
    final h = math.max(height, 48.0);
    final pad = math.min(4.0, (h - 48) / 2);

    return Container(
      height: h,
      padding: EdgeInsets.all(pad),
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
                  child: Semantics(
                    button: true,
                    selected: i == index,
                    label: options[i],
                    excludeSemantics: true,
                    onTap: () => onChanged(i),
                    child: Pressable(
                      scale: 0.94,
                      onTap: () => onChanged(i),
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 220),
                          style: context.type.labelLarge!.copyWith(
                            fontSize: 13,
                            color: i == index ? t.textPrimary : t.textTertiary,
                            fontWeight: i == index
                                ? FontWeight.w700
                                : FontWeight.w600,
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
                ),
            ],
          ),
        ],
      ),
    );
  }
}
