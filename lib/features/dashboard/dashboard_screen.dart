import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/shell/app_shell.dart';
import '../../app/theme/app_theme.dart';
import '../../core/data/seed.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/coach_providers.dart';
import '../../core/providers/study_providers.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/progress_ring.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/stagger.dart';
import '../onboarding/coach_marks.dart';
import 'widgets/focus_heatmap.dart';
import 'widgets/day_summary_sheet.dart';
import 'widgets/screen_time_card.dart';
import 'widgets/study_tracker.dart';
import 'widgets/subject_breakdown.dart';

/// Tab 1 — the all-in-one analytics dashboard.
///
/// No app bar: the screen opens on a greeting, and every section sits in a
/// tonal card on the scaffold surface. Everything below the greeting is read
/// from the Riverpod stores, so a session finished on the Focus tab is
/// reflected the moment this screen rebuilds.
///
/// Pull-to-refresh re-reads those stores behind a short skeleton frame: the
/// read itself is synchronous, so without the hold the refresh would resolve
/// in a single frame and read as a flicker rather than as loading.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _refreshing = false;

  /// Which window the tracker is showing. Local state rather than a provider:
  /// it is a way of looking at the log, not a fact about the user, and it
  /// should start on the week every time the app opens.
  StudyRange _range = StudyRange.week;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (!mounted) return;
    // No network yet — a refresh is re-reading the local stores. These reads
    // are the no-op that keeps the call honest once a repository lands here.
    ref.read(sessionsProvider);
    ref.read(subjectsProvider);
    ref.read(statsProvider);
    setState(() => _refreshing = false);
  }

  /// The Focus tab is branch 2 of the shell. Falling back to a route push
  /// keeps the CTA working if the dashboard is ever shown outside the shell.
  void _startFocusing() {
    final shell = StatefulNavigationShell.maybeOf(context);
    if (shell != null) {
      shell.goBranch(2);
      return;
    }
    context.go(AppRoutes.paths[AppRoutes.focus]!);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();

    final user = ref.watch(userProvider);
    final stats = ref.watch(statsProvider);
    final minutesToday = ref.watch(focusMinutesTodayProvider);
    final goalMinutes = ref.watch(dailyGoalProvider);
    final progress = ref.watch(goalProgressProvider);
    final sessions = ref.watch(sessionsProvider);
    final subjects = ref.watch(subjectsProvider);
    // Derived from the session log, not read from the stats aggregate: a
    // streak is a fact about dates and the aggregate carries none.
    final streak = ref.watch(currentStreakProvider);

    final sessionsToday = sessions
        .where((s) => s.completed && _sameDay(s.startedAt, now))
        .length;

    // Every number on this screen is derived from the session log, so the
    // chart, the heatmap and the ring above them can never disagree.
    final days = ref.watch(rangeBarsProvider(_range));
    final total = ref.watch(rangeTotalHoursProvider(_range));
    final average = ref.watch(rangeAverageHoursProvider(_range));
    final heatmapWeeks = ref.watch(heatmapWeeksProvider);

    // A tablet has room for two columns; a phone does not, and two narrow
    // columns are worse than one. Measured rather than taken from the window,
    // because the rail already took its width off the top.
    final wide = MediaQuery.sizeOf(context).width >= 900;

    // The first-run tips, built from what is actually on screen. A tip whose
    // subject is not rendered — the ring before the first session, the streak
    // chip at zero — is left out rather than pointed at nothing.
    final targets = ref.watch(coachTargetsProvider);
    final spots = <CoachSpot>[
      if (sessions.isEmpty)
        CoachSpot(
          target: targets.emptyCta,
          icon: Icons.play_arrow_rounded,
          title: 'Start your first session',
          body:
              'Your study log, charts and heatmap all grow from finished '
              'sessions. This button starts one.',
        )
      else
        CoachSpot(
          target: targets.ring,
          icon: Icons.donut_large_rounded,
          title: 'Your daily progress',
          body:
              'This ring fills as you focus. Finish a session and it starts '
              'moving.',
        ),
      if (streak > 0)
        CoachSpot(
          target: targets.streak,
          icon: Icons.local_fire_department_rounded,
          title: 'Build your streak',
          body: 'Study every day and the flame keeps growing.',
        ),
      CoachSpot(
        target: targets.focusTab,
        icon: Icons.timer_rounded,
        title: 'Your timer lives here',
        body:
            'The Focus tab starts a Pomodoro and runs the shield while it '
            'counts down.',
      ),
    ];

    final greeting = _Greeting(
      name: user.firstName,
      streak: streak,
      now: now,
      streakKey: targets.streak,
    );

    // The two columns, in reading order: what today looks like, then what the
    // log says. Only used when there is width for them.
    final left = <Widget>[
      if (sessions.isEmpty)
        _NoSessions(onStart: _startFocusing, ctaKey: targets.emptyCta)
      else ...[
        _DailyOverview(
          progress: progress,
          minutesToday: minutesToday,
          goalMinutes: goalMinutes,
          sessionsToday: sessionsToday,
          totalHours: stats.totalFocusHours,
          level: stats.level,
          ringKey: targets.ring,
        ),
        const SizedBox(height: Gap.xl),
        SectionHeader(
          title: _range == StudyRange.week ? 'This week' : 'This month',
          icon: Icons.bar_chart_rounded,
        ),
        const SizedBox(height: Gap.md),
        _TrackerPanel(
          range: _range,
          onRangeChanged: (r) => setState(() => _range = r),
          total: total,
          average: average,
          days: days,
          onDayTap: (day) => _openDay(day),
        ),
        const SizedBox(height: Gap.xl),
        const SectionHeader(
          title: 'Focus heatmap',
          icon: Icons.calendar_month_rounded,
        ),
        const SizedBox(height: Gap.md),
        Card.filled(
          child: Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: FocusHeatmap(weeks: heatmapWeeks),
          ),
        ),
      ],
    ];

    final right = <Widget>[
      const SectionHeader(
        title: 'Screen time today',
        icon: Icons.hourglass_bottom_rounded,
      ),
      const SizedBox(height: Gap.md),
      const Card.filled(
        child: Padding(
          padding: EdgeInsets.all(Gap.lg),
          child: ScreenTimeCard(),
        ),
      ),
      if (sessions.isNotEmpty) ...[
        const SizedBox(height: Gap.xl),
        const SectionHeader(
          title: 'Subject breakdown',
          icon: Icons.donut_large_rounded,
        ),
        const SizedBox(height: Gap.md),
        Card.filled(
          child: Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: SubjectBreakdown(subjects: subjects),
          ),
        ),
      ],
    ];

    return CoachMarks(
      spots: spots,
      child: RefreshIndicator(
        onRefresh: _refresh,
        color: cs.primary,
        backgroundColor: cs.surface,
        child: _refreshing
            ? ListView(
                padding: _padding(context),
                children: const [
                  SkeletonCard(height: 330, radius: Radii.hero),
                  SizedBox(height: Gap.xl),
                  SkeletonCard(height: 230),
                  SizedBox(height: Gap.xl),
                  SkeletonCard(height: 310),
                  SizedBox(height: Gap.xl),
                  SkeletonList(count: 3, itemHeight: 72),
                ],
              )
            : wide
            ? SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: _padding(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Stagger(index: 0, child: greeting),
                    const SizedBox(height: Gap.xl),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: _staggered(left, from: 1),
                          ),
                        ),
                        const SizedBox(width: Gap.xl),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: _staggered(right, from: 1 + left.length),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: _padding(context),
                children: [
                  Stagger(index: 0, child: greeting),
                  const SizedBox(height: Gap.xl),
                  ..._staggered([...left, ...right]),
                ],
              ),
      ),
    );
  }

  /// The screen's own padding, so both scroll shapes agree.
  EdgeInsets _padding(BuildContext context) => EdgeInsets.fromLTRB(
    Gap.lg + 4,
    MediaQuery.paddingOf(context).top + Gap.lg,
    Gap.lg + 4,
    kNavBarClearance,
  );

  List<Widget> _staggered(List<Widget> children, {int from = 0}) => [
    for (var i = 0; i < children.length; i++)
      Stagger(index: from + i, child: children[i]),
  ];

  /// Opens the tapped day's summary.
  void _openDay(DayBar day) {
    final date = day.date;
    if (date == null) return;
    showDaySummarySheet(context, date);
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _spokenMinutes(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  final parts = <String>[
    if (h > 0) '$h ${h == 1 ? 'hour' : 'hours'}',
    if (m > 0) '$m ${m == 1 ? 'minute' : 'minutes'}',
  ];
  return parts.isEmpty ? 'no focus logged' : parts.join(' ');
}
/// Greeting plus the streak pill — the one number worth surfacing in chrome.
class _Greeting extends StatelessWidget {
  const _Greeting({
    required this.name,
    required this.streak,
    required this.now,
    this.streakKey,
  });

  final String name;
  final int streak;
  final DateTime now;

  /// Anchor for the first-run tip about the streak. Null when the tips are
  /// not running.
  final Key? streakKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                // A nameless user gets "Good morning", not "Good morning, " —
                // the comma only belongs there when something follows it.
                [greetingFor(now), if (name.isNotEmpty) name].join(', '),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 3),
              Text(
                formatDate(now),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        if (streak > 0) ...[
          const SizedBox(width: Gap.md),
          Chip(
            key: streakKey,
            avatar: Icon(
              Icons.local_fire_department_rounded,
              size: 15,
              color: cs.tertiary,
            ),
            label: Text(
              '$streak',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            labelPadding: EdgeInsets.zero,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ],
    );
  }
}

/// Ring, goal copy and the three stat chips.
class _DailyOverview extends StatelessWidget {
  const _DailyOverview({
    required this.progress,
    required this.minutesToday,
    required this.goalMinutes,
    required this.sessionsToday,
    required this.totalHours,
    required this.level,
    this.ringKey,
  });

  final double progress;
  final int minutesToday;
  final int goalMinutes;
  final int sessionsToday;
  final double totalHours;
  final int level;

  /// Anchor for the first-run tip about the daily ring.
  final Key? ringKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card.filled(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.hero),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xl, Gap.xl, Gap.lg),
        child: Column(
          children: [
            ProgressRing(
              key: ringKey,
              value: progress,
              size: 188,
              stroke: 11,
              ticks: 24,
              semanticLabel:
                  'Daily focus, ${_spokenMinutes(minutesToday)} of '
                  '${_spokenMinutes(goalMinutes)}, '
                  '${(progress * 100).round()} percent of goal',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatMinutes(minutesToday),
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontSize: 36,
                      letterSpacing: -1.4,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'of ${formatMinutes(goalMinutes)} goal',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Gap.xl),
            LayoutBuilder(
              builder: (context, constraints) {
                final chips = <Widget>[
                  _StatChip(
                    icon: Icons.task_alt_rounded,
                    value: '$sessionsToday',
                    label: 'Sessions',
                  ),
                  _StatChip(
                    icon: Icons.timelapse_rounded,
                    // `formatHoursShort`, not `.round()`: a first session of 25
                    // minutes is 0.4h, and rounding it to "0h" reads as though
                    // nothing was logged.
                    value: formatHoursShort(totalHours),
                    label: 'All time',
                  ),
                  _StatChip(
                    icon: Icons.military_tech_rounded,
                    value: '$level',
                    label: 'Level',
                  ),
                ];

                // Three equal columns need ~340dp to keep the labels on one
                // line; below that the chips keep a third of the row as a
                // minimum and flow onto a second line instead of clipping.
                if (constraints.maxWidth < 340) {
                  final minWidth = (constraints.maxWidth - Gap.sm * 2) / 3;
                  return Wrap(
                    spacing: Gap.sm,
                    runSpacing: Gap.sm,
                    children: [
                      for (final chip in chips)
                        ConstrainedBox(
                          constraints: BoxConstraints(minWidth: minWidth),
                          child: chip,
                        ),
                    ],
                  );
                }
                return Row(
                  children: [
                    for (var i = 0; i < chips.length; i++) ...[
                      if (i > 0) const SizedBox(width: Gap.sm),
                      Expanded(child: chips[i]),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The weekly panel: headline total, average pill and the tappable chart.
class _TrackerPanel extends StatelessWidget {
  const _TrackerPanel({
    required this.range,
    required this.onRangeChanged,
    required this.total,
    required this.average,
    required this.days,
    required this.onDayTap,
  });

  final StudyRange range;
  final ValueChanged<StudyRange> onRangeChanged;
  final double total;
  final double average;
  final List<DayBar> days;
  final ValueChanged<DayBar> onDayTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatHoursShort(total),
                        style: tt.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        total <= 0
                            ? 'Nothing logged yet'
                            : '${formatHoursShort(average)} on an average day',
                        style: tt.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Gap.md),
                SegmentedButton<StudyRange>(
                  segments: [
                    for (final r in StudyRange.values)
                      ButtonSegment(value: r, label: Text(r.label)),
                  ],
                  selected: {range},
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: WidgetStatePropertyAll(tt.labelSmall),
                  ),
                  onSelectionChanged: (selection) =>
                      onRangeChanged(selection.first),
                ),
              ],
            ),
            const SizedBox(height: Gap.lg),
            StudyTracker(days: days, onDayTap: onDayTap),
          ],
        ),
      ),
    );
  }
}

/// Designed first-run state — shown whenever there is nothing to chart.
class _NoSessions extends StatelessWidget {
  const _NoSessions({required this.onStart, this.ctaKey});

  final VoidCallback onStart;

  /// Anchor for the first-run tip about starting a session.
  final Key? ctaKey;

  @override
  Widget build(BuildContext context) {
    return Card.filled(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.hero),
      ),
      child: EmptyState(
        icon: Icons.timer_outlined,
        title: 'No sessions yet',
        subtitle:
            'Finish your first focus block and this page fills in — '
            'the daily ring, the study tracker and the heatmap.',
        action: FilledButton.icon(
          key: ctaKey,
          onPressed: onStart,
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: const Text('Start focusing'),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: Gap.md,
          horizontal: Gap.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: cs.primary),
            const SizedBox(height: 7),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: cs.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

