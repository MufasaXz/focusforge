import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/data/seed.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/pressable.dart';

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
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.deliberate,
  )..forward();

  int? _selected;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _c.value = 1;
  }

  @override
  void didUpdateWidget(covariant StudyTracker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different window is a different chart, so it draws itself again and
    // the highlight from the old one would point at a day that has moved.
    if (!identical(oldWidget.days, widget.days)) {
      _selected = null;
      if (MediaQuery.disableAnimationsOf(context)) {
        _c.value = 1;
      } else {
        _c.forward(from: 0);
      }
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
      child: SizedBox(
        height: widget.height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < days.length; i++)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: _selected == i,
                  label:
                      '${days[i].date == null ? days[i].label : formatDate(days[i].date!)}. '
                      '${spokenHours(days[i].hours)} focused. View day summary',
                  excludeSemantics: true,
                  onTap: () => _select(i),
                  child: Pressable(
                    scale: 1,
                    onTap: () => _select(i),
                    child: _Bar(
                      day: days[i],
                      maxHours: maxHours,
                      highlighted: _selected == i || days[i].isToday,
                      animation: CurvedAnimation(
                        parent: _c,
                        // Staggered left-to-right so the chart grows rather
                        // than popping in all at once.
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
          ],
        ),
      ),
    );
  }

  /// A window overview before the individually operable day summaries.
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
/// A slot and a fill: a faint full-height track so an empty day still reads as
/// a day rather than as a gap in the row, and inside it a narrower capsule
/// carrying a vertical gradient — deep at the foot, bright at the head. The
/// inset is what makes the fill read as a measure rather than as a painted
/// bar, and it is the one detail the whole chart's character hangs on.
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(dense ? 4 : Radii.pill);

    // The gradient runs between two of the scheme's own hues rather than
    // between a hue and its own shadow, so the fill carries the app's colour
    // in both themes instead of going muddy in one of them.
    final head = accent.withValues(alpha: highlighted ? 1 : 0.82);
    final foot = Color.lerp(
      accent,
      cs.tertiary,
      0.6,
    )!.withValues(alpha: highlighted ? 1 : 0.82);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          // The bar is given room inside its slot: a slot filled edge to edge
          // turns seven days into one band, and the inset the fill carries
          // only reads when the slot is wider than it. The label below keeps
          // the whole slot, so "Wed" is not squeezed into the bar's width. A
          // month is thirty slots on the same width and cannot afford the gap.
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: dense ? 0.5 : 9),
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                final v = (_visual * animation.value).clamp(0.0, 1.0);
                return Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    // The track. Fixed height, so the row never looks ragged
                    // while the bars are still growing.
                    //
                    // Weighted per theme: a wash of the on-colour is a slot on
                    // white and a smudge on black, and the same 5% that reads as
                    // one disappears as the other.
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          color: muted.withValues(alpha: dark ? 0.12 : 0.05),
                        ),
                      ),
                    ),
                    if (v > 0)
                      FractionallySizedBox(
                        heightFactor: v.clamp(0.05, 1.0),
                        child: AnimatedContainer(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : Motion.base,
                          curve: Motion.emphasized,
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(
                            horizontal: dense ? 1 : 3,
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: radius,
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [foot, head],
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
        const SizedBox(height: Gap.sm),
        // Today is a filled pill rather than a bolder word: at this size a
        // weight change is invisible, and the pill survives a glance. A day
        // with no label keeps the same height so every bar starts level.
        if (day.label.isEmpty)
          const SizedBox(height: 19)
        else
          // Free of the slot's width: a three-letter weekday is wider than a
          // month's bar, and a label that wrapped to two lines would take the
          // whole row's baseline with it.
          UnconstrainedBox(
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : Motion.base,
              curve: Motion.emphasized,
              padding: EdgeInsets.symmetric(
                horizontal: dense ? 4 : 7,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.pill),
                color: highlighted ? accent : Colors.transparent,
              ),
              child: AnimatedDefaultTextStyle(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : Motion.base,
                curve: Motion.emphasized,
                style: label.copyWith(
                  color: highlighted ? cs.onPrimary : cs.onSurfaceVariant,
                  fontWeight: highlighted ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 11,
                ),
                child: Text(day.label, maxLines: 1, softWrap: false),
              ),
            ),
          ),
      ],
    );
  }
}
