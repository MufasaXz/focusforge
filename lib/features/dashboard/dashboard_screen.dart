import 'package:flutter/material.dart';

import '../../app/shell/app_shell.dart';
import '../../app/theme/color_tokens.dart';
import '../../app/theme/glass_theme.dart';
import '../../core/data/mock_data.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/glass_surface.dart';
import '../../shared/widgets/progress_ring.dart';
import '../../shared/widgets/stagger.dart';
import 'widgets/app_distribution.dart';
import 'widgets/focus_heatmap.dart';
import 'widgets/subject_breakdown.dart';
import 'widgets/weekly_chart.dart';

/// Tab 1 — the all-in-one analytics dashboard.
///
/// No app bar: the screen opens on a greeting, and every section is a glass
/// panel floating over the ambient canvas. Sections stagger in on first build.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final now = DateTime.now();
    final progress = DemoData.focusMinutesToday / DemoData.focusGoalMinutes;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        Gap.lg + 4,
        MediaQuery.paddingOf(context).top + Gap.lg,
        Gap.lg + 4,
        kNavBarClearance,
      ),
      children: [
        // Greeting -----------------------------------------------------------
        Stagger(
          index: 0,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${greetingFor(now)}, ${DemoData.userName}',
                      style: context.type.headlineMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      formatDate(now),
                      style: context.type.bodySmall
                          ?.copyWith(color: t.textTertiary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Gap.md),
              // Streak chip — the one number worth surfacing in the chrome.
              GlassPanel(
                radius: Radii.pill,
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.md,
                  vertical: 8,
                ),
                accent: t.gold,
                glowStrength: 0.55,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      size: 15,
                      color: t.gold,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${DemoData.streakDays}',
                      style: context.type.labelLarge?.copyWith(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.xl),

        // Daily overview -----------------------------------------------------
        Stagger(
          index: 1,
          child: GlassPanel(
            radius: Radii.hero,
            blur: 18,
            padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xl, Gap.xl, Gap.lg),
            child: Column(
              children: [
                ProgressRing(
                  value: progress,
                  size: 188,
                  stroke: 11,
                  ticks: 24,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatMinutes(DemoData.focusMinutesToday),
                        style: context.type.displayMedium?.copyWith(
                          fontSize: 36,
                          letterSpacing: -1.4,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'of ${formatMinutes(DemoData.focusGoalMinutes)} goal',
                        style: context.type.bodySmall?.copyWith(
                          color: t.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Gap.xl),
                const Row(
                  children: [
                    Expanded(
                      child: _StatChip(
                        icon: Icons.phone_iphone_rounded,
                        value: '${DemoData.pickups}',
                        label: 'Pickups',
                      ),
                    ),
                    SizedBox(width: Gap.sm),
                    Expanded(
                      child: _StatChip(
                        icon: Icons.lock_open_rounded,
                        value: '${DemoData.unlocks}',
                        label: 'Unlocks',
                      ),
                    ),
                    SizedBox(width: Gap.sm),
                    Expanded(
                      child: _StatChip(
                        icon: Icons.timer_rounded,
                        value: '${DemoData.focusMinutesStat}',
                        label: 'Focus mins',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Gap.xl),

        // Weekly --------------------------------------------------------------
        const Stagger(
          index: 2,
          child: SectionHeader(title: 'This week', icon: Icons.bar_chart_rounded),
        ),
        Stagger(
          index: 3,
          child: GlassPanel(
            radius: Radii.card,
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${DemoData.weekTotalHours}h',
                      style: context.type.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(width: Gap.sm),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        'focused',
                        style: context.type.bodySmall,
                      ),
                    ),
                    const Spacer(),
                    const _TrendPill(label: '+18%'),
                  ],
                ),
                const SizedBox(height: Gap.lg),
                const WeeklyChart(days: DemoData.week),
              ],
            ),
          ),
        ),
        const SizedBox(height: Gap.xl),

        // Heatmap --------------------------------------------------------------
        const Stagger(
          index: 4,
          child: SectionHeader(
            title: 'Focus heatmap',
            icon: Icons.calendar_month_rounded,
          ),
        ),
        Stagger(
          index: 5,
          child: GlassPanel(
            radius: Radii.card,
            padding: const EdgeInsets.all(Gap.lg),
            child: const FocusHeatmap(weeks: DemoData.heatmap),
          ),
        ),
        const SizedBox(height: Gap.xl),

        // App distribution ------------------------------------------------------
        Stagger(
          index: 6,
          child: SectionHeader(
            title: 'App distribution',
            icon: Icons.apps_rounded,
            trailing: Text(
              'Today',
              style: context.type.labelSmall?.copyWith(color: t.textTertiary),
            ),
          ),
        ),
        Stagger(
          index: 7,
          child: GlassPanel(
            radius: Radii.card,
            padding: const EdgeInsets.all(Gap.lg),
            child: const AppDistribution(apps: DemoData.apps),
          ),
        ),
        const SizedBox(height: Gap.xl),

        // Subjects ---------------------------------------------------------------
        const Stagger(
          index: 8,
          child: SectionHeader(
            title: 'Subject breakdown',
            icon: Icons.donut_large_rounded,
          ),
        ),
        Stagger(
          index: 9,
          child: GlassPanel(
            radius: Radii.card,
            padding: const EdgeInsets.all(Gap.lg),
            child: const SubjectBreakdown(subjects: DemoData.subjects),
          ),
        ),
      ],
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
    final t = context.glass;
    return GlassPanel(
      level: 2,
      radius: Radii.item,
      sheen: false,
      padding: const EdgeInsets.symmetric(vertical: Gap.md, horizontal: Gap.sm),
      child: Column(
        children: [
          Icon(icon, size: 16, color: t.accentPrimary),
          const SizedBox(height: 7),
          Text(
            value,
            style: context.type.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: context.type.labelSmall?.copyWith(
              fontSize: 10,
              color: t.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small delta badge used next to headline metrics.
class _TrendPill extends StatelessWidget {
  const _TrendPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final c = t.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm + 2, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: c.withValues(alpha: 0.42)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.trending_up_rounded, size: 13, color: c),
          const SizedBox(width: 3),
          Text(
            label,
            style: context.type.labelSmall?.copyWith(
              color: c,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
