import '../../core/localization/app_strings.dart';
import '../../core/services/profile_photo.dart';
import '../../shared/widgets/glass_surface.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
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
    final sunday = monday.add(const Duration(days: 6));
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
                      // The podium: the three leaders get a stage, the rest
                      // read as the standings they are.
                      _Podium(entries: board.take(3).toList()),
                      if (board.length > 3) ...[
                        const SizedBox(height: Gap.sm),
                        for (var i = 3; i < board.length; i++) ...[
                          if (i > 3)
                            const Divider(
                              height: 1,
                              indent: Gap.lg,
                              endIndent: Gap.lg,
                            ),
                          _BoardRowTile(rank: i + 1, entry: board[i]),
                        ],
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

/// One row of the board. The user's own row is the one that has to be findable
/// at a glance, so it is the only one that gets a gold outline.
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
    final foreground = cs.onSurface;
    final muted = cs.onSurfaceVariant;
    final photoBytes = ProfilePhoto.bytes(entry.avatarPhoto);
    final level = entry.level == null
        ? context.tr("Level unavailable")
        : context.tr("Level {0}", [entry.level]);
    final medal = switch (rank) {
      1 => harmonize(const Color(0xFFB8860B), cs.primary),
      2 => cs.secondary,
      3 => cs.tertiary,
      _ => cs.onSurfaceVariant,
    };

    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.item),
        side: entry.isMe
            ? BorderSide(color: const Color(0xFFD6AD43), width: 1.5)
            : BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Gap.md,
        vertical: Gap.sm,
      ),
      tileColor: entry.isMe
          ? cs.surfaceContainerLow
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
            label: context.tr("Rank {0}", [rank]),
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
                foregroundImage: photoBytes == null
                    ? null
                    : MemoryImage(photoBytes),
                onForegroundImageError: photoBytes == null ? null : (_, _) {},
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
                    context.tr("You"),
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
          ? null
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
              ],
            ),
    );
  }
}

/// The top three, on a stage: first place raised and centred, second and
/// third a step down on either side. A leaderboard with three identical rows
/// at the top reads as a list that happens to be sorted; a podium reads as a
/// finish. Fewer than three entries simply take the seats that exist.
class _Podium extends StatelessWidget {
  const _Podium({required this.entries});

  /// The leaders, already ordered — index 0 is first place.
  final List<LeaderboardEntry> entries;

  @override
  Widget build(BuildContext context) {
    // Order the columns 2nd, 1st, 3rd so the winner sits in the middle, and
    // pull the seats that are not there from either end.
    final order = <int?>[1, 0, 2];
    return Padding(
      padding: const EdgeInsets.only(top: Gap.md, bottom: Gap.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final i in order)
            Expanded(
              child: i != null && i < entries.length
                  ? _PodiumSeat(rank: i + 1, entry: entries[i])
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}

/// One podium seat: the avatar on its riser, the name and hours beneath.
class _PodiumSeat extends StatelessWidget {
  const _PodiumSeat({required this.rank, required this.entry});

  final int rank;
  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final photoBytes = ProfilePhoto.bytes(entry.avatarPhoto);
    final medal = switch (rank) {
      1 => harmonize(const Color(0xFFB8860B), cs.primary),
      2 => cs.secondary,
      _ => cs.tertiary,
    };
    final winner = rank == 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: medal,
                  width: winner ? 3 : 2,
                ),
                boxShadow: winner
                    ? [
                        BoxShadow(
                          color: medal.withValues(alpha: 0.45),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: CircleAvatar(
                radius: winner ? 34 : 26,
                foregroundImage: photoBytes == null
                    ? null
                    : MemoryImage(photoBytes),
                onForegroundImageError: photoBytes == null ? null : (_, _) {},
                backgroundColor:
                    entry.isMe ? cs.primary : cs.surfaceContainerHighest,
                foregroundColor:
                    entry.isMe ? cs.onPrimary : cs.onSurfaceVariant,
                child: Text(
                  entry.initials,
                  style: (winner ? tt.titleMedium : tt.titleSmall)?.copyWith(
                    color: entry.isMe ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            // The medal hangs off the bottom of the ring like a real one.
            Positioned(
              bottom: winner ? -6 : -5,
              child: Container(
                width: winner ? 26 : 21,
                height: winner ? 26 : 21,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: medal,
                  border: Border.all(color: cs.surface, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$rank',
                  style: tt.labelSmall?.copyWith(
                    color: cs.surface,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.lg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
          child: Text(
            entry.isMe ? '${entry.name} · You' : entry.name,
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
            color: medal,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
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
                    Text(
                      standing == null ? '—' : '#$standing',
                      style: Theme.of(context).textTheme.displaySmall
                          ?.copyWith(color: cs.primary),
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
