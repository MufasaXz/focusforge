import '../../core/localization/app_strings.dart';

import 'dart:async';

import '../../shared/widgets/glass_surface.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/shell/app_shell.dart';
import '../../app/theme/app_theme.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/coach_providers.dart';
import '../../core/providers/study_providers.dart';
import '../../core/providers/goal_planner_providers.dart';
import '../../core/providers/usage_providers.dart';
import '../../core/providers/usage_stats_providers.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/icon_badge.dart';
import '../../shared/widgets/stagger.dart';
import '../../shared/widgets/tonal_panel.dart';
import '../assistant/home/pip_dock.dart';
import '../onboarding/coach_marks.dart';
import 'widgets/daily_goal_sheet.dart';
import 'widgets/goal_ring.dart';
import 'widgets/session_shortcut.dart';
import 'widgets/study_week.dart';
import 'widgets/usage_access_card.dart';

/// Tab 1 — the all-in-one analytics dashboard.
///
/// No app bar: the screen opens on a greeting, and every section sits in a
/// tonal card on the scaffold surface. Everything below the greeting is read
/// from the Riverpod stores, so a session finished on the Focus tab is
/// reflected the moment this screen rebuilds.
///
/// Refresh re-reads device usage while the local study log stays on screen.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  late final StreamSubscription<DateTime> _calendar;

  @override
  void initState() {
    super.initState();
    _calendar = Stream<DateTime>.periodic(
      const Duration(minutes: 1),
      (_) => DateTime.now(),
    ).listen((_) => ref.read(focusCalendarDateProvider.notifier).refresh());
  }

  @override
  void dispose() {
    _calendar.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.read(timerProvider.notifier).sync();
    ref.read(focusCalendarDateProvider.notifier).refresh();
    ref.invalidate(usageAccessProvider);
    refreshUsage(ref);
    // Each card owns its error state. Keep the saved study log visible even
    // if the platform cannot answer a usage read.
    await Future.wait([ref.read(usageAccessProvider.future)])
        .then<void>((_) {}, onError: (Object _, StackTrace _) {});
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
    ref.watch(focusCalendarDateProvider);
    final now = DateTime.now();

    final user = ref.watch(userProvider);
    final stats = ref.watch(statsProvider);
    final sessions = ref.watch(sessionsProvider);
    final goal = ref.watch(activeFocusGoalProvider);
    // Derived from the session log, not read from the stats aggregate: a
    // streak is a fact about dates and the aggregate carries none.
    final streak = ref.watch(currentStreakProvider);

    final sessionsToday = sessions
        .where((s) => s.completed && _sameDay(s.startedAt, now))
        .length;

    // Measure the room remaining beside the rail, including split windows.
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= Layout.wide;

        // The first-run tips, built from what is actually on screen. A tip whose
        // subject is not rendered — the ring before the first session, the streak
        // chip at zero — is left out rather than pointed at nothing.
        final targets = ref.watch(coachTargetsProvider);
        final spots = <CoachSpot>[
          if (goal == null)
            CoachSpot(
              target: targets.emptyCta,
              icon: Icons.play_arrow_rounded,
              title: context.tr("Plan your focus time"),
              body: context.tr(
                "Set your daily focus time. Your progress ring appears when you save.",
              ),
            )
          else
            CoachSpot(
              target: targets.ring,
              icon: Icons.donut_large_rounded,
              title: context.tr("Your daily progress"),
              body: context.tr(
                "This ring fills as you focus — it starts moving the moment a block runs, and keeps what you finish.",
              ),
            ),
          if (streak > 0)
            CoachSpot(
              target: targets.streak,
              icon: Icons.local_fire_department_rounded,
              title: context.tr("Build your streak"),
              body: context.tr("Study every day and the flame keeps growing."),
            ),
          CoachSpot(
            target: targets.focusTab,
            icon: Icons.timer_rounded,
            title: context.tr("Your timer lives here"),
            body: context.tr(
              "The Focus tab starts a Pomodoro and runs the shield while it counts down.",
            ),
          ),
          CoachSpot(
            target: targets.shieldTab,
            icon: Icons.shield_outlined,
            title: context.tr("Start blocking apps like this"),
            body: context.tr(
              "The Shield tab lists the apps you can close. Switch one on, and it stops opening until you switch it off.",
            ),
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
        //
        final left = <Widget>[
          if (goal == null)
            _PlanGoalCard(
              savedGoalMinutes: ref
                  .watch(focusGoalPlannerProvider)
                  .day
                  ?.totalMinutes,
              onPlan: () => showDailyGoalSheet(context),
              ctaKey: targets.emptyCta,
            )
          else
            _DailyOverview(
              sessionsToday: sessionsToday,
              totalHours: stats.totalFocusHours,
              level: stats.level,
              ringKey: targets.ring,
              onFocus: _startFocusing,
            ),
          const UsageAccessCard(),
        ];
        // The week, by subject, once there is study to draw — and today's
        // screen time under it, once the phone shares it.
        final screenTime =
            ref.watch(appListConsentProvider) &&
            ref.watch(usageAccessProvider).valueOrNull == true;
        // An inactive week stays a single, centred column: an empty chart is
        // not worth spreading the page into two for.
        final studied = ref.watch(weekStudyProvider).total > 0;
        final history = <Widget>[
          if (studied || screenTime) ...[
            const SizedBox(height: Gap.xl),
            SectionHeader(
              title: context.tr("This week"),
              icon: Icons.bar_chart_rounded,
            ),
            StudyWeekOverview(screenTime: screenTime),
          ],
        ];

        return PipDock(
          child: CoachMarks(
            spots: spots,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: wide && history.isNotEmpty
                      ? Layout.readable * 2 + Gap.xl
                      : Layout.readable,
                ),
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  color: cs.primary,
                  backgroundColor: cs.surface,
                  child: wide && history.isNotEmpty
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: _staggered(left, from: 1),
                                    ),
                                  ),
                                  const SizedBox(width: Gap.xl),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: _staggered(
                                        history,
                                        from: 1 + left.length,
                                      ),
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
                            ..._staggered([...left, ...history]),
                          ],
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The screen's own padding, so both scroll shapes agree.
  EdgeInsets _padding(BuildContext context) => EdgeInsets.fromLTRB(
    Gap.lg + 4,
    MediaQuery.paddingOf(context).top + Gap.lg,
    Gap.lg + 4,
    // Room for the last card to rise above Pip, who stands on the bar.
    kNavBarClearance + PipDock.clearance,
  );

  List<Widget> _staggered(List<Widget> children, {int from = 0}) => [
    for (var i = 0; i < children.length; i++)
      Stagger(index: from + i, child: children[i]),
  ];
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
  return parts.isEmpty ? tr("no focus logged") : parts.join(' ');
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
              // The date as the page's eyebrow — the same accent-over-title
              // rhythm the screens below the greeting use, so the header joins
              // the page instead of floating above it.
              Text(
                formatDate(
                  now,
                  locale: Localizations.localeOf(context),
                ).toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cs.primary,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: Gap.xs),
              Text(
                // A nameless user gets "Good morning", not "Good morning, " —
                // the comma only belongs there when something follows it.
                [
                  greetingFor(now, locale: Localizations.localeOf(context)),
                  if (name.isNotEmpty) name,
                ].join(', '),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ],
          ),
        ),
        if (streak > 0) ...[
          const SizedBox(width: Gap.md),
          // The flame lands rather than appearing: a streak is the one number
          // on this screen that is worth noticing, and it arrives with the
          // overshoot of something being put down. Keyed on the value, so a
          // streak that grows replays it — and one that does not sits still.
          TweenAnimationBuilder<double>(
            key: ValueKey<int>(streak),
            tween: Tween<double>(begin: 0.72, end: 1),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 520),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Chip(
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
          ),
        ],
      ],
    );
  }
}

/// The day's gauge: the goal ring, today's target, and the day's numbers.
///
/// It watches the live focus count itself rather than taking it as an
/// argument: that count changes once a second while a block is running, and a
/// dashboard that rebuilt its charts, heatmap and breakdown at that rate would
/// be paying for the ring with the rest of the page.
class _DailyOverview extends ConsumerWidget {
  const _DailyOverview({
    required this.sessionsToday,
    required this.totalHours,
    required this.level,
    this.ringKey,
    this.onFocus,
  });

  final int sessionsToday;
  final double totalHours;
  final int level;

  /// Anchor for the first-run tip about the daily ring.
  final Key? ringKey;
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final brightness = Theme.of(context).brightness;

    final plan = ref.watch(activeFocusGoalProvider);
    if (plan == null) return const SizedBox.shrink();
    final goalMinutes = plan.totalMinutes;
    final progress = ref.watch(activeFocusGoalProgressProvider);
    final minutesToday = ref.watch(activeFocusGoalSecondsProvider) ~/ 60;

    return GlassCard(
      key: const ValueKey('daily-goal-tile'),
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.hero),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xl, Gap.xl, Gap.lg),
        child: Column(
          children: [
            GoalRing(
              key: ringKey,
              value: progress,
              size: 224,
              stroke: 16,
              // Every five focused minutes, and every finished block, the
              // ring celebrates the step it has just taken.
              milestone: minutesToday ~/ 5,
              semanticLabel: context.tr(
                "Focus goal, {0} of {1}, {2} percent of goal",
                [
                  _spokenMinutes(minutesToday),
                  _spokenMinutes(goalMinutes),
                  (progress * 100).round(),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (MediaQuery.textScalerOf(context).scale(14) <= 28) ...[
                      SproutMark(
                        size: 32,
                        color: GoalRingPalette.leaf(brightness),
                      ),
                      const SizedBox(height: Gap.sm),
                    ],
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      // The figure rolls up as it changes, so a new minute
                      // reads as progress rather than as a flicker.
                      child: AnimatedSwitcher(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : Motion.emphasizedDuration,
                        switchInCurve: Motion.emphasized,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, .35),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: Text(
                          formatMinutes(minutesToday),
                          key: ValueKey<int>(minutesToday),
                          style: tt.displayMedium?.copyWith(
                            fontSize: 34,
                            letterSpacing: -1.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      context.tr("Focus today"),
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Gap.lg),
            _GoalRow(
              goalMinutes: goalMinutes,
              label: context.tr("Today's goal"),
              onTap: () => showDailyGoalSheet(context),
            ),
            const SizedBox(height: Gap.md),
            LayoutBuilder(
              builder: (context, constraints) {
                final chips = <Widget>[
                  _StatChip(
                    icon: Icons.task_alt_rounded,
                    value: '$sessionsToday',
                    label: context.tr("Sessions"),
                  ),
                  _StatChip(
                    icon: Icons.timelapse_rounded,
                    // `formatHoursShort`, not `.round()`: a first session of 25
                    // minutes is 0.4h, and rounding it to "0h" reads as though
                    // nothing was logged.
                    value: formatHoursShort(totalHours),
                    label: context.tr("All time"),
                  ),
                  _StatChip(
                    icon: Icons.military_tech_rounded,
                    value: '$level',
                    label: context.tr("Level"),
                  ),
                ];

                final stacked =
                    constraints.maxWidth < 260 ||
                    MediaQuery.textScalerOf(context).scale(14) > 19;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(Radii.card),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.md),
                    child: stacked
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var i = 0; i < chips.length; i++) ...[
                                if (i > 0) const SizedBox(height: Gap.lg),
                                chips[i],
                              ],
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < chips.length; i++) ...[
                                if (i > 0) const SizedBox(width: Gap.sm),
                                Expanded(child: chips[i]),
                              ],
                            ],
                          ),
                  ),
                );
              },
            ),
            if (onFocus != null) ...[
              const SizedBox(height: Gap.lg),
              const Divider(),
              const SizedBox(height: Gap.lg),
              SessionShortcut(onOpen: onFocus!),
            ],
          ],
        ),
      ),
    );
  }
}

/// Today's target, and the way into the editor that sets it per day.
///
/// The weekday is named on the row rather than left to the greeting above:
/// the number beside it is that day's, and the one thing this row has to say
/// is that the days do not share a target.
class _GoalRow extends StatelessWidget {
  const _GoalRow({
    required this.goalMinutes,
    required this.onTap,
    required this.label,
  });

  final int goalMinutes;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final today = formatWeekday(
      DateTime.now(),
      locale: Localizations.localeOf(context),
    );

    return Semantics(
      button: true,
      label: context.tr("{0}, {1}, {2}. Opens the goal editor", [
        label,
        today,
        _spokenMinutes(goalMinutes),
      ]),
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.item),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.sm,
            vertical: Gap.sm,
          ),
          child: Row(
            children: [
              IconBadge(
                icon: Icons.flag_rounded,
                color: GoalRingPalette.leaf(Theme.of(context).brightness),
                size: 38,
                radius: 11,
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: tt.bodySmall),
                    Text(
                      formatMinutes(goalMinutes),
                      style: tt.titleMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Gap.sm),
              Icon(Icons.edit_outlined, size: 18, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// A first target is an explicit choice, rather than a shipped default.
class _PlanGoalCard extends StatelessWidget {
  const _PlanGoalCard({
    required this.onPlan,
    this.ctaKey,
    this.savedGoalMinutes,
  });
  final VoidCallback onPlan;
  final Key? ctaKey;
  final int? savedGoalMinutes;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // Premium empty state: a soft primary wash with a quiet lift, so the
    // first-run goal reads as an invitation rather than an empty card.
    return HeroSurface(
      accentStrength: 0.12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: IconBadge(
              icon: Icons.flag_outlined,
              color: cs.primary,
              size: 52,
              radius: 17,
            ),
          ),
          const SizedBox(height: Gap.md),
          Text(
            savedGoalMinutes == null
                ? context.tr("Make room for focus")
                : context.tr("Your goal · {0}", [
                    formatMinutes(savedGoalMinutes!),
                  ]),
            textAlign: TextAlign.center,
            style: tt.headlineSmall,
          ),
          const SizedBox(height: Gap.sm),
          Text(
            savedGoalMinutes == null
                ? context.tr(
                    "Choose your focus time for today. Subject targets are optional.",
                  )
                : context.tr("Your saved target is ready whenever you are."),
            textAlign: TextAlign.center,
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: Gap.lg),
          FilledButton.icon(
            key: ctaKey,
            onPressed: onPlan,
            icon: const Icon(Icons.add_rounded),
            label: Text(context.tr("Set goal")),
          ),
        ],
      ),
    );
  }
}

/// A compact, solid study plan separate from the day's progress gauge.
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
    final tt = Theme.of(context).textTheme;
    return Semantics(
      label: '$label, $value',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(height: Gap.sm),
          Text(
            value,
            style: tt.titleLarge?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Gap.xs),
          Text(label, style: tt.bodySmall, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
