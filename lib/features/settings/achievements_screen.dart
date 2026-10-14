import '../../shared/widgets/glass_surface.dart';

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/social.dart';
import '../../core/providers/social_providers.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/icon_badge.dart';
import '../../shared/widgets/pressable.dart';
import 'settings_support.dart';

/// The badge cabinet.
///
/// Locked badges are shown, not hidden — a greyed tile with a progress bar is
/// a goal, whereas a "?" placeholder is just an absence. Unlocked badges keep
/// their own colour so the grid reads as a collection rather than a list.
///
/// Progress is measured from the user's own stats and session log; badges
/// nothing in the app can measure yet are not in the catalogue at all, so a
/// locked tile here is always a target the user can actually reach.
class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(achievementSyncProvider);
    final backup = ref.watch(achievementBackupStatusProvider);
    final badges = ref.watch(achievementsProvider);
    final unlocked = ref.watch(unlockedCountProvider);
    final earned = badges.where((b) => b.unlocked).toList()
      ..sort((a, b) {
        // Unknown legacy dates follow dated earns; stable IDs break ties.
        final byDate = b.unlockedAt!.compareTo(a.unlockedAt!);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });
    final locked = badges.where((b) => !b.unlocked).toList(growable: false);

    return AppPage(
      title: 'Achievements',
      subtitle: '$unlocked of ${badges.length} unlocked',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CollectionSummary(unlocked: unlocked, total: badges.length),
          const SizedBox(height: Gap.lg),
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.lg),
            child: Row(
              children: [
                Icon(
                  backup == AchievementBackupStatus.saved
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(switch (backup) {
                    AchievementBackupStatus.localOnly => 'Saved on this device. Link an account for private backup.',
                    AchievementBackupStatus.syncing =>
                      'Saving your earned achievements…',
                    AchievementBackupStatus.saved =>
                      'Earned achievements saved to your account.',
                    AchievementBackupStatus.pending => 'Saved on this device. Account backup is waiting to reconnect.',
                  }, style: Theme.of(context).textTheme.bodySmall),
                ),
                if (backup == AchievementBackupStatus.pending)
                  TextButton(
                    onPressed: () => ref.read(achievementSyncProvider)(),
                    child: const Text('Retry'),
                  ),
              ],
            ),
          ),
          _NextMilestone(locked: locked),
          const SizedBox(height: Gap.xl),
          const SectionHeader(
            title: 'Unlocked',
            icon: Icons.workspace_premium_rounded,
          ),
          if (earned.isEmpty)
            Text(
              'Your first earned badge will appear here.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            _BadgeGrid(badges: earned),
          const SizedBox(height: Gap.xl),
          SectionHeader(
            title: 'Locked',
            icon: Icons.lock_outline_rounded,
            trailing: Text(
              '${locked.length}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          if (locked.isNotEmpty) _BadgeGrid(badges: locked),
        ],
      ),
    );
  }
}

class _CollectionSummary extends StatelessWidget {
  const _CollectionSummary({required this.unlocked, required this.total});

  final int unlocked;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ContentCard(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Your collection', style: theme.textTheme.titleMedium),
            const SizedBox(height: Gap.sm),
            Text(
              '$unlocked of $total earned',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: Gap.md),
            Semantics(
              label: 'Achievement collection',
              value: '$unlocked of $total earned',
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : unlocked / total,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: Gap.sm),
            Text(
              unlocked == total && total > 0
                  ? 'Every milestone earned. Your collection is complete.'
                  : 'Every completed session moves you forward.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// The nearest measured target stays available after the first badge is earned.
class _NextMilestone extends StatelessWidget {
  const _NextMilestone({required this.locked});

  final List<Achievement> locked;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (locked.isEmpty) return const SizedBox.shrink();

    final closest = locked.reduce((a, b) => a.ratio >= b.ratio ? a : b);

    return ContentCard(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Next milestone',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: Gap.md),
            Row(
              children: [
                IconBadge(
                  icon: closest.icon,
                  color: closest.color,
                  size: 44,
                  radius: 13,
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Text(
                    closest.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.md),
            Text(
              closest.description,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: Gap.md),
            Semantics(
              label: '${closest.name} progress',
              value: closest.progressLabel,
              child: LinearProgressIndicator(
                value: closest.ratio,
                color: closest.color,
                backgroundColor: cs.surfaceContainerHighest,
                minHeight: 5,
              ),
            ),
            const SizedBox(height: Gap.sm),
            Text(
              closest.remainingLabel,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: Gap.sm),
            TextButton.icon(
              onPressed: () => _openDetail(context, closest),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('View milestone'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeGrid extends StatelessWidget {
  const _BadgeGrid({required this.badges});

  final List<Achievement> badges;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = (MediaQuery.textScalerOf(context).scale(14) / 14)
            .clamp(1.0, 3.0);
        final columns =
            ((constraints.maxWidth + Gap.md) /
                    (_targetTileWidth * textScale + Gap.md))
                .floor()
                .clamp(1, 6);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: Gap.md,
            crossAxisSpacing: Gap.md,
            mainAxisExtent: 192 + 72 * (textScale - 1),
          ),
          itemCount: badges.length,
          itemBuilder: (context, i) => _BadgeTile(
            key: ValueKey('achievement-${badges[i].id}'),
            badge: badges[i],
          ),
        );
      },
    );
  }

  static const double _targetTileWidth = 136;
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({super.key, required this.badge});

  final Achievement badge;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final unlocked = badge.unlocked;
    final color = unlocked
        ? badge.color
        : Color.lerp(badge.color, cs.onSurfaceVariant, 0.78)!;

    return Pressable(
      onTap: () => _openDetail(context, badge),
      scale: 0.94,
      child: Card.outlined(
        // An unlocked tile keeps its badge's colour on the outline; a locked
        // one falls back to the neutral border.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: BorderSide(
            color: unlocked
                ? badge.color.withValues(alpha: 0.55)
                : cs.outlineVariant,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.sm,
            vertical: Gap.md,
          ),
          child: Column(
            children: [
              IconBadge(icon: badge.icon, color: color, size: 46, radius: 14),
              const SizedBox(height: Gap.sm),
              Text(
                badge.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontSize: 13,
                  color: unlocked ? cs.onSurface : cs.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (unlocked)
                Text(
                  _earnedOn(badge.unlockedAt),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                )
              else ...[
                Semantics(
                  label: '${badge.name} progress',
                  value: badge.progressLabel,
                  child: LinearProgressIndicator(
                    value: badge.ratio,
                    color: color,
                    backgroundColor: cs.surfaceContainerHighest,
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  badge.remainingLabel,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Transparent-barrier sheet with the badge's full story.
void _openDetail(BuildContext context, Achievement badge) {
  final cs = Theme.of(context).colorScheme;
  final unlocked = badge.unlocked;
  final color = unlocked
      ? badge.color
      : Color.lerp(badge.color, cs.onSurfaceVariant, 0.6)!;

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: EdgeInsets.fromLTRB(
        Gap.lg,
        Gap.lg,
        Gap.lg,
        Gap.lg + MediaQuery.paddingOf(context).bottom,
      ),
      // A modal sheet is one of the three places the redesign allows a real
      // frosted blur: σ24 over a near-opaque tonal fill.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.hero),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.85,
            ),
            color: cs.surfaceContainerLow.withValues(alpha: 0.9),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Gap.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant,
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                    ),
                  ),
                  const SizedBox(height: Gap.xl),
                  Center(
                    child: IconBadge(
                      icon: badge.icon,
                      color: color,
                      size: 64,
                      radius: 20,
                      semanticLabel: badge.name,
                    ),
                  ),
                  const SizedBox(height: Gap.lg),
                  Text(
                    badge.name,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: Gap.sm),
                  Text(
                    badge.description,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: Gap.xl),
                  if (unlocked)
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: Gap.sm,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: cs.tertiary,
                        ),
                        Text(
                          isUnknownUnlockTime(badge.unlockedAt)
                              ? 'Earned earlier'
                              : 'Earned on ${_formatDate(badge.unlockedAt!)}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: cs.tertiary),
                        ),
                      ],
                    )
                  else ...[
                    Semantics(
                      label: '${badge.name} progress',
                      value: badge.progressLabel,
                      child: LinearProgressIndicator(
                        value: badge.ratio,
                        color: color,
                        backgroundColor: cs.surfaceContainerHighest,
                        minHeight: 7,
                      ),
                    ),
                    const SizedBox(height: Gap.md),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          badge.progressLabel,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: Gap.sm),
                        Text(
                          badge.remainingLabel,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: Gap.xl),
                  AppActionButton(
                    label: 'Close',
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _formatDate(DateTime date) =>
    '${date.day} ${_months[date.month - 1]} ${date.year}';

/// Unlocks restored from a store that predates timestamp tracking have no real
/// date; say so rather than printing the epoch as if it were the day it was
/// earned.
String _earnedOn(DateTime? at) =>
    at == null || isUnknownUnlockTime(at) ? 'Earned earlier' : _formatDate(at);
