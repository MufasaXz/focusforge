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

    // Both shortcuts and settings use the destination screens' live values.
    final community = <_SettingSpec>[
      _SettingSpec(
        icon: Icons.leaderboard_outlined,
        label: context.tr("Leaderboard"),
        routeName: AppRoutes.leaderboard,
        trailing: rank == null ? null : '#$rank',
        locked: user.isAnonymous,
      ),
      _SettingSpec(
        icon: Icons.groups_outlined,
        label: context.tr("Study Groups"),
        routeName: AppRoutes.groups,
        trailing: context.tr("{0} active", [groups.length]),
        locked: user.isAnonymous,
      ),
    ];
    final settings = <_SettingSpec>[
      _SettingSpec(
        icon: Icons.lock_outlined,
        label: context.tr("Strict Mode"),
        routeName: AppRoutes.strictMode,
        trailing: strict.isActive ? context.tr("On") : context.tr("Off"),
        trailingColor: strict.isActive ? t.error : null,
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= Layout.wide;

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
          stagger(
            LayoutBuilder(
              builder: (context, constraints) {
                // Leave enough room for the full labels at larger text sizes.
                final stacked =
                    constraints.maxWidth <
                    300 * MediaQuery.textScalerOf(context).scale(12) / 12;
                final tileWidth = stacked
                    ? constraints.maxWidth
                    : (constraints.maxWidth - Gap.sm) / 2;
                final diameters = [
                  for (final spec in community)
                    _CommunityTile.diameterFor(
                      context,
                      stacked ? [spec] : community,
                      tileWidth,
                    ),
                ];
                final tiles = [
                  for (final (i, spec) in community.indexed)
                    _CommunityTile(
                      diameter: diameters[i],
                      key: ValueKey('profile-${spec.routeName}-tile'),
                      spec: spec,
                      onTap: () => unawaited(_openSetting(context, ref, spec)),
                    ),
                ];
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      tiles.first,
                      const SizedBox(height: Gap.sm),
                      tiles.last,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: tiles.first),
                    const SizedBox(width: Gap.sm),
                    Expanded(child: tiles.last),
                  ],
                );
              },
            ),
          ),
          if (wide) const SizedBox(height: Gap.xl),
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
        ];
        for (final group in [
          (
            context.tr("Preferences"),
            Icons.settings_outlined,
            settings.take(2),
          ),
          (context.tr("App & privacy"), Icons.tune_rounded, settings.skip(2)),
        ]) {
          final section = prefStagger(
            _ProfileSection(
              title: group.$1,
              icon: group.$2,
              children: [
                for (final (i, spec) in group.$3.indexed) ...[
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
          );
          prefs.add(section);
        }

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: wide ? Layout.readable * 2 + Gap.xl : Layout.readable,
            ),
            child: _TabEntrance(
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
        return DecoratedBox(
          key: const ValueKey('profile-hero'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(t.primary.withValues(alpha: .10), t.surface),
                t.surface,
              ],
            ),
            borderRadius: BorderRadius.circular(Radii.hero),
            border: Border.all(color: t.primary.withValues(alpha: .22)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Gap.lg),
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
                    borderRadius: BorderRadius.circular(
                      Radii.concentric(Radii.hero, Gap.lg),
                    ),
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
        Semantics(
          key: const ValueKey('profile-achievements'),
          button: true,
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
          hint: context.tr("Achievements"),
          value: context.tr("{0} percent", [
            (stats.levelProgress * 100).round(),
          ]),
          excludeSemantics: true,
          onTap: () => context.goNamed(AppRoutes.achievements),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () => context.goNamed(AppRoutes.achievements),
              borderRadius: BorderRadius.circular(
                Radii.concentric(Radii.hero, Gap.lg),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
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
                                  padding: const EdgeInsetsDirectional.only(
                                    end: Gap.xs,
                                  ),
                                  child: Icon(
                                    Icons.military_tech_rounded,
                                    size: 16,
                                    color: cs.primary,
                                  ),
                                ),
                              ),
                              TextSpan(
                                text: context.tr("Level {0}", [stats.level]),
                              ),
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
                              : context.tr("{0} / {1} XP", [
                                  stats.xp,
                                  stats.xpForNext,
                                ]),
                          style: tt.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Gap.sm),
                    ClipRRect(
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
                  ],
                ),
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
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: IconBadge(
              icon: Icons.edit_rounded,
              color: t.primary,
              size: 36,
              radius: Radii.concentric(Radii.hero, Gap.lg),
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
      key: const ValueKey('profile-local-account'),
      color: Color.alphaBlend(
        t.secondary.withValues(alpha: .06),
        t.surfaceContainerLow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
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
                  radius: Radii.concentric(Radii.card, Gap.md),
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
              style: FilledButton.styleFrom(
                minimumSize: const Size(48, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    Radii.concentric(Radii.card, Gap.md),
                  ),
                ),
              ),
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

/// How the app looks: Day or Dark (true black), the accent palette and the
/// timer's clock face.
///
/// The two themes are shown as they are, as small live previews built from
/// the real colour schemes, rather than as words in a switch. Every nested
/// shape follows [Radii.concentric], so corners run parallel to the card's.
class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  static const _inset = Gap.md;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final settings = ref.watch(themeSettingsProvider);
    final notifier = ref.read(themeSettingsProvider.notifier);
    final inner = Radii.concentric(Radii.card, _inset);
    final face = ref.watch(clockFaceProvider);

    return ContentCard(
      key: const ValueKey('profile-appearance'),
      child: Padding(
        padding: const EdgeInsets.all(_inset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                for (final (i, mode) in ThemePreference.choices.indexed) ...[
                  if (i > 0) const SizedBox(width: Gap.sm),
                  Expanded(
                    child: _ModePreview(
                      mode: mode,
                      palette: settings.palette,
                      selected: settings.mode == mode,
                      radius: inner,
                      onTap: () => notifier.setMode(mode),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: Gap.md),
            // The accent panel shares the previews' radius: one inset, one
            // inner corner, everywhere inside this card.
            DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(inner),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Gap.md,
                  Gap.md,
                  Gap.md,
                  Gap.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.tr("Accent color"),
                            style: tt.titleSmall,
                          ),
                        ),
                        Text(
                          context.tr(settings.palette.label),
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Gap.sm),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        for (final p in AppPalette.choices)
                          Flexible(
                            child: _PaletteSwatch(
                              palette: p,
                              selected: p == settings.palette,
                              onTap: () => notifier.setPalette(p),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Gap.sm),
            Material(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(inner),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => context.goNamed(AppRoutes.clockFace),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.md,
                      vertical: Gap.sm,
                    ),
                    child: Row(
                      children: [
                        IconBadge(
                          icon: Icons.timer_outlined,
                          color: cs.primary,
                          size: 36,
                          radius: Radii.concentric(inner, Gap.sm),
                        ),
                        const SizedBox(width: Gap.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.tr("Clock face"),
                                style: tt.titleSmall,
                              ),
                              Text(
                                context.tr(face.label),
                                style: tt.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const AppChevron(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A theme drawn as a tiny screen in its own colours: an avatar and name, a
/// card with a progress bar, and an action pill. What you pick is what you
/// see.
class _ModePreview extends StatelessWidget {
  const _ModePreview({
    required this.mode,
    required this.palette,
    required this.selected,
    required this.radius,
    required this.onTap,
  });

  final ThemePreference mode;
  final AppPalette palette;
  final bool selected;
  final double radius;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final scheme =
        (mode == ThemePreference.light
                ? AppTheme.light(palette: palette)
                : AppTheme.dark(palette: palette, amoled: true))
            .colorScheme;
    const pad = Gap.sm;
    final innerRadius = Radii.concentric(radius, pad);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.base;

    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: context.tr(mode.label),
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: duration,
            curve: Motion.decelerate,
            padding: const EdgeInsets.all(pad),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: selected ? cs.primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The miniature screen.
                AspectRatio(
                  aspectRatio: 1.35,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(innerRadius),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: .5),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(Gap.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _Dot(color: scheme.primary, size: 12),
                              const SizedBox(width: 6),
                              _Bar(
                                color: scheme.onSurface.withValues(alpha: .7),
                                width: 34,
                              ),
                            ],
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _Bar(
                                  color: scheme.onSurfaceVariant.withValues(
                                    alpha: .6,
                                  ),
                                  width: 26,
                                ),
                                const SizedBox(height: 5),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Container(
                                          height: 4,
                                          color: scheme.primary,
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Container(
                                          height: 4,
                                          color: scheme.surfaceContainerHighest,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Container(
                              width: 30,
                              height: 10,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Gap.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedSwitcher(
                      duration: duration,
                      child: Icon(
                        selected ? Icons.check_circle_rounded : mode.icon,
                        key: ValueKey(selected),
                        size: 16,
                        color: selected ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        context.tr(mode.label),
                        overflow: TextOverflow.ellipsis,
                        style: tt.labelLarge?.copyWith(
                          color: selected ? cs.primary : cs.onSurface,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _Bar extends StatelessWidget {
  const _Bar({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: 4,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

/// One palette: its own colour in a circle, with a ring and a tick when it
/// is the chosen one, and its name under it. The circle shows the seed for
/// the current brightness, so it matches what the app turns into.
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
    final cs = Theme.of(context).colorScheme;
    final color = palette.seedFor(Theme.of(context).brightness);
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
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.xs,
            vertical: Gap.xs,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ring and fill are concentric circles: a 3 dp gap between
              // them at every point.
              AnimatedContainer(
                duration: duration,
                curve: Motion.decelerate,
                width: 48,
                height: 48,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? cs.onSurface : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: selected
                      ? Icon(
                          Icons.check_rounded,
                          size: 20,
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: selected ? cs.onSurface : cs.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: Gap.md),
      minVerticalPadding: Gap.md,
      minTileHeight: 64,
      leading: IconBadge(
        icon: spec.icon,
        color: t.primary,
        size: 40,
        radius: Radii.concentric(Radii.card, Gap.md),
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

/// Concentric community pills that grow with their labels.
class _CommunityTile extends StatelessWidget {
  const _CommunityTile({
    super.key,
    required this.spec,
    required this.onTap,
    required this.diameter,
  });

  final _SettingSpec spec;
  final VoidCallback onTap;
  final double diameter;

  // A larger circle consumes some label width. Measure until the two agree,
  // so neither scaled text nor the circle can overflow the stadium's ends.
  static double diameterFor(
    BuildContext context,
    List<_SettingSpec> specs,
    double width,
  ) {
    final tt = Theme.of(context).textTheme;
    double measure(String text, TextStyle? style, double available) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: available.clamp(0, double.infinity));
      final height = painter.height;
      painter.dispose();
      return height;
    }

    var diameter = 40.0;
    // Each label has at most two lines. Starting small and only growing
    // reaches a stable size, shared by both tiles when they occupy a row.
    for (var pass = 0; pass < specs.length * 4; pass++) {
      final available = width - Gap.sm * 3 - diameter;
      var height = 0.0;
      for (final spec in specs) {
        final measured =
            measure(spec.label, tt.labelMedium, available) +
            (spec.trailing == null
                ? 0
                : 2 + measure(spec.trailing!, tt.bodySmall, available));
        if (measured > height) height = measured;
      }
      if (height <= diameter) break;
      diameter = height.ceilToDouble();
    }
    return diameter;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const shape = StadiumBorder();

    return Semantics(
      button: true,
      label: spec.label,
      value: spec.trailing,
      hint: spec.locked ? context.tr("Sign in") : null,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: _tileColor(context),
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: SizedBox(
            height: diameter + Gap.sm * 2,
            child: Padding(
              padding: const EdgeInsets.all(Gap.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox.square(
                    dimension: diameter,
                    child: Stack(
                      children: [
                        IconBadge(
                          icon: spec.icon,
                          color: cs.primary,
                          size: diameter,
                          radius: Radii.concentric(
                            diameter / 2 + Gap.sm,
                            Gap.sm,
                          ),
                        ),
                        if (spec.locked)
                          PositionedDirectional(
                            end: 0,
                            bottom: 0,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: _tileColor(context),
                                shape: BoxShape.circle,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Icon(
                                  Icons.lock_outlined,
                                  size: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          spec.label,
                          style: theme.textTheme.labelMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (spec.trailing != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            spec.trailing!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
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

/// The tile surface: the low container in light, where it lifts off the page,
/// and a step higher in dark, where the low container is the page's own tone.
Color _tileColor(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Theme.of(context).brightness == Brightness.dark
      ? cs.surfaceContainerHigh
      : cs.surfaceContainerLow;
}
