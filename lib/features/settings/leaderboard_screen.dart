import '../../core/localization/app_strings.dart';
import '../../core/services/profile_photo.dart';
import '../../shared/widgets/glass_surface.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/icon_registry.dart';
import '../../core/models/social.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/community_safety.dart';
import '../../core/providers/social_providers.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/form_controls.dart';
import 'account_gate.dart';

/// The week, measured — against last week, and against everybody else on the
/// board who chose to be on it.
///
/// Two halves that answer different questions. The card at the top is the
/// comparison the app can always make, from the user's own session log. Below
/// it is the weekly board, which is a real read of real rows: an empty board
/// is shown as an empty board, because a fabricated rival is the one kind of
/// demo data a user cannot tell from the real thing.
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (ref.read(accountUidProvider) == null) return;
    ref.invalidate(weekBoardProvider);
    try {
      await ref.read(leaderboardPublisherProvider)();
      if (mounted) {
        await ref
            .read(weekBoardProvider.future)
            .timeout(const Duration(seconds: 12));
      }
    } catch (_) {
      // The read exposes its error and retries; sharing keeps its own queue.
    }
  }

  @override
  Widget build(BuildContext context) {
    final thisWeek = ref.watch(leaderboardWeekHoursProvider);
    final lastWeek = ref.watch(previousWeekHoursProvider);
    final sessions = ref.watch(weekSessionCountProvider);
    final signedIn = !ref.watch(userProvider).isAnonymous;

    // A row on the board has to belong to somebody, so the board itself is
    // behind a real account — the same gate study groups use.
    if (!signedIn) {
      return AppPage(
        title: context.tr("Leaderboard"),
        subtitle: context.tr("A week of focus, together"),
        child: AccountGate(
          title: context.tr("Sign in to see the board"),
          subtitle: context.tr(
            "Sign in to compare weekly focus time. Sharing your score is optional.",
          ),
          unlocked: context.tr("The weekly board is unlocked."),
          sectionTitle: context.tr("What the board adds"),
          items: [
            GateItem(
              Icons.leaderboard_rounded,
              context.tr("This week's standings"),
              context.tr("Everyone who opted in, best first"),
            ),
            GateItem(
              Icons.public_rounded,
              context.tr("Your row, your name"),
              context.tr("Share your name, level and this week's hours"),
            ),
          ],
        ),
      );
    }

    final board = ref.watch(leaderboardProvider);
    final myRow = ref.watch(myRankProvider);
    final optedIn = ref.watch(boardOptInProvider);
    final available = ref.watch(leaderboardServiceProvider).available;
    final boardState = ref.watch(weekBoardProvider);
    final loading = boardState.isLoading;
    final myIndex = board.indexWhere((entry) => entry.isMe);
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - now.weekday + 1);
    // A calendar step: six 24-hour days can land on Saturday across a
    // daylight-saving change.
    final sunday = DateTime(monday.year, monday.month, monday.day + 6);
    final dates = MaterialLocalizations.of(context);

    return AppPage(
      title: context.tr("Leaderboard"),
      onRefresh: _refresh,
      subtitle:
          '${dates.formatShortDate(monday)} – ${dates.formatShortDate(sunday)}',
      trailing: optedIn
          ? PopupMenuButton<String>(
              tooltip: context.tr("Sharing options"),
              onSelected: (_) async {
                try {
                  await ref.read(boardOptInProvider.notifier).set(false);
                } catch (_) {
                  if (context.mounted) {
                    showAppSnack(
                      context,
                      context.tr(
                        "Could not turn off sharing. Check your connection and retry.",
                      ),
                      danger: true,
                    );
                  }
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'off',
                  child: Text(context.tr("Turn off sharing")),
                ),
              ],
            )
          : null,
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
                context.tr("Weekly standings"),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (board.isNotEmpty)
                Text(
                  context.tr("{0} focusing", [board.length]),
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
              child: Padding(
                padding: const EdgeInsets.all(Gap.sm),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (boardState.hasError)
                      Padding(
                        padding: const EdgeInsets.all(Gap.lg),
                        child: Column(
                          children: [
                            Text(
                              context.tr(
                                "Could not load this week’s standings.",
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () =>
                                  ref.invalidate(weekBoardProvider),
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(context.tr("Try again")),
                            ),
                          ],
                        ),
                      )
                    else if (loading && board.isEmpty)
                      const _BoardLoading()
                    else if (board.isEmpty)
                      _EmptyBoard(optedIn: optedIn)
                    else ...[
                      // A podium needs a field to stand over; a board of one
                      // or two reads better as rows than as a stage of empty
                      // seats.
                      if (board.length >= 3) ...[
                        _Podium(entries: board.take(3).toList()),
                        const SizedBox(height: Gap.sm),
                        for (var i = 3; i < board.length; i++) ...[
                          if (i > 3)
                            const Divider(
                              height: 1,
                              indent: Gap.lg,
                              endIndent: Gap.lg,
                            ),
                          _BoardRowTile(
                            rank: i + 1,
                            entry: board[i],
                            leader: board.first.hours,
                          ),
                        ],
                      ] else
                        for (var i = 0; i < board.length; i++) ...[
                          if (i > 0)
                            const Divider(
                              height: 1,
                              indent: Gap.lg,
                              endIndent: Gap.lg,
                            ),
                          _BoardRowTile(
                            rank: i + 1,
                            entry: board[i],
                            leader: board.first.hours,
                          ),
                        ],
                    ],
                  ],
                ),
              ),
            ),
            if (!optedIn) const SizedBox(height: Gap.md),
            if (!optedIn)
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

/// The medal colours: gold, silver and bronze, pulled into the live theme.
///
/// They are categorical, like a subject's hue — they say "first", "second"
/// and "third" — so they are harmonised rather than turned into scheme roles.
Color _medal(int rank, ColorScheme cs) => harmonize(switch (rank) {
  1 => const Color(0xFFC9A227),
  2 => const Color(0xFF9AA5B1),
  _ => const Color(0xFFB87333),
}, cs.primary);

/// One row of the board. The user's own row is the one that has to be findable
/// at a glance, so it is the only one with an outline, in the theme's primary.
class _BoardRowTile extends StatelessWidget {
  const _BoardRowTile({
    required this.rank,
    required this.entry,
    required this.leader,
  });

  final int rank;
  final LeaderboardEntry entry;

  /// The leader's hours, which every row's bar is measured against.
  final double leader;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final compact =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 19;
    final muted = cs.onSurfaceVariant;
    final level = entry.level == null
        ? context.tr("Level unavailable")
        : context.tr("Level {0}", [entry.level]);
    final medal = rank <= 3 ? _medal(rank, cs) : null;
    final share = leader <= 0 ? 0.0 : (entry.hours / leader).clamp(0.0, 1.0);

    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.item),
        side: entry.isMe
            ? BorderSide(color: cs.primary, width: 1.5)
            : BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Gap.md,
        vertical: Gap.sm,
      ),
      tileColor: entry.isMe ? cs.surfaceContainerLow : null,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: context.tr("Rank {0}", [rank]),
            excludeSemantics: true,
            child: SizedBox(
              width: compact ? 30 : 34,
              height: 48,
              child: Center(
                child: medal == null
                    ? Text(
                        '$rank',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: muted,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      )
                    : Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: medal.withValues(alpha: .18),
                          border: Border.all(color: medal, width: 1.5),
                        ),
                        child: Text(
                          '$rank',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
              ),
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: Gap.sm),
            ExcludeSemantics(
              child: _BoardAvatar(
                entry: entry,
                radius: 19,
                style: theme.textTheme.labelMedium,
              ),
            ),
          ],
        ],
      ),
      title: Wrap(
        spacing: Gap.sm,
        runSpacing: Gap.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            entry.name,
            maxLines: compact ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (entry.isMe)
            DecoratedBox(
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
                  context.tr("You"),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onPrimary,
                    fontWeight: FontWeight.w700,
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
            // Narrow rows have no trailing column, so the hours get a line.
            if (compact)
              Text(
                formatHoursShort(entry.hours),
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            const SizedBox(height: Gap.sm),
            // The week against the leader's, as a thin bar: how far behind
            // is a length, read faster than a difference of two numbers.
            ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.pill),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: share),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : Motion.deliberate,
                  curve: Motion.emphasized,
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    minHeight: 4,
                    color: entry.isMe
                        ? cs.primary
                        : (medal ?? cs.onSurfaceVariant.withValues(alpha: .5)),
                    backgroundColor: cs.surfaceContainerHighest,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      trailing: compact
          ? null
          : Text(
              formatHoursShort(entry.hours),
              style: theme.textTheme.titleSmall?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
    );
  }
}

/// The top three on a stage: three risers, first place raised and centred,
/// second and third a step down on either side, each with its rank on the
/// riser and its person standing on top. A leaderboard with three identical
/// rows at the top reads as a list that happens to be sorted; a podium reads
/// as a finish.
class _Podium extends StatelessWidget {
  const _Podium({required this.entries});

  /// The leaders, already ordered — index 0 is first place.
  final List<LeaderboardEntry> entries;

  /// Riser heights by place: first, second, third.
  static const _heights = [92.0, 68.0, 52.0];

  @override
  Widget build(BuildContext context) {
    // Order the columns 2nd, 1st, 3rd so the winner sits in the middle.
    const order = [1, 0, 2];
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.lg, Gap.xs, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final i in order)
            Expanded(
              child: i < entries.length
                  ? _PodiumSeat(
                      rank: i + 1,
                      entry: entries[i],
                      riser: _heights[i],
                    )
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}

/// One podium seat: the person on top, the riser with its rank beneath.
class _PodiumSeat extends StatelessWidget {
  const _PodiumSeat({
    required this.rank,
    required this.entry,
    required this.riser,
  });

  final int rank;
  final LeaderboardEntry entry;
  final double riser;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final medal = _medal(rank, cs);
    final winner = rank == 1;
    final reduce = MediaQuery.disableAnimationsOf(context);

    // The risers grow from the floor, third first and the winner last, so
    // the stage builds up to first place.
    final grow = reduce
        ? Duration.zero
        : Duration(
            milliseconds:
                560 +
                (rank == 1
                    ? 260
                    : rank == 2
                    ? 130
                    : 0),
          );

    return Semantics(
      label: context.tr("Rank {0}", [rank]),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (winner)
            Icon(Icons.emoji_events_rounded, size: 22, color: medal)
          else
            const SizedBox(height: 22),
          const SizedBox(height: Gap.xs),
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: medal, width: winner ? 3 : 2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: _BoardAvatar(
                entry: entry,
                radius: winner ? 32 : 25,
                style: (winner ? tt.titleMedium : tt.titleSmall)?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: Gap.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
            child: Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: (winner ? tt.titleSmall : tt.labelLarge)?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            formatHoursShort(entry.hours),
            style: tt.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          // The user's own seat says so in a pill of its own, so a long
          // name can never truncate it away.
          if (entry.isMe) ...[
            const SizedBox(height: Gap.xs),
            DecoratedBox(
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.sm,
                  vertical: 1,
                ),
                child: Text(
                  context.tr("You"),
                  style: tt.labelSmall?.copyWith(
                    color: cs.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: Gap.sm),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: grow,
            curve: Motion.emphasized,
            builder: (context, t, _) => Container(
              height: riser * t,
              margin: const EdgeInsets.symmetric(horizontal: Gap.xs),
              alignment: Alignment.topCenter,
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  medal.withValues(alpha: .16),
                  cs.surfaceContainerHigh,
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(Radii.tile),
                ),
                border: Border(top: BorderSide(color: medal, width: 3)),
              ),
              child: t < .5
                  ? null
                  : Opacity(
                      opacity: ((t - .5) * 2).clamp(0.0, 1.0),
                      child: Padding(
                        padding: const EdgeInsets.only(top: Gap.sm),
                        child: Text(
                          '$rank',
                          style: tt.headlineSmall?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
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
            title: Text(context.tr("Share my weekly score")),
            subtitle: Text(
              optedIn
                  ? minutes <= 0
                        ? context.tr(
                            "On — your row appears after your first session",
                          )
                        : myRow == null
                        ? context.tr("On — publishing this week's hours")
                        : context.tr("On — {0} published", [
                            formatHoursShort(minutes / 60),
                          ])
                  : context.tr("Off — no score is published to this board"),
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
                    '${context.tr("Your display name, account ID, level and weekly focus time are visible to signed-in users when you opt in.")} '
                    '${context.tr("Your photo is backed up with your account and shared when leaderboard sharing is on.")}',
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
                  ? context.tr(
                      "Nobody else is on the board this week yet. Yours appears as soon as you log a session.",
                    )
                  : context.tr(
                      "Nobody is on the board this week yet. Turn the switch on and yours is the first row.",
                    ),
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
                context.tr(
                  "This build has no backend, so there is no board to read. Your own week above is measured here, on this device.",
                ),
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
              context.tr("YOUR WEEK"),
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
                      context.tr("focused this week"),
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // A place on the podium wears its medal here too.
                        if (standing != null && standing! <= 3) ...[
                          Icon(
                            Icons.workspace_premium_rounded,
                            size: 28,
                            color: _medal(standing!, cs),
                          ),
                          const SizedBox(width: Gap.xs),
                        ],
                        Text(
                          standing == null ? '—' : '#$standing',
                          style: Theme.of(context).textTheme.displaySmall
                              ?.copyWith(color: cs.primary),
                        ),
                      ],
                    ),
                    Text(
                      context.tr("your standing"),
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
              label: context.tr("This week against last week"),
              value: context.tr("{0} percent", [(progress * 100).round()]),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.pill),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : Motion.deliberate,
                  curve: Motion.emphasized,
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    color: cs.primary,
                    backgroundColor: cs.surfaceContainerHighest,
                    minHeight: 8,
                  ),
                ),
              ),
            ),
            const SizedBox(height: Gap.sm),
            Wrap(
              spacing: Gap.lg,
              runSpacing: Gap.sm,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Text(
                  sessions == 1
                      ? context.tr("1 session")
                      : context.tr("{0} sessions", [sessions]),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Text(
                  lastWeek > 0
                      ? context.tr("Last week {0}", [
                          formatHoursShort(lastWeek),
                        ])
                      : context.tr("A fresh start this week"),
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

/// A person's avatar on the board: their photo, else the symbol they chose,
/// else their initials, on the colour they chose.
///
/// With no colour chosen the board keeps its own: the accent for the
/// viewer's row, a quiet surface for everyone else's.
class _BoardAvatar extends StatelessWidget {
  const _BoardAvatar({
    required this.entry,
    required this.radius,
    required this.style,
  });

  final LeaderboardEntry entry;
  final double radius;

  /// The text style of the initials; its colour is set here.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chosen = entry.avatarColor;
    final color = chosen != null
        ? Color(chosen)
        : (entry.isMe ? cs.primary : cs.surfaceContainerHighest);
    // A chosen colour is free, so its ink is picked by its own lightness.
    final ink = chosen != null
        ? (color.computeLuminance() > 0.45 ? Colors.black87 : Colors.white)
        : (entry.isMe ? cs.onPrimary : cs.onSurfaceVariant);
    final photo = ProfilePhoto.bytes(entry.avatarPhoto);
    final icon = entry.avatarIcon;
    return CircleAvatar(
      radius: radius,
      foregroundImage: photo == null ? null : MemoryImage(photo),
      onForegroundImageError: photo == null ? null : (_, _) {},
      backgroundColor: color,
      foregroundColor: ink,
      child: icon != null
          ? Icon(AppIcons.resolve(icon), size: radius, color: ink)
          : Text(entry.initials, style: style?.copyWith(color: ink)),
    );
  }
}
