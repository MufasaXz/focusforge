import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/shell/app_shell.dart';
import '../../app/theme/app_theme.dart';
import '../../core/models/parent.dart';
import '../../core/models/study.dart';
import '../../core/models/user.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/parent_providers.dart';
import '../../core/providers/shield_providers.dart';
import '../../core/providers/social_providers.dart';
import '../../core/providers/study_providers.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/app_segmented_control.dart';
import '../../shared/widgets/icon_badge.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/progress_ring.dart';
import '../../shared/widgets/stagger.dart';
import '../../shared/widgets/tonal_panel.dart';
import 'widgets/focus_overview.dart';
import '../settings/account_gate.dart';
import '../settings/settings_support.dart';
import 'widgets/avatar_sheet.dart';
import 'widgets/edit_profile_sheet.dart';
import 'widgets/link_account_sheet.dart';
import 'widgets/subject_target_sheet.dart';

/// Shown on the About row. There is no `package_info` dependency in this app,
/// so the version is a constant — keep it in step with `pubspec.yaml`.
const _appVersion = '1.0.2';

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
      message:
          '${spec.label} compares you with other people, so it needs a real '
          'account. Linking one is instant and keeps everything you have '
          'already logged on this device.',
    );
    if (!wants || !context.mounted) return;

    final profile = await showLinkAccountSheet(context);
    if (profile == null || !context.mounted) return;
    await ref.read(userProvider.notifier).save(profile);
    if (!context.mounted) return;
    final name = profile.displayName.trim();
    showAppSnack(context, name.isEmpty ? 'Signed in.' : 'Signed in as $name.');
  }

  if (context.mounted) context.goNamed(route);
}

/// `5h` for whole hours, `5.5h` otherwise — a raw double would render `5.0h`.
String _hours(double h) =>
    h == h.roundToDouble() ? '${h.round()}h' : '${h.toStringAsFixed(1)}h';

/// Tab 4 — identity, progression and settings.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).colorScheme;

    final user = ref.watch(userProvider);
    final stats = ref.watch(statsProvider);
    final streak = ref.watch(currentStreakProvider);
    final subjects = ref.watch(subjectsProvider);
    final groups = ref.watch(groupsProvider);
    final achievements = ref.watch(achievementsProvider);
    final unlocked = ref.watch(unlockedCountProvider);
    final me = ref.watch(myRankProvider);
    final strict = ref.watch(strictModeProvider);
    // `valueOrNull`: a stream that errors — no rules published yet, no
    // connection — must leave this row without a trailing value rather than
    // throw out of the build and blank the whole tab.
    final guardian = ref.watch(guardianProvider).valueOrNull;
    final children =
        ref.watch(childrenProvider).valueOrNull ?? const <ChildLink>[];

    final standings = ref.watch(leaderboardProvider);
    final rankIndex = standings.indexWhere((e) => e.isMe);
    final rank = me == null || rankIndex < 0 ? null : rankIndex + 1;

    // Every row carries its own live trailing value, so the list cannot drift
    // from the data the destination screens show.
    final settings = <_SettingSpec>[
      _SettingSpec(
        icon: Icons.groups_outlined,
        label: 'Study Groups',
        routeName: AppRoutes.groups,
        trailing: '${groups.length} active',
        locked: user.isAnonymous,
      ),
      _SettingSpec(
        icon: Icons.emoji_events_outlined,
        label: 'Achievements',
        routeName: AppRoutes.achievements,
        trailing: '$unlocked / ${achievements.length}',
      ),
      _SettingSpec(
        icon: Icons.leaderboard_outlined,
        label: 'Leaderboard',
        routeName: AppRoutes.leaderboard,
        trailing: rank == null ? null : '#$rank',
        locked: user.isAnonymous,
      ),
      _SettingSpec(
        icon: Icons.lock_outlined,
        label: 'Strict Mode',
        routeName: AppRoutes.strictMode,
        trailing: strict.enabled ? 'On' : 'Off',
        trailingColor: strict.enabled ? t.error : null,
      ),
      _SettingSpec(
        icon: Icons.family_restroom_outlined,
        label: 'Parent control',
        routeName: AppRoutes.parentControl,
        // One value, and the one that matters: is anybody watching this
        // device, or is this the phone doing the watching.
        trailing: guardian != null
            ? 'Linked'
            : children.isEmpty
            ? null
            : '${children.length} linked',
      ),
      _SettingSpec(
        icon: Icons.timer_outlined,
        label: 'Clock face',
        routeName: AppRoutes.clockFace,
        // Named rather than counted: "5 options" says nothing about which one
        // is running, and this row is the only place the current one is
        // visible without opening the page.
        trailing: ref.watch(clockFaceProvider).label,
      ),
      _SettingSpec(
        icon: Icons.notifications_active_outlined,
        label: 'Notifications',
        routeName: AppRoutes.notifications,
      ),
      _SettingSpec(
        icon: Icons.shield_outlined,
        label: 'Data & Privacy',
        routeName: AppRoutes.privacy,
      ),
      _SettingSpec(
        icon: Icons.info_outlined,
        label: 'About FocusForge',
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
      stagger(const Eyebrow('YOUR SPACE', icon: Icons.person_outline_rounded)),
      const SizedBox(height: Gap.lg),
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
      stagger(ProfileShortcuts(guardian: user.isGuardian)),
      const SizedBox(height: Gap.lg),
      if (user.isAnonymous) ...[
        stagger(const _AnonymousCard()),
        const SizedBox(height: Gap.lg),
      ],
      if (!user.isGuardian) ...[
        stagger(const FocusOverview()),
        const SizedBox(height: Gap.xl),
      ],
      stagger(
        SectionHeader(
          title: 'Weekly study goals',
          icon: Icons.flag_outlined,
          trailing: Text(
            'Tap to edit',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: t.onSurfaceVariant),
          ),
        ),
      ),
      stagger(
        EdgeFade(
          trailing: 32,
          child: SizedBox(
            height: MediaQuery.textScalerOf(context).scale(14) > 19 ? 164 : 118,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: subjects.length,
              separatorBuilder: (_, _) => const SizedBox(width: Gap.md),
              itemBuilder: (context, i) => _SubjectGoalCard(
                subject: subjects[i],
                onTap: () => showSubjectTargetSheet(context, subjects[i]),
              ),
            ),
          ),
        ),
      ),
    ];

    final prefs = <Widget>[
      prefStagger(
        const SectionHeader(title: 'Appearance', icon: Icons.palette_outlined),
      ),
      prefStagger(const _AppearanceCard()),
      const SizedBox(height: Gap.xl),
      for (final group in [
        ('Progress & community', settings.take(3)),
        ('Focus & protection', settings.skip(3).take(3)),
        ('App & privacy', settings.skip(6)),
      ])
        prefStagger(
          AppSection(
            title: group.$1,
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
      child: ListView(
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
                Expanded(child: Column(children: identity)),
                const SizedBox(width: Gap.xl),
                Expanded(child: Column(children: prefs)),
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
    return TonalPanel(
      accent: true,
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Gap.xl),
        child: Column(
          children: [
            const Eyebrow('A LITTLE BETTER, EVERY DAY'),
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
            Row(
              children: [
                Expanded(
                  child: _HeroStat(
                    value: _hours(stats.totalFocusHours),
                    label: 'Total focus',
                  ),
                ),
                _Divider(t: t),
                Expanded(
                  child: _HeroStat(
                    value: '$streak',
                    label: 'Day streak',
                    accent: t.tertiary,
                  ),
                ),
                _Divider(t: t),
                Expanded(
                  child: _HeroStat(
                    value: '$unlocked/$totalBadges',
                    label: 'Badges',
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.xl),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: Gap.lg,
              runSpacing: Gap.xs,
              children: [
                Text(
                  'Level ${stats.level}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  '${stats.xp} / ${stats.xpForNext} XP',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            Semantics(
              label:
                  'Level ${stats.level}, ${stats.xp} of ${stats.xpForNext} XP',
              value: '${(stats.levelProgress * 100).round()} percent',
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
          user.displayName.trim().isEmpty ? 'Your profile' : user.displayName,
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
                  child: Text(user.persona.label, style: tt.labelMedium),
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
    label: 'Change your avatar',
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
      label: 'Edit profile',
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
    final profile = await showLinkAccountSheet(context);
    if (profile == null || !context.mounted) return;
    await ref.read(userProvider.notifier).save(profile);
    final name = profile.displayName.trim();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${name.isEmpty ? 'Signed in' : 'Signed in as $name'}. Study '
          'groups and the leaderboard are unlocked.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).colorScheme;
    return Card.outlined(
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
                        'Local account',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'You are using a local account. Everything you log '
                        'stays on this device and is never uploaded.',
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
                    'Study groups and the leaderboard need a linked account.',
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
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.link_rounded, size: 18),
                  SizedBox(width: Gap.sm),
                  Flexible(child: Text('Link an account')),
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

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSegmentedControl<ThemePreference>(
              options: {for (final p in ThemePreference.values) p: p.label},
              selected: settings.mode,
              onChanged: notifier.setMode,
            ),
            const SizedBox(height: Gap.xl),
            Text('Palette', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: Gap.md),
            // Wrap rather than Row: six swatches fit on the tablet this app
            // is built for, but a 320dp phone would clip the last one, and a
            // picker that hides a choice is worse than one that uses two
            // lines.
            Wrap(
              spacing: Gap.md,
              runSpacing: Gap.md,
              children: [
                for (final p in AppPalette.values)
                  _PaletteSwatch(
                    palette: p,
                    selected: p == settings.palette,
                    onTap: () => notifier.setPalette(p),
                  ),
              ],
            ),
            if (isDark) ...[
              const SizedBox(height: Gap.lg),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'True black',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          'Turns dark surfaces fully off, for OLED panels.',
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
                    label: 'True black',
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
      label: palette.label,
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
                palette.label,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One subject goal. Tapping opens the target editor.
class _SubjectGoalCard extends StatelessWidget {
  const _SubjectGoalCard({required this.subject, required this.onTap});

  final Subject subject;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).colorScheme;
    final s = subject;
    final spoken =
        '${s.name}, ${_hours(s.weekDone)} of ${_hours(s.weekTarget)} '
        'this week. Change the weekly target.';

    return Semantics(
      button: true,
      label: spoken,
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        scale: 0.97,
        child: Card.filled(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.lg,
              vertical: Gap.md,
            ),
            child: Row(
              children: [
                MiniRing(
                  value: s.weekProgress,
                  color: harmonize(s.color, t.primary),
                  size: 54,
                  label: '${(s.weekProgress * 100).round()}%',
                ),
                const SizedBox(width: Gap.md),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          s.icon,
                          size: 16,
                          color: harmonize(s.color, t.primary),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          s.name,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          '${_hours(s.weekDone)} / ${_hours(s.weekTarget)}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.tune_rounded,
                          size: 12,
                          color: t.onSurfaceVariant,
                        ),
                      ],
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
