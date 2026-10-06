import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/shell/app_shell.dart';
import '../../app/theme/app_theme.dart';
import '../../core/data/seed.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/shield_providers.dart';
import '../../core/providers/study_providers.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/progress_ring.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/stagger.dart';
import '../onboarding/coach_marks.dart';
import 'widgets/app_distribution.dart';
import 'widgets/focus_heatmap.dart';
import 'widgets/subject_breakdown.dart';
import 'widgets/weekly_chart.dart';

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
    final activeShields = ref.watch(activeShieldCountProvider);

    final sessionsToday = sessions
        .where((s) => s.completed && _sameDay(s.startedAt, now))
        .length;

    // Every number on this screen is derived from the session log, so the
    // chart, the heatmap and the ring above them can never disagree.
    final week = ref.watch(weeklyBarsProvider);
    final weekTotal = ref.watch(weekTotalHoursProvider);
    final weekAverage = ref.watch(weekAverageHoursProvider);
    final heatmapWeeks = ref.watch(heatmapWeeksProvider);

    return CoachMarks(
      child: RefreshIndicator(
        onRefresh: _refresh,
        color: cs.primary,
        backgroundColor: cs.surface,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            Gap.lg + 4,
            MediaQuery.paddingOf(context).top + Gap.lg,
            Gap.lg + 4,
            kNavBarClearance,
          ),
          children: [
            // Greeting -------------------------------------------------------
            Stagger(
              index: 0,
              child: _Greeting(
                name: user.firstName,
                streak: stats.currentStreak,
                now: now,
              ),
            ),
            const SizedBox(height: Gap.xl),

            if (_refreshing) ...const [
              SkeletonCard(height: 330, radius: Radii.hero),
              SizedBox(height: Gap.xl),
              SkeletonCard(height: 230),
              SizedBox(height: Gap.xl),
              SkeletonCard(height: 310),
              SizedBox(height: Gap.xl),
              SkeletonList(count: 3, itemHeight: 72),
            ] else if (sessions.isEmpty)
              // A brand-new user gets one designed state instead of a page of
              // zeroed charts — the empty state explains what will fill in.
              Stagger(index: 1, child: _NoSessions(onStart: _startFocusing))
            else ...[
              // Daily overview ------------------------------------------------
              Stagger(
                index: 1,
                child: _DailyOverview(
                  progress: progress,
                  minutesToday: minutesToday,
                  goalMinutes: goalMinutes,
                  sessionsToday: sessionsToday,
                  totalHours: stats.totalFocusHours,
                  level: stats.level,
                ),
              ),
              const SizedBox(height: Gap.xl),

              // Weekly --------------------------------------------------------
              const Stagger(
                index: 2,
                child: SectionHeader(
                  title: 'This week',
                  icon: Icons.bar_chart_rounded,
                ),
              ),
              Stagger(
                index: 3,
                child: _WeeklyPanel(
                  total: weekTotal,
                  average: weekAverage,
                  days: week,
                ),
              ),
              const SizedBox(height: Gap.xl),

              // Heatmap -------------------------------------------------------
              const Stagger(
                index: 4,
                child: SectionHeader(
                  title: 'Focus heatmap',
                  icon: Icons.calendar_month_rounded,
                ),
              ),
              Stagger(
                index: 5,
                child: Card.filled(
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.lg),
                    child: FocusHeatmap(weeks: heatmapWeeks),
                  ),
                ),
              ),
              const SizedBox(height: Gap.xl),

              // App shields ---------------------------------------------------
              Stagger(
                index: 6,
                child: SectionHeader(
                  title: 'App shields',
                  icon: Icons.shield_rounded,
                  trailing: Text(
                    '$activeShields active',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const Stagger(
                index: 7,
                child: Card.filled(
                  child: Padding(
                    padding: EdgeInsets.all(Gap.lg),
                    child: AppDistribution(),
                  ),
                ),
              ),
              const SizedBox(height: Gap.xl),

              // Subjects ------------------------------------------------------
              const Stagger(
                index: 8,
                child: SectionHeader(
                  title: 'Subject breakdown',
                  icon: Icons.donut_large_rounded,
                ),
              ),
              Stagger(
                index: 9,
                child: Card.filled(
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.lg),
                    child: SubjectBreakdown(subjects: subjects),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
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
  });

  final String name;
  final int streak;
  final DateTime now;

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
  });

  final double progress;
  final int minutesToday;
  final int goalMinutes;
  final int sessionsToday;
  final double totalHours;
  final int level;

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
class _WeeklyPanel extends StatelessWidget {
  const _WeeklyPanel({
    required this.total,
    required this.average,
    required this.days,
  });

  final double total;
  final double average;
  final List<DayBar> days;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${total.toStringAsFixed(1)}h',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    'focused',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const Spacer(),
                _MetaPill(
                  icon: Icons.insights_rounded,
                  label: '${formatHoursShort(average)} avg',
                  color: cs.secondary,
                ),
              ],
            ),
            const SizedBox(height: Gap.lg),
            WeeklyChart(days: days),
          ],
        ),
      ),
    );
  }
}

/// Designed first-run state — shown whenever there is nothing to chart.
class _NoSessions extends StatelessWidget {
  const _NoSessions({required this.onStart});

  final VoidCallback onStart;

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
            'the daily ring, weekly chart, heatmap and app shields.',
        action: FilledButton.icon(
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

/// Small delta badge used next to headline metrics.
class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 13, color: color),
      label: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
      labelPadding: EdgeInsets.zero,
      backgroundColor: color.withValues(alpha: 0.16),
      side: BorderSide(color: color.withValues(alpha: 0.42)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
