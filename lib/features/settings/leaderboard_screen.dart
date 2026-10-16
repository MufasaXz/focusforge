import '../../shared/widgets/glass_surface.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/social.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/community_providers.dart';
import '../../shared/widgets/community_safety.dart';
import '../../core/providers/social_providers.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/app_page.dart';
import 'account_gate.dart';

/// The week, measured — against last week, and against everybody else on the
/// board who chose to be on it.
///
/// Two halves that answer different questions. The card at the top is the
/// comparison the app can always make, from the user's own session log. Below
/// it is the weekly board, which is a real read of real rows: an empty board
/// is shown as an empty board, because a fabricated rival is the one kind of
/// demo data a user cannot tell from the real thing.
class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thisWeek = ref.watch(leaderboardWeekHoursProvider);
    final lastWeek = ref.watch(previousWeekHoursProvider);
    final sessions = ref.watch(weekSessionCountProvider);
    final signedIn = !ref.watch(userProvider).isAnonymous;

    // A row on the board has to belong to somebody, so the board itself is
    // behind a real account — the same gate study groups use.
    if (!signedIn) {
      return AppPage(
        title: 'Leaderboard',
        subtitle: 'A week of focus, together',
        child: const AccountGate(
          title: 'Sign in to see the board',
          subtitle: 'Sign in to compare weekly focus time. Sharing your score is optional.',
          unlocked: 'The weekly board is unlocked.',
          sectionTitle: 'What the board adds',
          items: [
            GateItem(
              Icons.leaderboard_rounded,
              'This week\'s standings',
              'Everyone who opted in, best first',
            ),
            GateItem(
              Icons.public_rounded,
              'Your row, your name',
              'Share your name, level and this week\'s hours',
            ),
          ],
        ),
      );
    }

    final hidden = ref.watch(blockedCommunityUsersProvider);
    final board = [
      for (final entry in ref.watch(leaderboardProvider))
        if (!hidden.contains(entry.uid)) entry,
    ];
    final myRow = ref.watch(myRankProvider);
    final optedIn = ref.watch(boardOptInProvider);
    final available = ref.watch(leaderboardServiceProvider).available;
    final boardState = ref.watch(weekBoardProvider);
    final loading = boardState.isLoading;
    final myIndex = board.indexWhere((entry) => entry.isMe);
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - now.weekday + 1);
    final sunday = monday.add(const Duration(days: 6));
    final dates = MaterialLocalizations.of(context);

    return AppPage(
      title: 'Leaderboard',
      subtitle:
          '${dates.formatShortDate(monday)} – ${dates.formatShortDate(sunday)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WeekCard(
            thisWeek: thisWeek,
            lastWeek: lastWeek,
            sessions: sessions,
            standing: myIndex < 0 ? null : myIndex + 1,
          ),
          const SizedBox(height: Gap.xl),
          Wrap(
            spacing: Gap.md,
            runSpacing: Gap.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(
                'Weekly standings',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (board.isNotEmpty)
                Text(
                  '${board.length} focusing',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: Gap.md),
          if (!available)
            const _NoBackendCard()
          else ...[
            ContentCard(
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (boardState.hasError)
                    Padding(
                      padding: const EdgeInsets.all(Gap.lg),
                      child: Column(
                        children: [
                          const Text('Could not load this week’s standings.'),
                          TextButton.icon(
                            onPressed: () => ref.invalidate(weekBoardProvider),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Try again'),
                          ),
                        ],
                      ),
                    )
                  else if (loading && board.isEmpty)
                    const _BoardLoading()
                  else if (board.isEmpty)
                    _EmptyBoard(optedIn: optedIn)
                  else
                    for (var i = 0; i < board.length; i++) ...[
                      if (i > 0)
                        const Divider(
                          height: 1,
                          indent: Gap.lg,
                          endIndent: Gap.lg,
                        ),
                      _BoardRowTile(rank: i + 1, entry: board[i]),
                    ],
                ],
              ),
            ),
            const SizedBox(height: Gap.md),
            _BoardSwitch(
              optedIn: optedIn,
              myRow: myRow,
              minutes: (thisWeek * 60).round(),
            ),
          ],
        ],
      ),
    );
  }
}

/// One row of the board. The user's own row is the one that has to be findable
/// at a glance, so it is the only one that gets a fill.
class _BoardRowTile extends StatelessWidget {
  const _BoardRowTile({required this.rank, required this.entry});

  final int rank;
  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final compact =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 19;
    final foreground = entry.isMe ? cs.onPrimaryContainer : cs.onSurface;
    final muted = entry.isMe ? cs.onPrimaryContainer : cs.onSurfaceVariant;
    final level = entry.level == null
        ? 'Level unavailable'
        : 'Level ${entry.level}';
    final menu = !entry.isMe && entry.uid.isNotEmpty
        ? CommunityMemberMenu(uid: entry.uid, name: entry.name)
        : null;
    final medal = switch (rank) {
      1 => harmonize(const Color(0xFFB8860B), cs.primary),
      2 => cs.secondary,
      3 => cs.tertiary,
      _ => cs.onSurfaceVariant,
    };

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Gap.md,
        vertical: Gap.sm,
      ),
      tileColor: entry.isMe
          ? cs.primaryContainer
          : rank == 1
          ? Color.alphaBlend(
              cs.primary.withValues(alpha: .04),
              cs.surfaceContainerLow,
            )
          : null,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: 'Rank $rank',
            excludeSemantics: true,
            child: Container(
              width: compact ? 32 : 38,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: rank <= 3 ? medal.withValues(alpha: .12) : null,
                borderRadius: BorderRadius.circular(Radii.tile),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (rank <= 3 && !compact)
                    Icon(
                      Icons.workspace_premium_rounded,
                      size: 15,
                      color: medal,
                    ),
                  Text(
                    '$rank',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: rank <= 3 ? medal : cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: Gap.sm),
            ExcludeSemantics(
              child: CircleAvatar(
                radius: 19,
                backgroundColor: entry.isMe
                    ? cs.primary
                    : cs.surfaceContainerHighest,
                foregroundColor: entry.isMe
                    ? cs.onPrimary
                    : cs.onSurfaceVariant,
                child: Text(
                  entry.initials,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: entry.isMe ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            entry.name,
            maxLines: compact ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (entry.isMe)
            Padding(
              padding: const EdgeInsets.only(top: Gap.xs),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Gap.sm,
                    vertical: 2,
                  ),
                  child: Text(
                    'You',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: Gap.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              level,
              style: theme.textTheme.labelMedium?.copyWith(color: muted),
            ),
            if (compact)
              Text(
                formatHoursShort(entry.hours),
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
          ],
        ),
      ),
      trailing: compact
          ? menu
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatHoursShort(entry.hours),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: foreground,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                ?menu,
              ],
            ),
    );
  }
}

/// The switch that puts this device on the board.
///
/// The state of the row is spelled out rather than implied: a user who has
/// opted in and studied nothing yet has no row, and "on" with no row would
/// otherwise look like a bug.
class _BoardSwitch extends ConsumerWidget {
  const _BoardSwitch({
    required this.optedIn,
    required this.myRow,
    required this.minutes,
  });

  final bool optedIn;
  final LeaderboardEntry? myRow;
  final int minutes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ContentCard(
      child: Column(
        children: [
          SwitchListTile.adaptive(
            value: optedIn,
            title: const Text('Share my weekly score'),
            subtitle: Text(
              optedIn
                  ? minutes <= 0
                        ? 'On — your row appears after your first session'
                        : myRow == null
                        ? 'On — publishing this week\'s hours'
                        : 'On — ${formatHoursShort(minutes / 60)} published'
                  : 'Off — no score is published to this board',
            ),
            onChanged: (value) async {
              if (value && !await confirmCommunityTerms(context)) return;
              await ref.read(boardOptInProvider.notifier).set(value);
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    'Your display name, account ID, level and weekly focus time '
                    'are visible to signed-in users when you opt in.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// An empty board is a state, not a failure: nobody has opted in yet.
class _EmptyBoard extends StatelessWidget {
  const _EmptyBoard({required this.optedIn});

  final bool optedIn;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(Gap.lg),
      child: Row(
        children: [
          Icon(
            Icons.people_outline_rounded,
            size: 20,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Text(
              optedIn
                  ? 'Nobody else is on the board this week yet. Yours '
                        'appears as soon as you log a session.'
                  : 'Nobody is on the board this week yet. Turn the switch '
                        'on and yours is the first row.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardLoading extends StatelessWidget {
  const _BoardLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(Gap.xl),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

/// Shown when the build has no backend at all — the web preview, or a phone
/// where Firebase could not start.
class _NoBackendCard extends StatelessWidget {
  const _NoBackendCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ContentCard(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.cloud_off_rounded, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(
                'This build has no backend, so there is no board to read. '
                'Your own week above is measured here, on this device.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
              ),
            ),
          ],
        ),
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
    this.standing,
  });

  final double thisWeek;
  final double lastWeek;
  final int sessions;
  final int? standing;

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

    return ContentCard(
      key: const ValueKey('leaderboard-week'),
      color: Color.alphaBlend(
        cs.primary.withValues(alpha: .09),
        cs.surfaceContainerLow,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.hero),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'YOUR WEEK',
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: cs.onSurfaceVariant, letterSpacing: 1.2),
            ),
            const SizedBox(height: Gap.md),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: Gap.xl,
              runSpacing: Gap.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Column(
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
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      standing == null ? '—' : '#$standing',
                      style: Theme.of(context).textTheme.displaySmall
                          ?.copyWith(color: cs.primary),
                    ),
                    Text(
                      'your standing',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
            if (lastWeek > 0) ...[
              const SizedBox(height: Gap.sm),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Chip(
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
              ),
            ],
            const SizedBox(height: Gap.md),
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
            Wrap(
              spacing: Gap.lg,
              runSpacing: Gap.sm,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Text(
                  sessions == 1 ? '1 session' : '$sessions sessions',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Text(
                  lastWeek > 0
                      ? 'Last week ${formatHoursShort(lastWeek)}'
                      : 'A fresh start this week',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
