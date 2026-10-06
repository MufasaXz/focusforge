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
    final badges = ref.watch(achievementsProvider);
    final unlocked = ref.watch(unlockedCountProvider);
    final earned = badges.where((b) => b.unlocked).toList(growable: false);
    final locked = badges.where((b) => !b.unlocked).toList(growable: false);

    return AppPage(
      title: 'Achievements',
      subtitle: '$unlocked of ${badges.length} unlocked',
      trailing: Chip(
        label: Text('$unlocked/${badges.length}'),
        backgroundColor: unlocked > 0
            ? Theme.of(context).colorScheme.secondaryContainer
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: 'Unlocked',
            icon: Icons.workspace_premium_rounded,
          ),
          if (earned.isEmpty)
            _ClosestBadge(locked: locked)
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
          _BadgeGrid(badges: locked),
        ],
      ),
    );
  }
}

/// Shown when the collection is still empty. Points at the nearest win instead
/// of just reporting the absence.
class _ClosestBadge extends StatelessWidget {
  const _ClosestBadge({required this.locked});

  final List<Achievement> locked;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (locked.isEmpty) return const SizedBox.shrink();

    final closest = locked.reduce((a, b) => a.ratio >= b.ratio ? a : b);

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Row(
          children: [
            IconBadge(
              icon: closest.icon,
              color: Color.lerp(closest.color, cs.onSurfaceVariant, 0.7)!,
              size: 44,
              radius: 13,
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Nothing unlocked yet',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    closest.ratio >= 1
                        ? '${closest.name} has reached its target.'
                        : 'Closest: ${closest.name} — '
                              '${(closest.ratio * 100).round()}% of the way '
                              'there.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Gap.sm),
                  Semantics(
                    label: '${closest.name} progress',
                    value: '${(closest.ratio * 100).round()} percent',
                    child: LinearProgressIndicator(
                      value: closest.ratio,
                      color: closest.color,
                      backgroundColor: cs.surfaceContainerHighest,
                      minHeight: 5,
                    ),
                  ),
                ],
              ),
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
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: Gap.md,
        crossAxisSpacing: Gap.md,
        // A fixed extent rather than an aspect ratio: the tiles hold two lines
        // of text, and an aspect ratio would overflow them on narrow phones.
        mainAxisExtent: 158,
      ),
      itemCount: badges.length,
      itemBuilder: (context, i) => _BadgeTile(badge: badges[i]),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge});

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
                  fontSize: 11.5,
                  color: unlocked ? cs.onSurface : cs.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (unlocked)
                Text(
                  _earnedOn(badge.unlockedAt),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: cs.onSurfaceVariant,
                  ),
                )
              else ...[
                Semantics(
                  label: '${badge.name} progress',
                  value: '${(badge.ratio * 100).round()} percent',
                  child: LinearProgressIndicator(
                    value: badge.ratio,
                    color: color,
                    backgroundColor: cs.surfaceContainerHighest,
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  // The provider unlocks every met target, so a locked badge
                  // should never sit at 100%; the guard keeps a mid-refresh
                  // rebuild from rendering a full bar as a bare percentage.
                  badge.ratio >= 1
                      ? 'Complete'
                      : '${(badge.ratio * 100).round()}%',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: cs.onSurfaceVariant,
                  ),
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
  final capped = badge.progress > badge.target ? badge.target : badge.progress;
  final remaining = badge.target - capped;

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
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
            color: cs.surfaceContainerLow.withValues(alpha: 0.9),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_rounded, size: 18, color: cs.tertiary),
                  const SizedBox(width: Gap.sm),
                  Text(
                    isUnknownUnlockTime(badge.unlockedAt)
                        ? 'Earned earlier'
                        : 'Earned on ${_formatDate(badge.unlockedAt!)}',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.tertiary),
                  ),
                ],
              )
            else ...[
              Semantics(
                label: '${badge.name} progress',
                value: '${(badge.ratio * 100).round()} percent',
                child: LinearProgressIndicator(
                  value: badge.ratio,
                  color: color,
                  backgroundColor: cs.surfaceContainerHighest,
                  minHeight: 7,
                ),
              ),
              const SizedBox(height: Gap.md),
              Row(
                children: [
                  Text(
                    '${_formatAmount(capped)} of ${_formatAmount(badge.target)}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const Spacer(),
                  Text(
                    '${_formatAmount(remaining)} to go',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
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

/// Drops the trailing `.0` that doubles carry for whole-number targets.
String _formatAmount(double value) => value == value.roundToDouble()
    ? '${value.toInt()}'
    : value.toStringAsFixed(1);