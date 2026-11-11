import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/utils/format.dart';

/// How long a chart takes to draw itself in.
const _grow = Duration(milliseconds: 520);

/// Runs [builder] from 0 to 1 once when [animate] is set, and holds it at 1
/// otherwise, so a chart seen before, or seen with reduce motion on, is
/// simply there.
class _GrowIn extends StatelessWidget {
  const _GrowIn({required this.animate, required this.builder});

  final bool animate;
  final Widget Function(BuildContext context, double t) builder;

  @override
  Widget build(BuildContext context) {
    if (!animate || MediaQuery.disableAnimationsOf(context)) {
      return builder(context, 1);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: _grow,
      curve: Motion.decelerate,
      builder: (context, t, _) => builder(context, t),
    );
  }
}

/// The short horizontal mark that stands for last week on every chart in a
/// report: across a day's column, or on a subject's bar.
class LastWeekMark extends StatelessWidget {
  const LastWeekMark({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 14,
    height: 2,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      borderRadius: BorderRadius.circular(1),
    ),
  );
}

/// A week of study as seven columns, Monday first, with last week's time on
/// the same day marked across each one.
///
/// Today is the column in full colour. Tapping a column reads out its day
/// underneath, which is how a chart this small can carry exact numbers
/// without a label on every bar.
class WeekBars extends StatefulWidget {
  const WeekBars({
    super.key,
    required this.days,
    required this.lastDays,
    required this.today,
    required this.surface,
    this.animate = false,
  });

  /// Minutes on each day, Monday first, this week and last.
  final List<int> days;
  final List<int> lastDays;

  /// Today's place in the week, 0 for Monday.
  final int today;

  /// The colour the chart sits on, which separates a mark from a bar.
  final Color surface;
  final bool animate;

  @override
  State<WeekBars> createState() => _WeekBarsState();
}

class _WeekBarsState extends State<WeekBars> {
  late int _picked = widget.today;

  /// The Monday of an arbitrary week: only the weekday names are read.
  static final _monday = DateTime(2024, 1, 1);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context);
    String minutes(int m) => formatMinutes(m, locale: locale);
    final top = math.max(
      30,
      [...widget.days, ...widget.lastDays].fold(0, math.max),
    );
    final quiet = Color.alphaBlend(
      cs.primary.withValues(alpha: 0.45),
      widget.surface,
    );
    final day = _monday.add(Duration(days: _picked));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 92,
          child: _GrowIn(
            animate: widget.animate,
            builder: (context, t) => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: i == _picked,
                      label: context.tr('{0} · {1}', [
                        formatWeekday(
                          _monday.add(Duration(days: i)),
                          locale: locale,
                        ),
                        minutes(widget.days[i]),
                      ]),
                      value: context.tr('Last week {0}', [
                        minutes(widget.lastDays[i]),
                      ]),
                      onTap: () => setState(() => _picked = i),
                      excludeSemantics: true,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(Radii.tile),
                        onTap: () => setState(() => _picked = i),
                        child: Column(
                          children: [
                            Expanded(
                              child: CustomPaint(
                                size: Size.infinite,
                                painter: _ColumnPainter(
                                  value: widget.days[i] / top * t,
                                  mark: widget.lastDays[i] / top,
                                  color: i == _picked ? cs.primary : quiet,
                                  markColor: cs.onSurfaceVariant,
                                  surface: widget.surface,
                                  floor: cs.outlineVariant,
                                ),
                              ),
                            ),
                            const SizedBox(height: Gap.xs),
                            Text(
                              formatWeekdayNarrow(
                                _monday.add(Duration(days: i)),
                                locale: locale,
                              ),
                              style: tt.labelMedium?.copyWith(
                                color: i == widget.today
                                    ? cs.onSurface
                                    : cs.onSurfaceVariant,
                                fontWeight: i == widget.today
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Gap.sm),
        // The picked day in words, and the key to the mark.
        ExcludeSemantics(
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Gap.md,
            runSpacing: Gap.xs,
            children: [
              Text(
                context.tr('{0} · {1}', [
                  formatWeekday(day, locale: locale),
                  minutes(widget.days[_picked]),
                ]),
                style: tt.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LastWeekMark(),
                  const SizedBox(width: Gap.xs + 2),
                  Flexible(
                    child: Text(
                      context.tr('Last week {0}', [
                        minutes(widget.lastDays[_picked]),
                      ]),
                      style: tt.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One day's column: a bar up from the floor, and last week's mark across it.
class _ColumnPainter extends CustomPainter {
  const _ColumnPainter({
    required this.value,
    required this.mark,
    required this.color,
    required this.markColor,
    required this.surface,
    required this.floor,
  });

  /// This week and last, each as a share of the chart's height.
  final double value;
  final double mark;
  final Color color;
  final Color markColor;
  final Color surface;
  final Color floor;

  @override
  void paint(Canvas canvas, Size size) {
    // Room above the tallest bar, so a mark at the very top is not clipped.
    const head = 4.0;
    final height = size.height - head - 1;
    final barWidth = math.min(18.0, size.width - 12);
    final centre = size.width / 2;
    final base = size.height - 1;
    canvas.drawRect(
      Rect.fromLTWH(0, base, size.width, 1),
      Paint()..color = floor,
    );
    if (value > 0) {
      // Even a short session shows as more than a hairline.
      final h = math.max(3.0, height * value.clamp(0.0, 1.0));
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(centre - barWidth / 2, base - h, barWidth, h),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        ),
        Paint()..color = color,
      );
    }
    if (mark > 0) {
      final y = base - height * mark.clamp(0.0, 1.0);
      final markWidth = barWidth + 10;
      // A ring of the surface keeps the mark legible where it crosses a bar.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(centre, y),
            width: markWidth + 4,
            height: 6,
          ),
          const Radius.circular(3),
        ),
        Paint()..color = surface,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(centre, y),
            width: markWidth,
            height: 2,
          ),
          const Radius.circular(1),
        ),
        Paint()..color = markColor,
      );
    }
  }

  @override
  bool shouldRepaint(_ColumnPainter old) =>
      old.value != value ||
      old.mark != mark ||
      old.color != color ||
      old.markColor != markColor ||
      old.surface != surface ||
      old.floor != floor;
}

/// A horizontal bar for one amount out of a shared maximum, with an optional
/// mark for what it was last week.
class AmountBar extends StatelessWidget {
  const AmountBar({
    super.key,
    required this.value,
    required this.color,
    required this.surface,
    this.mark,
    this.animate = false,
  });

  /// The amount and the mark, each as a share of the bar's length.
  final double value;
  final double? mark;
  final Color color;
  final Color surface;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _GrowIn(
      animate: animate,
      builder: (context, t) => SizedBox(
        height: 12,
        child: CustomPaint(
          size: Size.infinite,
          painter: _AmountPainter(
            value: value.clamp(0.0, 1.0) * t,
            mark: mark?.clamp(0.0, 1.0),
            color: color,
            track: cs.surfaceContainerHighest,
            markColor: cs.onSurfaceVariant,
            surface: surface,
            rtl: Directionality.of(context) == TextDirection.rtl,
          ),
        ),
      ),
    );
  }
}

class _AmountPainter extends CustomPainter {
  const _AmountPainter({
    required this.value,
    required this.mark,
    required this.color,
    required this.track,
    required this.markColor,
    required this.surface,
    required this.rtl,
  });

  final double value;
  final double? mark;
  final Color color;
  final Color track;
  final Color markColor;
  final Color surface;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    const thickness = 8.0;
    final top = (size.height - thickness) / 2;
    const radius = Radius.circular(thickness / 2);
    // Bars start at the reading edge, so the picture mirrors with the text.
    Rect span(double from, double to) => rtl
        ? Rect.fromLTRB(
            size.width - to,
            top,
            size.width - from,
            top + thickness,
          )
        : Rect.fromLTRB(from, top, to, top + thickness);
    canvas.drawRRect(
      RRect.fromRectAndRadius(span(0, size.width), radius),
      Paint()..color = track,
    );
    if (value > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          span(0, math.max(thickness, size.width * value)),
          radius,
        ),
        Paint()..color = color,
      );
    }
    final mark = this.mark;
    if (mark != null && mark > 0) {
      final x = (size.width * mark).clamp(2.0, size.width - 2.0);
      final at = rtl ? size.width - x : x;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(at, size.height / 2),
            width: 6,
            height: size.height,
          ),
          const Radius.circular(3),
        ),
        Paint()..color = surface,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(at, size.height / 2),
            width: 2,
            height: size.height,
          ),
          const Radius.circular(1),
        ),
        Paint()..color = markColor,
      );
    }
  }

  @override
  bool shouldRepaint(_AmountPainter old) =>
      old.value != value ||
      old.mark != mark ||
      old.color != color ||
      old.track != track ||
      old.markColor != markColor ||
      old.surface != surface ||
      old.rtl != rtl;
}

/// One bar cut into parts, for how a whole divides: a plan into its blocks,
/// a day into its subjects.
class PartsBar extends StatelessWidget {
  const PartsBar({super.key, required this.parts, this.animate = false});

  /// Each part's size and colour, in order.
  final List<(int, Color)> parts;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final shown = [
      for (final (size, color) in parts)
        if (size > 0) (size, harmonize(color, primary)),
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    return ExcludeSemantics(
      child: _GrowIn(
        animate: animate,
        builder: (context, t) => Align(
          alignment: AlignmentDirectional.centerStart,
          child: FractionallySizedBox(
            widthFactor: math.max(0.05, t),
            child: SizedBox(
              height: 10,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, (size, color)) in shown.indexed) ...[
                    // A gap of the surface between neighbours, not a stroke.
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: size,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadiusDirectional.horizontal(
                            start: Radius.circular(i == 0 ? 5 : 2),
                            end: Radius.circular(i == shown.length - 1 ? 5 : 2),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How far today has come toward its goal: a small ring with the share in
/// the middle.
class GoalRing extends StatelessWidget {
  const GoalRing({super.key, required this.share, this.animate = false});

  /// Done over goal. Past 1 the ring is simply full.
  final double share;
  final bool animate;

  static const double size = 48;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: _GrowIn(
                  animate: animate,
                  builder: (context, t) => CircularProgressIndicator(
                    value: share.clamp(0.0, 1.0) * t,
                    strokeWidth: 5,
                    strokeCap: StrokeCap.round,
                    backgroundColor: cs.surfaceContainerHighest,
                    color: cs.primary,
                  ),
                ),
              ),
            ),
            if (share >= 1)
              Icon(Icons.check_rounded, size: 22, color: cs.primary)
            else
              Text(
                formatPercent(
                  share.clamp(0.0, 1.0),
                  locale: Localizations.localeOf(context),
                ),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
