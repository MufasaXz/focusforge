import 'package:flutter/material.dart';

import '../../../app/theme/color_tokens.dart';
import '../../../app/theme/glass_theme.dart';
import '../../../core/data/seed.dart';

/// Month heatmap — a 7-column calendar where each cell is shaded by focus
/// intensity. Reads left-to-right, oldest week first.
///
/// Intensity is quantised into five steps rather than interpolated: discrete
/// levels are far easier to compare at a glance than a continuous ramp.
///
/// Every cell carries its own date, so a long press reports a real value
/// ("Tuesday 14 Oct - 2.5 hours focused") instead of leaving the reader to
/// guess what a shade of blue means. The popover is styled from the glass
/// tokens rather than the stock Material tooltip so it belongs to the surface
/// it grows out of.
///
/// The entrance is one [AnimationController] for the whole grid. Every cell
/// derives its own opacity/scale from a staggered [Interval] computed from its
/// (row, column) position, so the grid fills left-to-right along each row with
/// the rows cascading down. A [TweenAnimationBuilder] per cell would spin up
/// ~35 controllers that all fire on the same frame — more machinery, and no
/// sweep.
class FocusHeatmap extends StatefulWidget {
  const FocusHeatmap({
    super.key,
    required this.weeks,
    this.weekdayLabels = const ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
  });

  final List<List<HeatCell>> weeks;
  final List<String> weekdayLabels;

  @override
  State<FocusHeatmap> createState() => _FocusHeatmapState();
}

class _FocusHeatmapState extends State<FocusHeatmap>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  /// Whole-grid reveal. The grid itself is done well before this elapses; the
  /// slack is the tail of the legend.
  static const _reveal = Duration(milliseconds: 800);

  /// Stagger geometry, in fractions of [_reveal]. A cell fades and scales over
  /// [_cellSpan]; each row starts [_rowStep] after the one above it and each
  /// column [_colStep] after its neighbour. The row step is deliberately the
  /// larger of the two — that is what makes the motion read as rows cascading
  /// rather than as a single diagonal wipe.
  static const _cellSpan = 0.42;
  static const _rowStep = 0.082;
  static const _colStep = 0.030;

  /// The legend settles after the grid, sweeping left-to-right as the tail of
  /// the same reveal.
  static const _legendSpan = 0.30;
  static const _legendStep = 0.05;
  static const _legendStart = 0.50;

  /// Runs once, when the state is created — deliberately not from [build], so
  /// a rebuild (scroll, provider change) can never restart the sweep.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _reveal,
  )..forward();

  /// Keeps this state — and therefore the finished controller — mounted while
  /// the dashboard's lazy list scrolls the heatmap out of view, so the sweep
  /// does not replay when it comes back.
  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Platform "reduce motion": present the settled grid, no sweep. Setting
    // the value also stops a sweep already in flight.
    if (MediaQuery.disableAnimationsOf(context)) _c.value = 1;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Eased 0..1 reveal for the cell at ([row], [col]).
  double _revealAt(int row, int col) {
    final start = (row * _rowStep + col * _colStep)
        .clamp(0.0, 1.0 - _cellSpan)
        .toDouble();
    return Interval(
      start,
      start + _cellSpan,
      curve: Curves.easeOutCubic,
    ).transform(_c.value);
  }

  /// Eased 0..1 reveal for legend swatch [level].
  double _legendReveal(int level) {
    final start = _legendStart + level * _legendStep;
    return Interval(
      start,
      start + _legendSpan,
      curve: Curves.easeOutCubic,
    ).transform(_c.value);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = context.glass;
    final today = DateTime.now();

    return Semantics(
      container: true,
      label: 'Focus heatmap, ${widget.weeks.length} weeks of focus history',
      child: Column(
        children: [
          Row(
            children: [
              for (final label in widget.weekdayLabels)
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
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Column(
              children: [
                for (var w = 0; w < widget.weeks.length; w++)
                  Row(
                    children: [
                      for (var d = 0; d < widget.weeks[w].length; d++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: _Cell(
                              cell: widget.weeks[w][d],
                              isToday: _sameDay(widget.weeks[w][d].date, today),
                              reveal: _revealAt(w, d),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: Gap.lg),
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Row(
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
                  _Swatch(
                    level: level,
                    reveal: _legendReveal(level),
                    radius: 3,
                    t: t,
                  ),
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
          ),
        ],
      ),
    );
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

const _monthsShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _spokenHours(double hours) {
  if (hours == hours.roundToDouble()) {
    final n = hours.toInt();
    return '$n ${n == 1 ? 'hour' : 'hours'}';
  }
  return '$hours hours';
}

/// "Tuesday 14 Oct - 2.5 hours focused" — the same sentence is used for the
/// tooltip and for the cell's semantics label.
String _spokenValue(HeatCell cell) {
  final date =
      '${cell.weekday} ${cell.date.day} ${_monthsShort[cell.date.month - 1]}';
  if (cell.hours <= 0) return '$date - no focus logged';
  return '$date - ${_spokenHours(cell.hours)} focused';
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
    required this.cell,
    required this.isToday,
    required this.reveal,
  });

  final HeatCell cell;
  final bool isToday;

  /// Eased 0..1 progress of this cell's slice of the grid reveal.
  final double reveal;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final label = _spokenValue(cell);

    return Semantics(
      label: label,
      child: Tooltip(
        message: label,
        // The custom Semantics node above is the single source of truth for
        // screen readers; the tooltip is the visual channel only.
        excludeFromSemantics: true,
        triggerMode: TooltipTriggerMode.longPress,
        waitDuration: const Duration(milliseconds: 300),
        showDuration: const Duration(seconds: 2),
        preferBelow: false,
        verticalOffset: 8,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        textStyle: context.type.labelSmall?.copyWith(
          color: t.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 11.5,
        ),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            t.accentPrimary.withValues(alpha: 0.14),
            t.canvasGradient.last,
          ),
          borderRadius: BorderRadius.circular(Radii.tile),
          border: Border.all(color: t.accentPrimary.withValues(alpha: 0.55)),
          boxShadow: [BoxShadow(color: t.glassL1Shadow, blurRadius: 18)],
        ),
        child: AspectRatio(
          aspectRatio: 1,
          child: Stack(
            children: [
              Positioned.fill(
                child: _Swatch(
                  level: _levelFor(cell.intensity),
                  reveal: reveal,
                  radius: 6,
                  t: t,
                ),
              ),
              if (isToday)
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
        ),
      ),
    );
  }
}

/// Fades + scales in as [reveal] goes 0 → 1, then holds at the final state.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.level,
    required this.reveal,
    required this.radius,
    required this.t,
  });

  final int level;

  /// Eased 0..1 progress handed down from the grid's single controller.
  final double reveal;
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
    return Opacity(
      opacity: reveal,
      child: Transform.scale(
        scale: 0.72 + 0.28 * reveal,
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
      ),
    );
  }
}
