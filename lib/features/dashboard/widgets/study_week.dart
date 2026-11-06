import '../../../core/localization/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/providers/goal_planner_providers.dart';
import '../../../core/providers/study_providers.dart';
import '../../../core/utils/format.dart';
import '../usage_stats.dart';
import 'day_summary_sheet.dart';

/// How many subjects the week names: the legend has three columns, and the
/// bars give every other subject one shared, neutral segment.
const _named = 3;

/// One subject's share of the week.
@immutable
class WeekSubject {
  const WeekSubject({
    required this.id,
    required this.minutes,
    this.name,
    this.color,
  });

  final String id;
  final int minutes;

  /// The catalogue name, or a deleted subject's recorded one. Null for time
  /// that was never tagged or whose subject left no name behind.
  final String? name;

  /// The subject's own colour, or null when it is no longer in the catalogue.
  final Color? color;
}

/// This week's completed focus, Monday first, by day and by subject.
@immutable
class WeekStudy {
  const WeekStudy({
    required this.monday,
    required this.days,
    required this.subjects,
    this.recentPeak = 0,
  });

  final DateTime monday;

  /// Minutes per subject id for each day, Monday to Sunday.
  final List<Map<String, int>> days;

  /// Every subject studied this week, busiest first.
  final List<WeekSubject> subjects;

  /// The busiest of the [recentDays] days before today, in minutes, even
  /// when they fall in last week. Sizes the chart to how much the user
  /// usually studies, so a fresh Monday is not drawn on a 2-hour scale.
  final int recentPeak;

  static const recentDays = 4;

  int get total => subjects.fold(0, (sum, s) => sum + s.minutes);
}

/// The week the Home chart draws, derived from the session log.
///
/// Monday-aligned and keyed on the calendar date, matching the subject rings
/// and the leaderboard, so "this week" is the same span everywhere. The day of
/// a block is its weekday rather than its distance from Monday, so a week with
/// a 23-hour day in it cannot slide a block onto the wrong bar.
final weekStudyProvider = Provider<WeekStudy>((ref) {
  final today = ref.watch(focusCalendarDateProvider);
  final monday = DateTime(
    today.year,
    today.month,
    today.day - (today.weekday - 1),
  );
  final next = DateTime(monday.year, monday.month, monday.day + 7);
  final catalogue = {for (final s in ref.watch(subjectsProvider)) s.id: s};

  final days = List.generate(7, (_) => <String, int>{});
  final totals = <String, int>{};
  final labels = <String, String>{};
  final recentStart = DateTime(
    today.year,
    today.month,
    today.day - WeekStudy.recentDays,
  );
  final recent = <DateTime, int>{};
  for (final session in ref.watch(sessionsProvider)) {
    final at = session.startedAt;
    if (!session.completed || session.minutes <= 0) continue;
    if (!at.isBefore(recentStart) && at.isBefore(today)) {
      final date = DateTime(at.year, at.month, at.day);
      recent[date] = (recent[date] ?? 0) + session.minutes;
    }
    if (at.isBefore(monday) || !at.isBefore(next)) continue;
    final id = session.subjectId;
    final day = days[at.weekday - DateTime.monday];
    day[id] = (day[id] ?? 0) + session.minutes;
    totals[id] = (totals[id] ?? 0) + session.minutes;
    if (session.label.isNotEmpty) labels[id] ??= session.label;
  }

  final subjects = [
    for (final MapEntry(key: id, value: minutes) in totals.entries)
      WeekSubject(
        id: id,
        minutes: minutes,
        name: catalogue[id]?.name ?? labels[id],
        color: catalogue[id]?.color,
      ),
  ]..sort((a, b) => b.minutes.compareTo(a.minutes));
  return WeekStudy(
    monday: monday,
    days: days,
    subjects: subjects,
    recentPeak: recent.values.fold(0, (a, b) => a > b ? a : b),
  );
});

/// The top of the week chart's scale, in whole hours, for a busiest day of
/// [busiestMinutes]: rounded up to an even number, two at least, so the
/// middle line always lands on a whole hour (0h · 2h · 4h, 0h · 3h · 6h).
int weekScaleHours(int busiestMinutes) {
  final hours = ((busiestMinutes / 60).ceil() + 1) ~/ 2 * 2;
  return hours < 2 ? 2 : hours;
}

/// This week's focus on Home: the total, the days by subject, and the three
/// subjects that took the most of it.
class StudyWeekOverview extends ConsumerWidget {
  const StudyWeekOverview({super.key, this.screenTime = false});

  /// Whether the phone shares app usage, so today's screen time can sit
  /// under the week as a way into the full stats.
  final bool screenTime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final week = ref.watch(weekStudyProvider);
    final today = ref.watch(focusCalendarDateProvider);
    final named = week.subjects.take(_named).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatMinutes(week.total),
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -.5,
          ),
        ),
        Text(
          context.tr("focused this week"),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Gap.lg),
        StudyWeekChart(
          week: week,
          named: named,
          today: today.weekday - DateTime.monday,
          onDayTap: (i) => showDaySummarySheet(
            context,
            DateTime(week.monday.year, week.monday.month, week.monday.day + i),
          ),
        ),
        const SizedBox(height: Gap.md),
        if (named.isEmpty)
          Text(
            context.tr("No focus logged"),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          )
        else
          SubjectLegend(subjects: named),
        if (screenTime) ...[
          const SizedBox(height: Gap.lg),
          const ScreenTimeLink(),
        ],
      ],
    );
  }
}

/// The colour a week subject is drawn in.
///
/// Its own colour while it is in the catalogue. Time with no subject, or
/// whose subject has been deleted, shares one neutral, so it can never be
/// mistaken for a real subject's hue.
Color weekSubjectColor(WeekSubject subject, ColorScheme cs) =>
    subject.color ?? _neutral(cs);

Color _neutral(ColorScheme cs) => cs.onSurfaceVariant.withValues(alpha: .38);

/// A week subject's name for display.
String weekSubjectName(BuildContext context, WeekSubject subject) =>
    subject.name ??
    (subject.id.isEmpty ? context.tr("Not tagged") : context.tr("Unassigned"));

/// Seven bars, Monday to Sunday, each stacked by subject.
///
/// The named subjects keep their own colours, busiest at the base; every
/// other subject shares one neutral segment on top. Segments are separated by
/// a 2px gap of the surface behind them, so two neighbouring colours never
/// read as one.
class StudyWeekChart extends StatelessWidget {
  const StudyWeekChart({
    super.key,
    required this.week,
    required this.named,
    this.today,
    this.onDayTap,
    this.height = 110,
  });

  final WeekStudy week;
  final List<WeekSubject> named;

  /// Monday-based index of today, drawn with a strong label.
  final int? today;
  final ValueChanged<int>? onDayTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ids = {for (final s in named) s.id};
    final stacks = [
      for (final day in week.days)
        [
          for (final subject in named)
            (weekSubjectColor(subject, cs), day[subject.id] ?? 0),
          (
            _neutral(cs),
            day.entries
                .where((e) => !ids.contains(e.key))
                .fold(0, (sum, e) => sum + e.value),
          ),
        ],
    ];
    final totals = [
      for (final stack in stacks) stack.fold(0, (sum, part) => sum + part.$2),
    ];
    final busiest = totals.fold(week.recentPeak, (a, b) => a > b ? a : b);
    final top = weekScaleHours(busiest) * 60;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    // The phone's own weekday letters, Monday first.
    final narrow = MaterialLocalizations.of(context).narrowWeekdays;
    final letters = [for (var i = 0; i < 7; i++) narrow[(i + 1) % 7]];

    // Sized by its contents rather than a fixed strip for the weekday
    // letters, so large text grows the chart instead of overflowing it.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The axis is a scale, not content: every bar's value is also
        // spoken. Its labels stop growing at 1.5x and shrink to fit, so very
        // large text cannot push three of them past the chart.
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.5,
          child: SizedBox(
            width: 30,
            height: height,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final hours in [top / 60, top / 120, 0.0])
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(formatHoursShort(hours), style: labelStyle),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              for (final fraction in const [0.0, 0.5, 1.0])
                Positioned(
                  left: 0,
                  right: 0,
                  top: height * fraction,
                  child: Divider(
                    height: 1,
                    color: cs.outlineVariant.withValues(alpha: .5),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: Semantics(
                        button: onDayTap != null,
                        selected: today == i,
                        label: [
                          letters[i],
                          formatMinutes(totals[i]),
                        ].join(', '),
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onDayTap == null ? null : () => onDayTap!(i),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                height: height,
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: _StackedBar(
                                    parts: stacks[i],
                                    top: top,
                                    height: height,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                letters[i],
                                style: labelStyle?.copyWith(
                                  color: today == i ? cs.onSurface : null,
                                  fontWeight: today == i
                                      ? FontWeight.w700
                                      : null,
                                ),
                              ),
                            ],
                          ),
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

class _StackedBar extends StatelessWidget {
  const _StackedBar({
    required this.parts,
    required this.top,
    required this.height,
  });

  /// Base first: the busiest named subject sits on the axis.
  final List<(Color, int)> parts;
  final int top;
  final double height;

  static const _width = 22.0;
  static const _gap = 2.0;

  @override
  Widget build(BuildContext context) {
    final drawn = [
      for (final part in parts)
        if (part.$2 > 0) part,
    ];
    if (drawn.isEmpty) return const SizedBox(width: _width);
    final reduce = MediaQuery.disableAnimationsOf(context);
    // The bar grows from the axis the first time it is drawn, so the week
    // reads as something that was built rather than something that appeared.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reduce ? Duration.zero : Motion.deliberate,
      curve: Motion.emphasized,
      builder: (context, grow, _) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        child: SizedBox(
          width: _width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drawn top-down, so the base segment comes last.
              for (final (i, (color, minutes)) in drawn.reversed.indexed) ...[
                if (i > 0) const SizedBox(height: _gap),
                Container(
                  height: (height * grow * minutes / top).clamp(1.5, height),
                  color: color,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The week's leading subjects, side by side: each with its colour, its time
/// and its name, in the columns the screen-time split used.
class SubjectLegend extends StatelessWidget {
  const SubjectLegend({super.key, required this.subjects});

  final List<WeekSubject> subjects;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Always three columns, so one or two subjects keep the same widths
        // and alignment as a full week.
        for (var i = 0; i < _named; i++)
          Expanded(
            child: i >= subjects.length
                ? const SizedBox.shrink()
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: weekSubjectColor(subjects[i], cs),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              formatMinutes(subjects[i].minutes),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              weekSubjectName(context, subjects[i]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
      ],
    );
  }
}
