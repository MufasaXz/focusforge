import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/social.dart';
import '../../core/providers/social_providers.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/icon_badge.dart';
import 'settings_support.dart';

/// Weekly standings, three scopes deep.
///
/// The podium is the top three and nothing else — ranks four and below are a
/// plain list, because a podium that keeps going is just a chart with extra
/// steps. The user's own row is highlighted in both places so the answer to
/// "where am I?" never requires scanning.
///
/// "This week" is the Monday-aligned calendar week the dashboard's subject
/// rings and heatmap use — see [leaderboardWeekHoursProvider] — so the board
/// and the rest of the app count the same days. Only the user's row is
/// measured from real sessions; the rest are sample data until the backend
/// exists. The caption at the top says so, because a fake competitive standing
/// is worse than an honest sample board.
class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(leaderboardScopeProvider);
    final entries = ref.watch(leaderboardProvider);
    final me = ref.watch(myRankProvider);

    return AppPage(
      title: 'Leaderboard',
      subtitle: 'This week · ${entries.length} on the board',
      actions: [
        SegmentedButton<int>(
          segments: [
            for (var i = 0; i < LeaderboardScope.values.length; i++)
              ButtonSegment(
                value: i,
                label: Text(LeaderboardScope.values[i].label),
              ),
          ],
          selected: {scope.index},
          onSelectionChanged: (selection) => ref
              .read(leaderboardScopeProvider.notifier)
              .set(LeaderboardScope.values[selection.first]),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SampleBoardNote(),
          const SizedBox(height: Gap.lg),
          if (entries.length >= 3)
            _Podium(entries: entries.take(3).toList(growable: false)),
          if (entries.length > 3) ...[
            const SizedBox(height: Gap.xl),
            const SectionHeader(
              title: 'Standings',
              icon: Icons.format_list_numbered_rounded,
            ),
            _RankedList(entries: entries),
          ],
          const SizedBox(height: Gap.xl),
          const SectionHeader(
            title: 'Your rank',
            icon: Icons.military_tech_rounded,
          ),
          _MyRankCard(entries: entries, me: me),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sample-data note
// ---------------------------------------------------------------------------

/// The board mixes one measured row with seeded ones. Saying so costs a line
/// and is the honest alternative to a competitive standing the backend cannot
/// back up yet.
class _SampleBoardNote extends StatelessWidget {
  const _SampleBoardNote();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.md,
          vertical: Gap.md,
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(
                'Only your row is real. The other standings are sample data '
                'until the backend ships.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Podium
// ---------------------------------------------------------------------------

class _Podium extends StatelessWidget {
  const _Podium({required this.entries});

  /// Exactly three, ordered first to third.
  final List<LeaderboardEntry> entries;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card.filled(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.hero),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xl, Gap.md, Gap.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _PodiumPlace(
                entry: entries[1],
                place: 2,
                height: 64,
                accent: cs.primary,
              ),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: _PodiumPlace(
                entry: entries[0],
                place: 1,
                height: 92,
                accent: cs.tertiary,
              ),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: _PodiumPlace(
                entry: entries[2],
                place: 3,
                height: 52,
                accent: cs.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PodiumPlace extends StatelessWidget {
  const _PodiumPlace({
    required this.entry,
    required this.place,
    required this.height,
    required this.accent,
  });

  final LeaderboardEntry entry;
  final int place;
  final double height;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final top = place == 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (top) ...[
          Icon(Icons.workspace_premium_rounded, size: 18, color: accent),
          const SizedBox(height: 4),
        ],
        IconBadge(
          glyph: entry.initials,
          color: entry.isMe ? cs.primary : accent,
          size: top ? 54 : 44,
          radius: top ? 18 : 14,
          semanticLabel: entry.name,
        ),
        const SizedBox(height: Gap.sm),
        Text(
          entry.isMe ? 'You' : entry.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontSize: 11.5,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          formatHours(entry.hours),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: 10.5,
            color: accent,
          ),
        ),
        const SizedBox(height: Gap.sm),
        Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(Radii.tile),
            ),
            color: accent.withValues(alpha: 0.16),
            border: Border.all(color: accent.withValues(alpha: 0.45)),
          ),
          child: Center(
            child: Text(
              '$place',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: accent),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Ranked list
// ---------------------------------------------------------------------------

class _RankedList extends StatelessWidget {
  const _RankedList({required this.entries});

  final List<LeaderboardEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.xs),
        child: Column(
          children: [
            for (var i = 3; i < entries.length; i++)
              _RankRow(
                rank: i + 1,
                entry: entries[i],
                showDivider: i < entries.length - 1,
              ),
          ],
        ),
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.rank,
    required this.entry,
    required this.showDivider,
  });

  final int rank;
  final LeaderboardEntry entry;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMe = entry.isMe;
    final accent = cs.primary;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.xs, vertical: 2),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: Gap.md),
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '$rank',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: isMe ? accent : cs.onSurfaceVariant,
                    ),
                  ),
                ),
                IconBadge(
                  glyph: entry.initials,
                  color: isMe ? accent : cs.onSurfaceVariant,
                  size: 30,
                  radius: 10,
                ),
              ],
            ),
            title: Text(
              entry.isMe ? 'You' : entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: isMe ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            trailing: Text(
              formatHours(entry.hours),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: isMe ? accent : cs.onSurface,
              ),
            ),
            tileColor: isMe ? cs.primaryContainer : null,
          ),
        ),
        if (showDivider)
          Divider(height: 1, thickness: 1, color: cs.outlineVariant),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Your rank
// ---------------------------------------------------------------------------

class _MyRankCard extends StatelessWidget {
  const _MyRankCard({required this.entries, required this.me});

  final List<LeaderboardEntry> entries;
  final LeaderboardEntry? me;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mine = me;
    final leader = entries.isEmpty ? null : entries.first;

    if (mine == null || leader == null) {
      return Card.filled(
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Text(
            'Not on this board yet — finish a session to appear here.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    final rank = entries.indexWhere((e) => e.isMe) + 1;
    final behind = leader.hours - mine.hours;
    final isLeader = leader.isMe;

    final String message;
    if (isLeader && entries.length > 1) {
      final runnerUp = entries[1];
      message =
          'You lead ${runnerUp.name} by '
          '${formatHours(mine.hours - runnerUp.hours)}.';
    } else if (isLeader) {
      message = 'You are #1 this week.';
    } else {
      message = '${formatHours(behind)} behind ${leader.name}.';
    }

    // The old glass surface was elevated and accent-tinted; a tonal outline
    // carries the same "this one is different" cue without a glow.
    final progress = leader.hours <= 0
        ? 1.0
        : (mine.hours / leader.hours).clamp(0.0, 1.0);

    return Card.outlined(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(color: cs.primary),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconBadge(
                  icon: Icons.military_tech_rounded,
                  color: cs.primary,
                  size: 44,
                  radius: 14,
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '#$rank this week',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${formatHours(mine.hours)} of focused study',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.lg),
            Semantics(
              label: 'Progress toward first place',
              value: '${(progress * 100).round()} percent',
              child: LinearProgressIndicator(
                value: progress,
                color: cs.primary,
                backgroundColor: cs.surfaceContainerHighest,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: Gap.sm),
            Text(message, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}