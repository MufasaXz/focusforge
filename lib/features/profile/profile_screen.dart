import '../../core/localization/app_strings.dart';
import '../../shared/widgets/glass_surface.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/shell/app_shell.dart';
import '../../app/theme/app_theme.dart';
import '../../core/app_version.dart';
import '../../core/models/user.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/shield_providers.dart';
import '../../core/providers/social_providers.dart';
import '../../core/providers/study_providers.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/icon_badge.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/stagger.dart';
import '../../shared/widgets/tonal_panel.dart';
import '../settings/account_gate.dart';
import '../settings/settings_support.dart';
import 'widgets/avatar_sheet.dart';
import 'widgets/edit_profile_sheet.dart';
import 'widgets/link_account_sheet.dart';

/// Shown on the About row. There is no `package_info` dependency in this app,
/// so the version is a shared constant — keep it in step with `pubspec.yaml`.
/// See `core/app_version.dart`.
const _appVersion = kAppVersion;

/// Opens a settings destination, asking for an account first when the row is
/// locked.
///
/// A locked row used to navigate to a screen whose whole content was "sign
/// in", which is a detour to reach a question that could be asked here. The
/// answer doubles as the navigation: link, then land where the tap was going.
Future<void> _openSetting(
  BuildContext context,
  WidgetRef ref,
  _SettingSpec spec,
) async {
  final route = spec.routeName;
  if (route == null) return;

  if (spec.locked) {
    final wants = await showAccountGateDialog(
      context,
      feature: spec.label,
      message: context.tr(
        "{0} compares you with other people, so it needs a real account. Linking one is instant and keeps everything you have already logged on this device.",
        [spec.label],
      ),
    );
    if (!wants || !context.mounted) return;

    final profile = await showLinkAccountSheet(context);
    if (profile == null || !context.mounted) return;
    await ref.read(userProvider.notifier).save(profile);
    if (!context.mounted) return;
    showAppSnack(
      context,
      ref.read(authServiceProvider).welcomeMessage(profile),
    );
  }

  if (context.mounted) context.goNamed(route);
}

/// `5h` for whole hours, `5.5h` otherwise — a raw double would render `5.0h`.
String _hours(double h) => h == h.roundToDouble()
    ? tr("{0}h", [h.round()])
    : tr("{0}h", [h.toStringAsFixed(1)]);

/// Tab 4 — identity, progression and settings.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).colorScheme;

    final user = ref.watch(userProvider);
    final stats = ref.watch(statsProvider);
    final streak = ref.watch(currentStreakProvider);
    final groups = ref.watch(groupsProvider);
    final achievements = ref.watch(achievementsProvider);
    final unlocked = ref.watch(unlockedCountProvider);
    final me = ref.watch(myRankProvider);
    final strict = ref.watch(strictModeProvider);
    // `valueOrNull`: a stream that errors — no rules published yet, no
    // connection — must leave this row without a trailing value rather than
    // throw out of the build and blank the whole tab.

    final standings = ref.watch(leaderboardProvider);
    final rankIndex = standings.indexWhere((e) => e.isMe);
    final rank = me == null || rankIndex < 0 ? null : rankIndex + 1;

    final theme = ref.watch(themeSettingsProvider);

    // Every row carries its own live value, so the list cannot drift from the
    // data the destination screens show. The value sits at the row's end, as
    // in a phone's own settings app, so each row is one line rather than two.
    final achievementsRow = _SettingSpec(
      icon: Icons.emoji_events_outlined,
      label: context.tr("Achievements"),
      routeName: AppRoutes.achievements,
      value: '$unlocked / ${achievements.length}',
    );
    final leaderboardRow = _SettingSpec(
      icon: Icons.leaderboard_outlined,
      label: context.tr("Leaderboard"),
      routeName: AppRoutes.leaderboard,
      value: rank == null ? null : '#$rank',
      locked: user.isAnonymous,
    );
    final groupsRow = _SettingSpec(
      icon: Icons.groups_outlined,
      label: context.tr("Study Groups"),
      routeName: AppRoutes.groups,
      value: user.isAnonymous
          ? null
          : context.tr("{0} active", [groups.length]),
      locked: user.isAnonymous,
    );
    final appearanceRow = _SettingSpec(
      icon: Icons.palette_outlined,
      label: context.tr("Appearance"),
      routeName: AppRoutes.appearance,
      value: context.tr(theme.palette.label),
    );
    final notificationsRow = _SettingSpec(
      icon: Icons.notifications_none_rounded,
      label: context.tr("Notifications"),
      routeName: AppRoutes.notifications,
    );
    final strictRow = _SettingSpec(
      icon: Icons.lock_outlined,
      label: context.tr("Strict Mode"),
      routeName: AppRoutes.strictMode,
      value: strict.isActive ? context.tr("On") : context.tr("Off"),
      valueColor: strict.isActive ? t.error : null,
    );
    final accessRow = _SettingSpec(
      icon: Icons.key_outlined,
      label: context.tr("App access"),
      routeName: AppRoutes.permissions,
    );
    final accountRow = _SettingSpec(
      icon: Icons.manage_accounts_outlined,
      label: context.tr("Account"),
      routeName: AppRoutes.privacy,
      value: user.isAnonymous
          ? context.tr("On this device")
          : context.tr("Linked"),
    );
    final aboutRow = _SettingSpec(
      icon: Icons.info_outlined,
      label: context.tr("About FocusForge"),
      routeName: AppRoutes.about,
      value: 'v$_appVersion',
    );

    // Three short groups instead of a card per topic. Appearance used to be
    // a tall card of its own here; it is one row now, and its controls live
    // on their own page.
    final progressGroup = (
      context.tr("Progress & community"),
      [achievementsRow, leaderboardRow, groupsRow],
    );
    final otherGroups = [
      (
        context.tr("Preferences"),
        [appearanceRow, notificationsRow, strictRow, accessRow],
      ),
      (context.tr("App & privacy"), [accountRow, aboutRow]),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= Layout.wide;

        // Stagger plays once per element lifetime. The tab's branch is built
        // the first time it is shown (go_router does not preload branches),
        // so the entrance lands on the first visit and never on a rebuild.
        //
        // Two counters when the columns are side by side, one when they are
        // stacked: the entrance is a single sweep down the page, so the
        // numbering follows the order the eye reads. Side by side, that is
        // the left column first.
        var index = 0;
        var prefIndex = 0;
        Widget stagger(Widget child) => Stagger(index: index++, child: child);
        Widget prefStagger(Widget child) =>
            Stagger(index: wide ? prefIndex++ : index++, child: child);

        Widget group((String, List<_SettingSpec>) g) => _SettingsGroup(
          title: g.$1,
          specs: g.$2,
          onOpen: (spec) => unawaited(_openSetting(context, ref, spec)),
        );

        // Identity and progress in one column, everything that is a setting
        // in the other. Stacked — which is every phone — it reads top to
        // bottom: who you are, how you are doing, then the settings.
        final identity = <Widget>[
          stagger(
            _HeroCard(
              user: user,
              stats: stats,
              streak: streak,
              unlocked: unlocked,
              totalBadges: achievements.length,
            ),
          ),
          const SizedBox(height: Gap.lg),
          if (user.isAnonymous) ...[
            stagger(const _AnonymousCard()),
            const SizedBox(height: Gap.lg),
          ],
          const SizedBox(height: Gap.sm),
          stagger(group(progressGroup)),
        ];

        final prefs = <Widget>[
          for (final g in otherGroups) prefStagger(group(g)),
        ];

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: wide ? Layout.readable * 2 + Gap.xl : Layout.readable,
            ),
            child: _TabEntrance(
              // The entrance waits for the branch to be on screen; see
              // [_TabEntrance]. Keyed so the motion-capture harness can grab
              // this vertical list directly.
              child: ListView(
                key: const ValueKey('profile-scroll'),
                padding: EdgeInsets.fromLTRB(
                  Gap.lg + 4,
                  MediaQuery.paddingOf(context).top + Gap.xl,
                  Gap.lg + 4,
                  kNavBarClearance,
                ),
                children: [
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: identity,
                          ),
                        ),
                        const SizedBox(width: Gap.xl),
                        Expanded(
                          child: Column(
                            key: const ValueKey('profile-settings'),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: prefs,
                          ),
                        ),
                      ],
                    )
                  else ...[
                    ...identity,
                    Column(
                      key: const ValueKey('profile-settings'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: prefs,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Identity, progression and the edit affordance.
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.user,
    required this.stats,
    required this.streak,
    required this.unlocked,
    required this.totalBadges,
  });

  final UserProfile user;
  final GamificationStats stats;

  /// Derived from the session log by `currentStreakProvider` — the stats
  /// aggregate carries no dates, so it cannot answer this.
  final int streak;

  final int unlocked;
  final int totalBadges;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Premium hero: a soft primary wash with a quiet lift, so the identity
        // card reads as the page's cover rather than another flat tile.
        return HeroSurface(
          key: const ValueKey('profile-hero'),
          accentStrength: 0.10,
          child: Column(
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Eyebrow(
                  context.tr("YOUR SPACE"),
                  icon: Icons.person_outline_rounded,
                ),
              ),
              const SizedBox(height: Gap.xl),
              // Avatar left, identity beside it, edit affordance on the right —
              // the arrangement the compact card reads best at. The only case
              // that still stacks is a viewport so narrow, or text so large,
              // that the name cannot share the row.
              // The level and its progress sit under the name, beside the
              // avatar, so the identity reads as one block rather than a
              // name floating over empty space.
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _Avatar(user: user, level: stats.level),
                  const SizedBox(width: Gap.lg),
                  Expanded(
                    child: _ProfileIdentity(user: user, stats: stats),
                  ),
                  const SizedBox(width: Gap.sm),
                  const _EditProfileButton(),
                ],
              ),
              const SizedBox(height: Gap.xl),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: t.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(Radii.item),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: Gap.lg,
                    horizontal: Gap.sm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _HeroStat(
                          value: _hours(stats.totalFocusHours),
                          label: context.tr("Total focus"),
                        ),
                      ),
                      _Divider(t: t),
                      Expanded(
                        child: _HeroStat(
                          value: '$streak',
                          label: context.tr("Day streak"),
                          accent: t.tertiary,
                        ),
                      ),
                      _Divider(t: t),
                      Expanded(
                        child: _HeroStat(
                          value: '$unlocked/$totalBadges',
                          label: context.tr("Badges"),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProfileIdentity extends StatelessWidget {
  const _ProfileIdentity({required this.user, required this.stats});

  final UserProfile user;
  final GamificationStats stats;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          user.displayName.trim().isEmpty
              ? context.tr("Your profile")
              : user.displayName,
          style: tt.headlineSmall?.copyWith(
            letterSpacing: -.8,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: Gap.sm),
        // A wrap, not a row: at large text sizes the XP falls under the
        // level instead of pushing past the edge of the card.
        // The level at the start of the bar and the XP at its end, so the two
        // read as the bar's own labels rather than one crowded phrase. A wrap
        // still, so at large text the XP drops under the level.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: Gap.lg,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // One run of text with the icon inline, so it wraps like text.
            Text.rich(
              TextSpan(
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(end: Gap.xs),
                      child: Icon(
                        Icons.military_tech_rounded,
                        size: 16,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  TextSpan(text: context.tr("Level {0}", [stats.level])),
                ],
              ),
              style: tt.labelLarge?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              stats.isMaxLevel
                  ? context.tr("{0} XP · Max level", [stats.xp])
                  : context.tr("{0} / {1} XP", [stats.xp, stats.xpForNext]),
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: Gap.sm),
        Semantics(
          label: stats.isMaxLevel
              ? context.tr("Level {0}, maximum level. {1} XP", [
                  stats.level,
                  stats.xp,
                ])
              : context.tr("Level {0}, {1} of {2} XP", [
                  stats.level,
                  stats.xp,
                  stats.xpForNext,
                ]),
          value: context.tr("{0} percent", [
            (stats.levelProgress * 100).round(),
          ]),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: stats.levelProgress),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : Motion.deliberate,
              curve: Motion.emphasized,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                color: cs.primary,
                backgroundColor: cs.surfaceContainerHighest,
                minHeight: 6,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The avatar, and the way to change it.
///
/// The tap target is the disc itself rather than a row in a menu: it is the
/// one thing on this page that is obviously about the user, and a pencil in
/// its corner is the standard way of saying so.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.user, required this.level});

  final UserProfile user;
  final int level;

  // No pencil of its own: the profile has one way in, the Edit button, and
  // the avatar opens the same editor, where the name and the avatar change
  // together.
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: context.tr("Edit profile"),
    child: ExcludeSemantics(
      child: Pressable(
        onTap: () => showEditProfileSheet(context),
        scale: 0.94,
        child: AvatarDisc(user: user, size: 74, level: level),
      ),
    ),
  );
}

class _EditProfileButton extends StatelessWidget {
  const _EditProfileButton();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).colorScheme;
    void open() => showEditProfileSheet(context);

    return Semantics(
      button: true,
      label: context.tr("Edit profile"),
      excludeSemantics: true,
      onTap: open,
      child: Pressable(
        onTap: open,
        child: SizedBox.square(
          dimension: 48,
          child: Center(
            child: IconBadge(
              icon: Icons.edit_rounded,
              color: t.primary,
              size: 36,
              radius: 11,
            ),
          ),
        ),
      ),
    );
  }
}

/// Honest state for a device-only account: what works, what does not, and the
/// one action that changes it.
class _AnonymousCard extends ConsumerWidget {
  const _AnonymousCard();

  /// Opens the provider choice and adopts whatever credential comes back.
  ///
  /// There is no in-flight state on this button. The sheet is modal, so a
  /// second tap cannot reach the card while it is open, and the row that is
  /// actually working carries its own spinner — a button spinning behind a
  /// barrier would say the same thing twice and never stop saying it.
  Future<void> _link(BuildContext context, WidgetRef ref) async {
    // Captured before the await: linking replaces this card, so by the time
    // the sheet returns the context below it is gone.
    final messenger = ScaffoldMessenger.of(context);
    final strings = AppStrings.of(context);
    final profile = await showLinkAccountSheet(context);
    if (profile == null || !context.mounted) return;
    await ref.read(userProvider.notifier).save(profile);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          strings.text(
            "{0} Your focus history is ready. Study groups are now available.",
            [ref.read(authServiceProvider).welcomeMessage(profile)],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // One line of state and one action. The full account story lives on the
    // Account screen; here it only has to say what is missing and fix it.
    return ContentCard(
      color: Color.alphaBlend(
        t.primary.withValues(alpha: .06),
        t.surfaceContainerLow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconBadge(
                  icon: Icons.smartphone_rounded,
                  color: t.primary,
                  size: _SettingTile.badge,
                  radius: Radii.tile - 2,
                ),
                const SizedBox(width: Gap.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr("Local account"), style: tt.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        context.tr(
                          "Study groups and the leaderboard need a linked account.",
                        ),
                        style: tt.bodySmall?.copyWith(
                          color: t.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.md),
            // No Semantics wrapper: a button already announces itself and
            // takes its name from its label. A non-container wrapper would be
            // absorbed by the card's node and turn the whole card into one
            // button named after every word on it.
            FilledButton.tonalIcon(
              onPressed: () => unawaited(_link(context, ref)),
              icon: const Icon(Icons.link_rounded, size: 18),
              label: Text(context.tr("Link an account")),
            ),
          ],
        ),
      ),
    );
  }
}

/// A quiet label over one rounded group of rows — the inset-grouped list
/// that a phone's own settings app uses.
///
/// The label sits outside the card and carries no icon: every row already has
/// one, and a second glyph in the heading was a third thing to read before
/// the first setting.
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.title,
    required this.specs,
    required this.onOpen,
  });

  final String title;
  final List<_SettingSpec> specs;
  final ValueChanged<_SettingSpec> onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              Gap.lg,
              0,
              Gap.lg,
              Gap.sm,
            ),
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ),
          ContentCard(
            child: Column(
              children: [
                for (final (i, spec) in specs.indexed) ...[
                  if (i > 0)
                    Divider(
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                      height: 1,
                      // Starts under the label, not under the icon, so the
                      // icons read as one column.
                      indent: Gap.lg + _SettingTile.badge + Gap.lg,
                    ),
                  _SettingTile(spec: spec, onTap: () => onOpen(spec)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One navigable settings row, described as data so the list stays readable.
class _SettingSpec {
  const _SettingSpec({
    required this.icon,
    required this.label,
    this.routeName,
    this.value,
    this.valueColor,
    this.locked = false,
  });

  final IconData icon;
  final String label;
  final String? routeName;

  /// The current state, shown at the row's end ("On", "#4", "v1.0.6").
  final String? value;
  final Color? valueColor;

  /// Marks a destination that needs a linked account, without hiding it.
  final bool locked;
}

/// A single-line row: icon, name, current value, chevron.
///
/// Built by hand rather than as a [ListTile] because a tile's trailing slot
/// is unconstrained: a long translated value ("Auf diesem Gerät") would push
/// the title off the row instead of giving way to it.
class _SettingTile extends StatelessWidget {
  const _SettingTile({required this.spec, required this.onTap});

  final _SettingSpec spec;
  final VoidCallback onTap;

  /// Side of the leading icon badge.
  static const double badge = 36;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return MergeSemantics(
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          // 56 dp rows: comfortably past the 48 dp target, and short enough
          // that the whole list fits on one screen of a phone.
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              Gap.lg,
              Gap.sm,
              Gap.md,
              Gap.sm,
            ),
            // The value gets at most half the row and gives way first, so
            // the title is never cut while a value is shown in full, and the
            // chevron always ends the row at the same x.
            child: LayoutBuilder(
              builder: (context, box) => Row(
                children: [
                  IconBadge(
                    icon: spec.icon,
                    color: t.primary,
                    size: badge,
                    radius: Radii.tile - 2,
                  ),
                  const SizedBox(width: Gap.lg),
                  Expanded(child: Text(spec.label, style: tt.titleSmall)),
                  if (spec.value != null) ...[
                    const SizedBox(width: Gap.sm),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: box.maxWidth / 2.4),
                      child: Text(
                        spec.value!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: tt.bodyMedium?.copyWith(
                          color: spec.valueColor ?? t.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                  if (spec.locked) ...[
                    const SizedBox(width: Gap.sm),
                    Icon(
                      Icons.lock_outlined,
                      size: 16,
                      color: t.onSurfaceVariant,
                      semanticLabel: context.tr(
                        "Study groups and the leaderboard need a linked account.",
                      ),
                    ),
                  ],
                  const SizedBox(width: Gap.xs),
                  const AppChevron(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label, this.accent});

  final String value;
  final String label;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: accent ?? t.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.t});

  final ColorScheme t;

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 30, color: t.outlineVariant);
}

/// Holds a screen's staggered entrance until its tab is actually on screen.
///
/// The shell keeps every visited tab mounted in an `IndexedStack`, and
/// go_router wraps the inactive branches in a disabled [TickerMode]. A
/// [Stagger] starts its delay clock in `initState`, so a tree that is built
/// before the branch is shown plays its entrance to an empty room and the user
/// sees nothing move when they switch in. Deferring the first build until the
/// ticker mode is enabled starts the clock on the frame the tab first appears;
/// the flag latches, so a later switch back does not replay the entrance.
class _TabEntrance extends StatefulWidget {
  const _TabEntrance({required this.child});

  final Widget child;

  @override
  State<_TabEntrance> createState() => _TabEntranceState();
}

class _TabEntranceState extends State<_TabEntrance> {
  bool _entered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `TickerMode.valuesOf` registers a dependency on the branch's on-stage
    // state, so this runs again the moment the tab is switched in. No setState:
    // the framework rebuilds immediately after this call.
    if (!_entered && TickerMode.valuesOf(context).enabled) _entered = true;
  }

  @override
  Widget build(BuildContext context) {
    // Checked here as well as in `didChangeDependencies`, and checked on every
    // build. This widget hides its entire child until the branch is on stage,
    // so anything that went wrong with the notification would not be a late
    // animation — it would be a blank tab, which is what a user would report
    // as "a white screen". Reading the value during build costs nothing and
    // makes the blank state impossible to reach while the tab is visible.
    if (!_entered && TickerMode.valuesOf(context).enabled) _entered = true;
    return _entered ? widget.child : const SizedBox.shrink();
  }
}
