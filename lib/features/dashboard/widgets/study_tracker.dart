import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/data/seed.dart';
import '../../../core/utils/format.dart';

/// The study tracker: one bar per day, over a week or a month.
///
/// Tapping a bar opens that day's summary — which subjects, how long each —
/// because "3h 20m" on its own does not say what the time was spent on, and
/// that is the question the chart exists to raise. The tapped bar stays
/// highlighted while the summary is open, so the sheet and the bar it
/// describes are never in doubt.
///
/// The heights are scaled by a 0.75 power rather than linearly. On a window
/// with one long day and six short ones, a linear scale flattens the six into
/// an unreadable stub row; the power curve keeps the tall day dominant while
/// leaving the others distinguishable.
class StudyTracker extends StatefulWidget {
  const StudyTracker({
    super.key,
    required this.days,
    required this.onDayTap,
    this.height = 148,
  });

  final List<DayBar> days;

  /// Called with the day the user tapped. The chart does not open the summary
  /// itself — it does not own the sessions.
  final ValueChanged<DayBar> onDayTap;

  final double height;

  @override
  State<StudyTracker> createState() => _StudyTrackerState();
}

class _StudyTrackerState extends State<StudyTracker>
    with SingleTickerProviderStateMixin {
  /// Height reserved for the day labels under the bars.
  static const _axisHeight = 22.0;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.deliberate,
  )..forward();

  int? _selected;

  @override
  void didUpdateWidget(covariant StudyTracker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different window is a different chart, so it draws itself again and
    // the highlight from the old one would point at a day that has moved.
    if (!identical(oldWidget.days, widget.days)) {
      _selected = null;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _select(int index) {
    HapticFeedback.selectionClick();
    setState(() => _selected = index);
    widget.onDayTap(widget.days[index]);
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
          child: Stack(
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
                        // A whisper of a rule. At full outlineVariant the grid
                        // competes with the bars it is meant to sit behind.
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
                              // A month is thirty bars wide on a phone; the
                              // outer ones keep a hairline so the row does not
                              // look clipped, the rest share the space evenly.
                              horizontal: days.length > 10
                                  ? 0.5
                                  : (i == 0 || i == days.length - 1 ? 1 : 4),
                            ),
                            child: _Bar(
                              day: days[i],
                              maxHours: maxHours,
                              highlighted: _selected == i || days[i].isToday,
                              animation: CurvedAnimation(
                                parent: _c,
                                // Staggered left-to-right so the chart grows
                                // rather than popping in all at once.
                                curve: Interval(
                                  (i / days.length) * 0.55,
                                  (i / days.length) * 0.55 + 0.45,
                                  curve: Motion.decelerate,
                                ),
                              ),
                              accent: cs.primary,
                              muted: cs.onSurface,
                              label: Theme.of(context).textTheme.labelSmall!,
                              dense: days.length > 10,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The whole chart is one spoken sentence — a screen reader user hears the
  /// window's numbers rather than a run of unlabelled bars.
  String _summary(List<DayBar> days) {
    final parts = [
      for (final day in days)
        if (day.hours > 0) '${_spokenDay(day)} ${spokenHours(day.hours)}',
    ];
    if (parts.isEmpty) return 'Study tracker. Nothing logged in this window.';
    return 'Study tracker. ${parts.join(', ')}';
  }

  static String _spokenDay(DayBar day) {
    final date = day.date;
    if (date == null) return day.label;
    return '${day.label} ${date.day}';
  }
}

/// One day's bar.
///
/// The treatment is lifted from a chart that got the details right: a faint
/// full-height track behind every bar so an empty day still reads as a slot
/// rather than as a gap in the row, a vertical gradient that darkens as the
/// bar rises, and a short white highlight across the top edge that gives the
/// fill a lit surface instead of a flat sticker.
class _Bar extends StatelessWidget {
  const _Bar({
    required this.day,
    required this.maxHours,
    required this.highlighted,
    required this.animation,
    required this.accent,
    required this.muted,
    required this.label,
    required this.dense,
  });

  final DayBar day;
  final double maxHours;

  /// Today, or the day whose summary is open.
  final bool highlighted;

  final Animation<double> animation;
  final Color accent;
  final Color muted;
  final TextStyle label;

  /// True in the month window, where the bars are too narrow for a label on
  /// every one of them and the corner radius has to come in.
  final bool dense;

  /// The bar's share of the tallest day, curved so short days stay readable.
  double get _visual {
    if (maxHours <= 0 || day.hours <= 0) return 0;
    final linear = (day.hours / maxHours).clamp(0.0, 1.0);
    return math.pow(linear, 0.75).toDouble().clamp(0.06, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(dense ? 6 : 16);
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
        // weight change is invisible, and the pill survives a glance. A day
        // with no label keeps the same height so every bar starts level.
        if (day.label.isEmpty)
          const SizedBox(height: 19)
        else
          AnimatedContainer(
            duration: Motion.base,
            curve: Motion.emphasized,
            padding: EdgeInsets.symmetric(
              horizontal: dense ? 4 : 8,
              vertical: 2,
            ),
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
