import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/color_tokens.dart';
import '../../../app/theme/glass_theme.dart';
import '../../../core/data/seed.dart';

/// Weekly focus bars.
///
/// Tapping a bar pins its value in a floating bubble; tapping the selected bar
/// again dismisses it. The bubble is positioned over the chart rather than
/// stacked inside the bar's column, so selecting a day never changes the
/// height of the bar it describes. Today starts selected — the chart opens on
/// the number that matters most — and the accent moves with the selection so
/// it is always obvious which day the bubble belongs to.
class WeeklyChart extends StatefulWidget {
  const WeeklyChart({super.key, required this.days, this.height = 148});

  final List<DayBar> days;
  final double height;

  @override
  State<WeeklyChart> createState() => _WeeklyChartState();
}

class _WeeklyChartState extends State<WeeklyChart>
    with SingleTickerProviderStateMixin {
  static const _bubbleWidth = 52.0;
  static const _bubbleHeight = 30.0;

  /// Height reserved for the day labels under the bars.
  static const _axisHeight = 22.0;

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..forward();

  int? _selected;

  /// Bar the bubble is anchored to. Kept when the selection is cleared so the
  /// bubble fades out in place instead of sliding back to today mid-fade.
  int _anchor = 0;

  @override
  void initState() {
    super.initState();
    _selected = _todayIndex();
    _anchor = _selected ?? 0;
  }

  @override
  void didUpdateWidget(covariant WeeklyChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = _selected;
    if (selected != null && selected >= widget.days.length) _selected = null;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  int? _todayIndex() {
    for (var i = 0; i < widget.days.length; i++) {
      if (widget.days[i].isToday) return i;
    }
    return null;
  }

  void _select(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selected == index) {
        _selected = null;
      } else {
        _selected = index;
        _anchor = index;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    if (days.isEmpty) return SizedBox(height: widget.height);

    final t = context.glass;
    final maxHours = days
        .map((d) => d.hours)
        .fold<double>(1, (a, b) => a > b ? a : b);

    return Semantics(
      container: true,
      label: _summary(days),
      child: ExcludeSemantics(
        child: SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cellWidth = constraints.maxWidth / days.length;
              final index = (_selected ?? _anchor).clamp(0, days.length - 1);
              final fraction = (days[index].hours / maxHours).clamp(0.0, 1.0);
              final barArea = widget.height - _axisHeight;
              final barTop = barArea * (1 - fraction.clamp(0.03, 1.0));
              final left = (cellWidth * (index + 0.5) - _bubbleWidth / 2).clamp(
                0.0,
                constraints.maxWidth - _bubbleWidth,
              );
              final top = (barTop - _bubbleHeight - 6).clamp(0.0, barArea);

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // Scale gridlines.
                  Positioned.fill(
                    bottom: _axisHeight,
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
                      for (var i = 0; i < days.length; i++)
                        Expanded(
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _select(i),
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: i == 0 || i == days.length - 1
                                      ? 1
                                      : 4,
                                ),
                                child: _Bar(
                                  day: days[i],
                                  maxHours: maxHours,
                                  highlighted: _selected == null
                                      ? days[i].isToday
                                      : _selected == i,
                                  animation: CurvedAnimation(
                                    parent: _c,
                                    // Staggered left-to-right so the chart
                                    // grows rather than popping in all at once.
                                    curve: Interval(
                                      (i / days.length) * 0.55,
                                      (i / days.length) * 0.55 + 0.45,
                                      curve: Curves.easeOutCubic,
                                    ),
                                  ),
                                  accent: t.accentPrimary,
                                  accent2: t.accentSecondary,
                                  muted: t.textPrimary,
                                  hairline: t.hairline,
                                  label: context.type.labelSmall!,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  // Value bubble — always laid out, faded out when nothing is
                  // selected, so it can slide between bars instead of blinking.
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    left: left,
                    top: top,
                    width: _bubbleWidth,
                    height: _bubbleHeight,
                    child: IgnorePointer(
                      child: AnimatedSlide(
                        offset: _selected == null
                            ? const Offset(0, 0.4)
                            : Offset.zero,
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        child: AnimatedOpacity(
                          opacity: _selected == null ? 0 : 1,
                          duration: const Duration(milliseconds: 180),
                          child: _Bubble(
                            label: _displayHours(days[index].hours),
                            accent: t.accentPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// The whole chart is one spoken sentence — a screen reader user hears the
  /// week's numbers rather than a run of unlabelled bars.
  String _summary(List<DayBar> days) {
    final parts = [
      for (var i = 0; i < days.length; i++)
        '${_weekdays[i % 7]} ${_spokenHours(days[i].hours)}',
    ];
    return 'Weekly focus, ${parts.join(', ')}';
  }
}

String _spokenHours(double hours) {
  if (hours == hours.roundToDouble()) {
    final n = hours.toInt();
    return '$n ${n == 1 ? 'hour' : 'hours'}';
  }
  return '$hours hours';
}

String _displayHours(double hours) =>
    hours == hours.roundToDouble() ? '${hours.toInt()}h' : '${hours}h';

/// Small glass bubble pinned above the selected bar.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    // Opaque enough to stay legible over gridlines and bars, but tinted from
    // the active theme so it never reads as a foreign Material tooltip.
    final fill = Color.alphaBlend(
      accent.withValues(alpha: 0.16),
      t.canvasGradient.last,
    );

    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: accent.withValues(alpha: 0.72)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.30),
            blurRadius: 16,
            spreadRadius: -3,
          ),
        ],
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: Text(
          label,
          key: ValueKey(label),
          style: context.type.labelMedium?.copyWith(
            color: accent,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.day,
    required this.maxHours,
    required this.highlighted,
    required this.animation,
    required this.accent,
    required this.accent2,
    required this.muted,
    required this.hairline,
    required this.label,
  });

  final DayBar day;
  final double maxHours;

  /// Today when nothing is selected, otherwise the selected day.
  final bool highlighted;

  final Animation<double> animation;
  final Color accent;
  final Color accent2;
  final Color muted;
  final Color hairline;
  final TextStyle label;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final fraction = (day.hours / maxHours).clamp(0.0, 1.0);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final v = (fraction * animation.value).clamp(0.0, 1.0);
              return Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: v.clamp(0.03, 1.0),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: highlighted
                            ? [accent, accent2.withValues(alpha: 0.72)]
                            : [
                                muted.withValues(alpha: 0.20),
                                muted.withValues(alpha: 0.07),
                              ],
                      ),
                      border: Border.all(
                        color: highlighted
                            ? accent.withValues(alpha: 0.75)
                            : hairline,
                      ),
                      boxShadow: highlighted
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
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          style: label.copyWith(
            color: highlighted ? accent : t.textTertiary,
            fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
            fontSize: 11,
          ),
          child: Text(day.label),
        ),
      ],
    );
  }
}
