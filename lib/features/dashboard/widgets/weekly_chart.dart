import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/data/seed.dart';
import '../../../core/utils/format.dart';

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

    final cs = Theme.of(context).colorScheme;
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
                          Container(
                            height: 1,
                            // A whisper of a rule. At full outlineVariant the
                            // grid competes with the bars it is meant to sit
                            // behind.
                            color: cs.outlineVariant.withValues(alpha: 0.3),
                          ),
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
                                  accent: cs.primary,
                                  muted: cs.onSurface,
                                  label: Theme.of(context).textTheme.labelSmall!,
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
                            label: formatHoursShort(days[index].hours),
                            accent: cs.primary,
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
        '${_weekdays[i % 7]} ${spokenHours(days[i].hours)}',
    ];
    return 'Weekly focus, ${parts.join(', ')}';
  }
}

/// Small tonal bubble pinned above the selected bar.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Opaque enough to stay legible over gridlines and bars, but tinted from
    // the active theme so it never reads as a foreign Material tooltip.
    final fill = Color.alphaBlend(
      accent.withValues(alpha: 0.16),
      cs.surface,
    );

    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: accent.withValues(alpha: 0.72)),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: Text(
          label,
          key: ValueKey(label),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: accent,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

/// One day's bar.
///
/// The treatment is lifted from a chart that got the details right: a faint
/// full-height track behind every bar so an empty day still reads as a slot
/// rather than as a gap in the row, a vertical gradient that darkens as the
/// bar rises, and a short white highlight across the top edge that gives the
/// fill a lit surface instead of a flat sticker.
///
/// The heights are scaled by a 0.75 power rather than linearly. On a week with
/// one long day and six short ones, a linear scale flattens the six into an
/// unreadable stub row; the power curve keeps the tall day dominant while
/// leaving the others distinguishable.
class _Bar extends StatelessWidget {
  const _Bar({
    required this.day,
    required this.maxHours,
    required this.highlighted,
    required this.animation,
    required this.accent,
    required this.muted,
    required this.label,
  });

  final DayBar day;
  final double maxHours;

  /// Today when nothing is selected, otherwise the selected day.
  final bool highlighted;

  final Animation<double> animation;
  final Color accent;
  final Color muted;
  final TextStyle label;

  /// The bar's share of the tallest day, curved so short days stay readable.
  double get _visual {
    if (maxHours <= 0 || day.hours <= 0) return 0;
    final linear = (day.hours / maxHours).clamp(0.0, 1.0);
    return math.pow(linear, 0.75).toDouble().clamp(0.06, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(16);
    final fill = highlighted ? accent : muted.withValues(alpha: 0.30);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final v = (_visual * animation.value).clamp(0.0, 1.0);
              return Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  // The track. Fixed height, so the row never looks ragged
                  // while the bars are still growing.
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        color: muted.withValues(alpha: 0.04),
                      ),
                    ),
                  ),
                  if (v > 0)
                    FractionallySizedBox(
                      heightFactor: v.clamp(0.04, 1.0),
                      child: AnimatedContainer(
                        duration: Motion.base,
                        curve: Motion.emphasized,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              fill,
                              Color.alphaBlend(
                                fill.withValues(alpha: 0.62),
                                cs.surface,
                              ),
                            ],
                          ),
                        ),
                        // The lit top edge.
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: FractionallySizedBox(
                            heightFactor: 0.06,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.vertical(
                                  top: radius.topLeft,
                                ),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.white.withValues(alpha: 0.30),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
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
        const SizedBox(height: Gap.sm),
        // Today is a filled pill rather than a bolder word: at this size a
        // weight change is invisible, and the pill survives a glance.
        AnimatedContainer(
          duration: Motion.base,
          curve: Motion.emphasized,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.pill),
            color: highlighted ? accent : Colors.transparent,
          ),
          child: AnimatedDefaultTextStyle(
            duration: Motion.base,
            curve: Motion.emphasized,
            style: label.copyWith(
              color: highlighted ? cs.onPrimary : cs.onSurfaceVariant,
              fontWeight: highlighted ? FontWeight.w800 : FontWeight.w600,
              fontSize: 11,
            ),
            child: Text(day.label),
          ),
        ),
      ],
    );
  }
}
