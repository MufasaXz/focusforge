import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/social_providers.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/icon_badge.dart';

/// The week, measured.
///
/// This screen used to be a competitive board. It is not one any more, because
/// there is no server behind it — and a board populated with invented names is
/// the one kind of demo data a user cannot tell from the real thing. A rival
/// you did not know you had is worse than no rival.
///
/// What is left is the comparison the app can actually make: this week against
/// last week, both counted from the same session log. That is a real number,
/// and it is the one the user can act on.
class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thisWeek = ref.watch(leaderboardWeekHoursProvider);
    final lastWeek = ref.watch(previousWeekHoursProvider);
    final sessions = ref.watch(weekSessionCountProvider);
    final groups = ref.watch(groupsProvider);

    return AppPage(
      title: 'Your week',
      subtitle: 'Monday to today',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (thisWeek <= 0 && lastWeek <= 0)
            const EmptyState(
              icon: Icons.insights_outlined,
              title: 'No focus logged this week',
              subtitle:
                  'Finish a session and this page fills in — your hours, your '
                  'streak, and how this week compares with the last one.',
            )
          else ...[
            _WeekCard(
              thisWeek: thisWeek,
              lastWeek: lastWeek,
              sessions: sessions,
            ),
            const SizedBox(height: Gap.xl),
          ],
          const SectionHeader(
            title: 'Study groups',
            icon: Icons.groups_rounded,
          ),
          if (groups.isEmpty)
            _NoGroupsCard()
          else
            for (var i = 0; i < groups.length; i++) ...[
              if (i > 0) const SizedBox(height: Gap.md),
              _GroupRow(
                name: groups[i].name,
                icon: groups[i].icon,
                hours: groups[i].weeklyHours,
                target: groups[i].targetHours,
                accent: SubjectPalette.harmonized(
                  Theme.of(context).colorScheme.primary,
                )[i % SubjectPalette.count],
              ),
            ],
          const SizedBox(height: Gap.lg),
          _NoServerNote(),
        ],
      ),
    );
  }
}

/// This week against last week, from one session log.
class _WeekCard extends StatelessWidget {
  const _WeekCard({
    required this.thisWeek,
    required this.lastWeek,
    required this.sessions,
  });

  final double thisWeek;
  final double lastWeek;
  final int sessions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final delta = thisWeek - lastWeek;
    final up = delta >= 0;
    final accent = up ? cs.primary : cs.tertiary;

    // Against the better of the two weeks, so the bar has a meaningful
    // ceiling: a week that doubled still shows a full bar next to a flat one.
    final ceiling = thisWeek > lastWeek ? thisWeek : lastWeek;
    final progress = ceiling <= 0 ? 0.0 : (thisWeek / ceiling).clamp(0.0, 1.0);

    return Card.outlined(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.hero),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatHoursShort(thisWeek),
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'focused this week',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (lastWeek > 0)
                  Chip(
                    avatar: Icon(
                      up
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                      size: 15,
                      color: accent,
                    ),
                    label: Text(
                      '${up ? '+' : '−'}${formatHoursShort(delta.abs())}',
                    ),
                    backgroundColor: accent.withValues(alpha: 0.14),
                  ),
              ],
            ),
            const SizedBox(height: Gap.lg),
            Semantics(
              label: 'This week against last week',
              value: '${(progress * 100).round()} percent',
              child: LinearProgressIndicator(
                value: progress,
                color: cs.primary,
                backgroundColor: cs.surfaceContainerHighest,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: Gap.sm),
            Row(
              children: [
                Text(
                  sessions == 1 ? '1 session' : '$sessions sessions',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const Spacer(),
                Text(
                  lastWeek > 0
                      ? 'Last week ${formatHoursShort(lastWeek)}'
                      : 'No week before this one yet',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.name,
    required this.icon,
    required this.hours,
    required this.target,
    required this.accent,
  });

  final String name;
  final IconData icon;
  final double hours;
  final double target;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progress = target <= 0 ? 0.0 : (hours / target).clamp(0.0, 1.0);

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconBadge(icon: icon, color: accent, size: 38, radius: 12),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Just you · ${formatHoursShort(hours)} this week',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Chip(label: Text('${(progress * 100).round()}%')),
              ],
            ),
            const SizedBox(height: Gap.md),
            Semantics(
              label: '$name weekly target',
              value: '${(progress * 100).round()} percent',
              child: LinearProgressIndicator(
                value: progress,
                color: accent,
                backgroundColor: cs.surfaceContainerHighest,
                minHeight: 6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoGroupsCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final signedIn = !ref.watch(userProvider).isAnonymous;

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Row(
          children: [
            Icon(Icons.groups_outlined, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(
                signedIn
                    ? 'No groups yet. Create one to set a shared weekly target.'
                    : 'Study groups need an account. Link one to set a weekly '
                          'target you can share.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: Gap.sm),
            TextButton(
              onPressed: () =>
                  context.push(AppRoutes.paths[AppRoutes.groups]!),
              child: Text(signedIn ? 'Open' : 'Link'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Why there is nobody else on this screen. One line, at the bottom, where it
/// answers the question the user is already asking.
class _NoServerNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.info_outline_rounded, size: 15, color: cs.onSurfaceVariant),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Text(
            'FocusForge has no server, so there is nobody else to compare '
            'with yet. Every number here is yours.',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
