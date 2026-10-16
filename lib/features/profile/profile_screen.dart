import '../../core/localization/app_strings.dart';
import '../../shared/widgets/glass_surface.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/shell/app_shell.dart';
import '../../app/theme/app_theme.dart';
import '../../core/models/user.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/shield_providers.dart';
import '../../core/providers/social_providers.dart';
import '../../core/providers/study_providers.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/app_segmented_control.dart';
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
/// so the version is a constant — keep it in step with `pubspec.yaml`.
const _appVersion = '1.0.0';

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

    // Every row carries its own live trailing value, so the list cannot drift
    // from the data the destination screens show.
    final settings = <_SettingSpec>[
      _SettingSpec(
        icon: Icons.groups_outlined,
        label: context.tr("Study Groups"),
        routeName: AppRoutes.groups,
        trailing: context.tr("{0} active", [groups.length]),
        locked: user.isAnonymous,
      ),
      _SettingSpec(
        icon: Icons.emoji_events_outlined,
        label: context.tr("Achievements"),
        routeName: AppRoutes.achievements,
        trailing: '$unlocked / ${achievements.length}',
      ),
      _SettingSpec(
        icon: Icons.leaderboard_outlined,
        label: context.tr("Leaderboard"),
        routeName: AppRoutes.leaderboard,
        trailing: rank == null ? null : '#$rank',
        locked: user.isAnonymous,
      ),
      _SettingSpec(
        icon: Icons.lock_outlined,
        label: context.tr("Strict Mode"),
        routeName: AppRoutes.strictMode,
        trailing: strict.enabled ? 'On' : context.tr("Off"),
        trailingColor: strict.enabled ? t.error : null,
      ),
      _SettingSpec(
        icon: Icons.notifications_active_outlined,
        label: context.tr("Notifications"),
        routeName: AppRoutes.notifications,
      ),
      _SettingSpec(
        icon: Icons.key_outlined,
        label: context.tr("App access"),
        routeName: AppRoutes.permissions,
        trailing: context.tr("Manage"),
      ),
      _SettingSpec(
        icon: Icons.manage_accounts_outlined,
        label: context.tr("Account"),
        routeName: AppRoutes.privacy,
        trailing: user.isAnonymous
            ? context.tr("On this device")
            : context.tr("Linked"),
      ),
      _SettingSpec(
        icon: Icons.info_outlined,
        label: context.tr("About FocusForge"),
        routeName: AppRoutes.about,
        trailing: 'v$_appVersion',
      ),
    ];

    final wide = MediaQuery.sizeOf(context).width >= Layout.wide;

    // Stagger plays once per element lifetime. The tab's branch is built the
    // first time it is shown (go_router does not preload branches), so the
    // entrance lands on the first visit and never on a rebuild.
    //
    // Two counters when the columns are side by side, one when they are
    // stacked: the entrance is a single sweep down the page, so the numbering
    // has to follow the order the eye reads rather than the order the code
    // builds. Side by side, that is the left column first.
    var index = 0;
    var prefIndex = 0;
    Widget stagger(Widget child) => Stagger(index: index++, child: child);
    Widget prefStagger(Widget child) =>
        Stagger(index: wide ? prefIndex++ : index++, child: child);

    // Identity and progress in one column, everything that is a setting in the
    // other. Stacked — which is every phone — it is the same page it has
    // always been, in the same order.
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
    ];

    final prefs = <Widget>[
      prefStagger(
        SectionHeader(
          title: context.tr("Appearance"),
          icon: Icons.palette_outlined,
        ),
      ),
      prefStagger(const _AppearanceCard()),
      const SizedBox(height: Gap.xl),
      for (final group in [
        (context.tr("Progress & community"), settings.take(3)),
        (context.tr("Preferences"), settings.skip(3).take(2)),
        (context.tr("App & privacy"), settings.skip(5)),
      ])
        prefStagger(
          _ProfileSection(
            title: group.$1,
            icon: group.$1 == 'Progress & community'
                ? Icons.explore_outlined
                : group.$1 == 'Preferences'
                ? Icons.settings_outlined
                : Icons.tune_rounded,
            children: [
              for (final (i, spec) in group.$2.indexed) ...[
                if (i > 0)
                  Divider(
                    color: t.outlineVariant.withValues(alpha: 0.4),
                    height: 1,
                    indent: 72,
                    endIndent: Gap.lg,
                  ),
                _SettingTile(
                  spec: spec,
                  onTap: () => unawaited(_openSetting(context, ref, spec)),
                ),
              ],
            ],
          ),
        ),
    ];

    return _TabEntrance(
      // The entrance waits for the branch to be on screen; see [_TabEntrance].
      // Keyed so the motion-capture harness can grab this vertical list
      // directly instead of the horizontal subject carousel inside it.
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: prefs,
                  ),
                ),
              ],
            )
          else ...[
            ...identity,
            const SizedBox(height: Gap.xl),
            ...prefs,
          ],
        ],
      ),
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
    final compact =
        MediaQuery.sizeOf(context).width < 380 ||
        MediaQuery.textScalerOf(context).scale(14) > 19;
    // Premium hero: a soft primary wash with a quiet lift, so the identity
    // card reads as the page's cover rather than another flat tile.
    return Container(
      key: const ValueKey('profile-hero'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(t.primary.withValues(alpha: 0.10), t.surface),
            t.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(Radii.hero),
        border: Border.all(color: t.primary.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: t.primary.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(Gap.xl),
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
            if (compact) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _Avatar(user: user),
                  const _EditProfileButton(),
                ],
              ),
              const SizedBox(height: Gap.lg),
              _ProfileIdentity(user: user),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Avatar(user: user),
                  const SizedBox(width: Gap.lg),
                  Expanded(child: _ProfileIdentity(user: user)),
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
            const SizedBox(height: Gap.lg),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: Gap.lg,
              runSpacing: Gap.xs,
              children: [
                Text(
                  context.tr("Level {0}", [stats.level]),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  context.tr("{0} / {1} XP", [stats.xp, stats.xpForNext]),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            Semantics(
              label: context.tr("Level {0}, {1} of {2} XP", [
                stats.level,
                stats.xp,
                stats.xpForNext,
              ]),
              value: context.tr("{0} percent", [
                (stats.levelProgress * 100).round(),
              ]),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.pill),
                child: LinearProgressIndicator(
                  value: stats.levelProgress,
                  color: t.secondary,
                  backgroundColor: t.surfaceContainerHighest,
                  minHeight: 7,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileIdentity extends StatelessWidget {
  const _ProfileIdentity({required this.user});

  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final tint = harmonize(user.persona.color, cs.primary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
        DecoratedBox(
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(Radii.tile),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.md,
              vertical: Gap.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(user.persona.icon, size: 16, color: tint),
                const SizedBox(width: Gap.sm),
                Flexible(
                  child: Text(
                    context.tr(user.persona.label),
                    style: tt.labelMedium,
                  ),
                ),
              ],
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
  const _Avatar({required this.user});

  final UserProfile user;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: context.tr("Change your avatar"),
    child: ExcludeSemantics(
      child: Pressable(
        onTap: () => showAvatarSheet(context),
        scale: 0.94,
        child: AvatarDisc(user: user, size: 74, editable: true),
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
    return ContentCard(
      color: Color.alphaBlend(
        t.secondary.withValues(alpha: .06),
        t.surfaceContainerLow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconBadge(
                  icon: Icons.smartphone_rounded,
                  color: t.primary,
                  size: 40,
                  radius: 12,
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr("Local account"),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.tr(
                          "You are using a local account. Everything you log stays on this device and is never uploaded.",
                        ),
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: t.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outlined, size: 14, color: t.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.tr(
                      "Study groups and the leaderboard need a linked account.",
                    ),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: t.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.lg),
            // No Semantics wrapper: a FilledButton already announces itself as
            // a button and takes its name from the label inside it. Wrapping
            // it in a non-container `Semantics(button: true)` was worse than
            // redundant — the wrapper has no boundary of its own, so it was
            // absorbed by the card's node and the whole card came out as one
            // button whose name was every word on it.
            FilledButton(
              onPressed: () => unawaited(_link(context, ref)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.link_rounded, size: 18),
                  SizedBox(width: Gap.sm),
                  Flexible(child: Text(context.tr("Link an account"))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Everything about how the app looks: light/dark/system, the seed palette,
/// and true black for OLED panels.
///
/// The badge and the trailing label both read from the live settings, so the
/// row states the current choice without a second tap.
class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).colorScheme;
    final settings = ref.watch(themeSettingsProvider);
    final notifier = ref.read(themeSettingsProvider.notifier);

    // The *resolved* brightness, not the preference: with `system` selected,
    // the AMOLED switch has to follow what the device is actually doing, and
    // by this point the theme has already resolved it. Showing the switch in
    // light mode would offer a control that cannot do anything.
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ContentCard(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr("Theme"),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: Gap.md),
            AppSegmentedControl<ThemePreference>(
              options: {
                for (final p in ThemePreference.values) p: context.tr(p.label),
              },
              selected: settings.mode,
              onChanged: notifier.setMode,
            ),
            const SizedBox(height: Gap.lg),
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr("Accent color"),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  context.tr(settings.palette.label),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: t.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: Gap.md),
            // Wrap rather than Row: six swatches fit on the tablet this app
            // is built for, but a 320dp phone would clip the last one, and a
            // picker that hides a choice is worse than one that uses two
            // lines.
            Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.sm,
              children: [
                for (final p in AppPalette.values)
                  _PaletteSwatch(
                    palette: p,
                    selected: p == settings.palette,
                    onTap: () => notifier.setPalette(p),
                  ),
              ],
            ),
            const SizedBox(height: Gap.lg),
            Divider(height: 1, color: t.outlineVariant.withValues(alpha: .4)),
            const SizedBox(height: Gap.sm),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.timer_outlined, color: t.onSurfaceVariant),
              title: Text(context.tr("Clock face")),
              subtitle: Text(context.tr(ref.watch(clockFaceProvider).label)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.goNamed(AppRoutes.clockFace),
            ),
            if (isDark) ...[
              const SizedBox(height: Gap.sm),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr("True black"),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          context.tr("Use a black background in dark mode."),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: t.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Gap.md),
                  // The row's heading is the switch's name; without this it
                  // is announced as an unlabelled switch next to some text.
                  Semantics(
                    label: context.tr("True black"),
                    child: Switch(
                      value: settings.amoled,
                      onChanged: notifier.setAmoled,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One palette in the picker — the seed every colour in the app derives from.
///
/// Drawn as the *light* seed: the two seeds are the same hue, so showing both
/// would be two circles pretending to be one choice. The dark seed still shows
/// up, on the switch above, the moment the app goes dark.
class _PaletteSwatch extends StatelessWidget {
  const _PaletteSwatch({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).colorScheme;
    final color = palette.lightSeed;

    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.base;
    return Semantics(
      label: context.tr(palette.label),
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.tile),
        child: Padding(
          padding: const EdgeInsets.all(Gap.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: duration,
                curve: Motion.decelerate,
                width: 48,
                height: 48,
                padding: const EdgeInsets.all(Gap.xs),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(selected ? 18 : 24),
                  border: Border.all(
                    color: selected ? t.onSurface : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: AnimatedContainer(
                  duration: duration,
                  curve: Motion.decelerate,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(selected ? 12 : 20),
                  ),
                  child: selected
                      ? Icon(
                          Icons.check_rounded,
                          size: 18,
                          color:
                              ThemeData.estimateBrightnessForColor(color) ==
                                  Brightness.dark
                              ? Colors.white
                              : Colors.black,
                        )
                      : null,
                ),
              ),
              const SizedBox(height: Gap.xs),
              Text(
                context.tr(palette.label),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Solid grouped settings rows with a quiet section heading.
class _ProfileSection extends StatelessWidget {
  const _ProfileSection({
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.lg),
      child: ContentCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Gap.lg,
                Gap.lg,
                Gap.lg,
                Gap.sm,
              ),
              child: SectionHeader(title: title, icon: icon),
            ),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: .4)),
            ...children,
          ],
        ),
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
    this.trailing,
    this.trailingColor,
    this.locked = false,
  });

  final IconData icon;
  final String label;
  final String? routeName;
  final String? trailing;
  final Color? trailingColor;

  /// Marks a destination that needs a linked account, without hiding it.
  final bool locked;
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({required this.spec, required this.onTap});

  final _SettingSpec spec;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      minVerticalPadding: Gap.md,
      leading: IconBadge(
        icon: spec.icon,
        color: t.primary,
        size: 40,
        radius: Radii.tile,
      ),
      title: Text(spec.label, style: Theme.of(context).textTheme.titleSmall),
      subtitle: spec.trailing == null
          ? null
          : Text(
              spec.trailing!,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: spec.trailingColor ?? t.onSurfaceVariant),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spec.locked) ...[
            Icon(Icons.lock_outlined, size: 16, color: t.onSurfaceVariant),
            const SizedBox(width: Gap.xs),
          ],
          const AppChevron(),
        ],
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
