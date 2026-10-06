import 'package:flutter/material.dart';

import '../../../app/theme/color_tokens.dart';
import '../../../app/theme/glass_theme.dart';
import '../../../core/data/mock_data.dart';

/// Weekly focus bars.
///
/// Today's bar carries the accent gradient, a bloom and a value label; the rest
/// are quiet ghost bars so the eye lands on today first. Faint gridlines give
/// the chart a readable scale without adding chrome.
class WeeklyChart extends StatefulWidget {
  const WeeklyChart({super.key, required this.days, this.height = 148});

  final List<DayBar> days;
  final double height;

  @override
  State<WeeklyChart> createState() => _WeeklyChartState();
}

class _WeeklyChartState extends State<WeeklyChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final maxHours = widget.days
        .map((d) => d.hours)
        .fold<double>(1, (a, b) => a > b ? a : b);

    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          // Scale gridlines.
          Positioned.fill(
            bottom: 22,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < 4; i++)
                  Container(height: 1, color: t.hairline),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < widget.days.length; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: i == 0 || i == widget.days.length - 1 ? 1 : 4,
                    ),
                    child: _Bar(
                      day: widget.days[i],
                      maxHours: maxHours,
                      animation: CurvedAnimation(
                        parent: _c,
                        // Staggered left-to-right so the chart grows rather
                        // than popping in all at once.
                        curve: Interval(
                          (i / widget.days.length) * 0.55,
                          (i / widget.days.length) * 0.55 + 0.45,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                      accent: t.accentPrimary,
                      accent2: t.accentSecondary,
                      muted: t.textPrimary,
                      track: t.track,
                      hairline: t.hairline,
                      label: context.type.labelSmall!,
                      valueStyle: context.type.labelMedium!,
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

class _Bar extends StatelessWidget {
  const _Bar({
    required this.day,
    required this.maxHours,
    required this.animation,
    required this.accent,
    required this.accent2,
    required this.muted,
    required this.track,
    required this.hairline,
    required this.label,
    required this.valueStyle,
  });

  final DayBar day;
  final double maxHours;
  final Animation<double> animation;
  final Color accent;
  final Color accent2;
  final Color muted;
  final Color track;
  final Color hairline;
  final TextStyle label;
  final TextStyle valueStyle;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final fraction = (day.hours / maxHours).clamp(0.0, 1.0);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (day.isToday)
          AnimatedBuilder(
            animation: animation,
            builder: (context, _) => Opacity(
              opacity: animation.value.clamp(0.0, 1.0),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${day.hours}h',
                  style: valueStyle.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ),
          ),
        Expanded(
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final v = (fraction * animation.value).clamp(0.0, 1.0);
              return Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: v.clamp(0.03, 1.0),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: day.isToday
                            ? [accent, accent2.withValues(alpha: 0.72)]
                            : [
                                muted.withValues(alpha: 0.20),
                                muted.withValues(alpha: 0.07),
                              ],
                      ),
                      border: Border.all(
                        color: day.isToday
                            ? accent.withValues(alpha: 0.75)
                            : hairline,
                      ),
                      boxShadow: day.isToday
                          ? [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.42),
                                blurRadius: 20,
                                spreadRadius: -4,
                              ),
                              BoxShadow(
                                color: accent2.withValues(alpha: 0.22),
                                blurRadius: 34,
                                spreadRadius: -6,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: Gap.sm),
        Text(
          day.label,
          style: label.copyWith(
            color: day.isToday ? accent : t.textTertiary,
            fontWeight: day.isToday ? FontWeight.w700 : FontWeight.w500,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
