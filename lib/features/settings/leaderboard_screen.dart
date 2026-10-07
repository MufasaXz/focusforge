import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/social.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/social_providers.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/empty_state.dart';
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
        title: 'Your week',
        subtitle: 'A real account is required',
        child: const AccountGate(
          title: 'Sign in to see the board',
          subtitle:
              'The weekly board compares you with other people, so it needs a '
              'real account. Your own week above stays on this device either '
              'way.',
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
              'Only your name and this week\'s hours are published',
            ),
          ],
        ),
      );
    }

    final board = ref.watch(leaderboardProvider);
    final myRow = ref.watch(myRankProvider);
    final optedIn = ref.watch(boardOptInProvider);
    final available = ref.watch(leaderboardServiceProvider).available;
    final loading = ref.watch(weekBoardProvider).isLoading;

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
            title: 'This week\'s board',
            icon: Icons.leaderboard_rounded,
          ),
          if (!available)
            const _NoBackendCard()
          else ...[
            if (loading && board.isEmpty)
              const _BoardLoading()
            else if (board.isEmpty)
              _EmptyBoard(optedIn: optedIn)
            else
              for (var i = 0; i < board.length; i++) ...[
                if (i > 0) const SizedBox(height: Gap.sm),
                _BoardRowTile(
                  rank: i + 1,
                  entry: board[i],
                  accent: SubjectPalette.harmonized(
                    Theme.of(context).colorScheme.primary,
                  )[i % SubjectPalette.count],
                ),
              ],
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
  const _BoardRowTile({
    required this.rank,
    required this.entry,
    required this.accent,
  });

  final int rank;
  final LeaderboardEntry entry;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Card.filled(
      color: entry.isMe ? cs.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.lg,
          vertical: Gap.md,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '$rank',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: entry.isMe ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: Gap.sm),
            CircleAvatar(
              radius: 16,
              backgroundColor: accent.withValues(alpha: 0.22),
              child: Text(
                entry.initials,
                style: theme.textTheme.labelMedium?.copyWith(color: accent),
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(
                entry.isMe ? '${entry.name} (you)' : entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: entry.isMe ? cs.onPrimaryContainer : null,
                ),
              ),
            ),
            Text(
              formatHoursShort(entry.hours),
              style: theme.textTheme.titleSmall?.copyWith(
                color: entry.isMe ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
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

    return Card.outlined(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          SwitchListTile.adaptive(
            value: optedIn,
            title: const Text('Appear on the board'),
            subtitle: Text(
              optedIn
                  ? minutes <= 0
                        ? 'On — your row appears after your first session'
                        : myRow == null
                        ? 'On — publishing this week\'s hours'
                        : 'On — ${formatHoursShort(minutes / 60)} published'
                  : 'Off — nothing about your week leaves this device',
            ),
            onChanged: (value) =>
                ref.read(boardOptInProvider.notifier).set(value),
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
                    'A row is your name and this week\'s hours. Not your '
                    'subjects, not your sessions, not what you studied.',
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
    return Card.filled(
      child: Padding(
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
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardLoading extends StatelessWidget {
  const _BoardLoading();

  @override
  Widget build(BuildContext context) {
    return const Card.filled(
      child: Padding(
        padding: EdgeInsets.all(Gap.xl),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
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
    return Card.filled(
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
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
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
