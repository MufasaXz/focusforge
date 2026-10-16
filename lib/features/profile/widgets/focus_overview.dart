import '../../../core/localization/app_strings.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/providers/study_providers.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/tonal_panel.dart';
import '../../../shared/widgets/glass_surface.dart';
import '../../dashboard/widgets/daily_goal_sheet.dart';

/// A recap derived from completed sessions, with direct access to daily goals.
class FocusOverview extends ConsumerWidget {
  const FocusOverview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final days = ref.watch(weeklyBarsProvider);
    final total = days.fold<double>(0, (sum, day) => sum + day.hours);
    final active = days.where((day) => day.hours > 0).length;
    final maximum = days.fold<double>(
      1,
      (value, day) => math.max(value, day.hours),
    );
    final today = ref.watch(focusMinutesTodayProvider);
    final goal = ref.watch(todayGoalMinutesProvider);

    return ContentCard(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Eyebrow(
              context.tr("YOUR WEEK IN FOCUS"),
              icon: Icons.insights_rounded,
            ),
            const SizedBox(height: Gap.md),
            Text(
              formatMinutes((total * 60).round()),
              style: tt.headlineMedium?.copyWith(
                letterSpacing: -1,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Gap.xs),
            Text(
              context.tr("{0} active {1} in the last 7 days", [
                active,
                active == 1 ? 'day' : 'days',
              ]),
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: Gap.lg),
            Semantics(
              label: days
                  .map(
                    (day) =>
                        '${day.label}: ${formatMinutes((day.hours * 60).round())}',
                  )
                  .join(', '),
              child: ExcludeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final day in days)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            children: [
                              SizedBox(
                                height: 58,
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    height: 5 + 53 * day.hours / maximum,
                                    decoration: BoxDecoration(
                                      color: day.hours > 0
                                          ? cs.primary
                                          : cs.outlineVariant.withValues(
                                              alpha: .45,
                                            ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: Gap.sm),
                              FittedBox(
                                child: Text(day.label, style: tt.labelSmall),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Gap.lg),
            Divider(color: cs.outlineVariant.withValues(alpha: .45)),
            const SizedBox(height: Gap.sm),
            Wrap(
              spacing: Gap.md,
              runSpacing: Gap.sm,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  context.tr("Today: {0} / {1}", [
                    formatMinutes(today),
                    formatMinutes(goal),
                  ]),
                  style: tt.labelMedium,
                ),
                TextButton.icon(
                  onPressed: () => showDailyGoalSheet(context),
                  icon: const Icon(Icons.tune_rounded, size: 16),
                  label: Text(context.tr("Adjust goal")),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
