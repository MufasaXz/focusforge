import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/providers/parent_providers.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../../../shared/widgets/pressable.dart';
import '../../../shared/widgets/progress_ring.dart';
import 'child_switcher.dart';
import 'week_strip.dart';

/// The selected child's day and week, on the parent's own dashboard.
///
/// A parent's device is not the one being studied, so the numbers that matter
/// on their home tab are their child's: today's minutes against the goal, and
/// the week's shape. The card is the way into the child's page as well — the
/// whole surface is the tap target, because a parent who wants the detail is
/// the only person looking at it.
///
/// Every read is `valueOrNull`: a denied or offline stream has to be drawn as
/// a state, and `value` throws out of the build when one errors.
class ChildStudyCard extends ConsumerWidget {
  const ChildStudyCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final child = ref.watch(activeChildProvider);
    if (child == null) return const SizedBox.shrink();

    final children =
        ref.watch(childrenProvider).valueOrNull ?? const [];
    final read = ref.watch(childProgressProvider(child.uid));
    final progress = read.valueOrNull;

    void open() => context.pushNamed(
      AppRoutes.parentChild,
      pathParameters: {'uid': child.uid},
    );

    return Card.filled(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.hero),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (children.length > 1) ...[
              const SizedBox(height: 36, child: ChildChips()),
              const SizedBox(height: Gap.md),
            ],
            Semantics(
              button: true,
              label:
                  '${child.name}\'s study. '
                  '${progress == null ? 'Nothing published yet' : '${formatMinutes(progress.minutes)} today of a ${formatMinutes(progress.goalMinutes)} goal'}'
                  '. Opens their page.',
              excludeSemantics: true,
              onTap: open,
              child: Pressable(
                onTap: open,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconBadge(
                          icon: Icons.person_rounded,
                          color: Theme.of(context).colorScheme.tertiary,
                          size: 36,
                          radius: 10,
                        ),
                        const SizedBox(width: Gap.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                child.name,
                                style: Theme.of(context).textTheme.titleMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Their study',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                    const SizedBox(height: Gap.lg),
                    if (progress == null || progress.updatedAt == null)
                      Text(
                        read.hasError
                            ? 'Their summary could not be read just now.'
                            : 'Nothing from their device yet — it publishes '
                                  'as the app is used.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      )
                    else ...[
                      Row(
                        children: [
                          ProgressRing(
                            value: progress.goalProgress,
                            size: 68,
                            stroke: 7,
                            semanticLabel:
                                '${progress.minutes} of '
                                '${progress.goalMinutes} minutes today',
                            child: Text(
                              '${(progress.goalProgress * 100).round()}%',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                          const SizedBox(width: Gap.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  formatHoursShort(progress.minutes / 60),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineSmall,
                                ),
                                Text(
                                  'of a ${formatMinutes(progress.goalMinutes)} '
                                  'goal today',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    progress.sessions == 1
                                        ? '1 session'
                                        : '${progress.sessions} sessions',
                                    if (progress.streak > 1)
                                      '${progress.streak}-day streak',
                                  ].join(' · '),
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Gap.lg),
                      WeekStrip(progress: progress, height: 40),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
