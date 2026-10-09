import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/providers/study_providers.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/tonal_panel.dart';
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

    return TonalPanel(
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Eyebrow('YOUR WEEK IN FOCUS', icon: Icons.insights_rounded),
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
            '$active active ${active == 1 ? 'day' : 'days'} in the last 7 days',
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
                'Today: ${formatMinutes(today)} / ${formatMinutes(goal)}',
                style: tt.labelMedium,
              ),
              TextButton.icon(
                onPressed: () => showDailyGoalSheet(context),
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: const Text('Adjust goal'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ProfileShortcuts extends StatelessWidget {
  const ProfileShortcuts({super.key, required this.guardian});
  final bool guardian;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 330 ||
            MediaQuery.textScalerOf(context).scale(14) > 20;
        final width = stacked
            ? constraints.maxWidth
            : (constraints.maxWidth - Gap.md) / 2;
        return Wrap(
          spacing: Gap.md,
          runSpacing: Gap.md,
          children: [
            for (final action in [
              (
                guardian
                    ? Icons.family_restroom_outlined
                    : Icons.play_arrow_rounded,
                guardian ? 'Parent dashboard' : 'Start focusing',
                guardian ? AppRoutes.parentControl : AppRoutes.focus,
              ),
              (Icons.shield_outlined, 'Manage Shield', AppRoutes.shield),
            ])
              SizedBox(
                width: width,
                child: Material(
                  color: cs.secondaryContainer.withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(Radii.item),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.item),
                    onTap: () => context.goNamed(action.$3),
                    child: Padding(
                      padding: const EdgeInsets.all(Gap.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(action.$1, color: cs.onSecondaryContainer),
                          const SizedBox(height: Gap.md),
                          Text(
                            action.$2,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: cs.onSecondaryContainer),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
