import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/shell/app_shell.dart';
import '../../app/theme/app_theme.dart';
import '../../core/models/study.dart';
import '../../core/models/user.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/shield_providers.dart';
import '../../core/providers/social_providers.dart';
import '../../core/providers/study_providers.dart';
import '../../core/services/auth_service.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/icon_badge.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/progress_ring.dart';
import '../../shared/widgets/stagger.dart';
import '../focus/widgets/clock_faces.dart';
import 'widgets/avatar_sheet.dart';
import 'widgets/edit_profile_sheet.dart';
import 'widgets/subject_target_sheet.dart';

/// Shown on the About row. There is no `package_info` dependency in this app,
/// so the version is a constant — keep it in step with `pubspec.yaml`.
const _appVersion = '0.1.0';

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
          // Stagger plays once per element lifetime. The tab's branch is built
          // the first time it is shown (go_router does not preload branches), so
          // the entrance lands on the first visit and never on a rebuild.
          // Hero ---------------------------------------------------------------
          Stagger(
            index: 0,
            child: _HeroCard(
              user: user,
              stats: stats,
              streak: streak,
              unlocked: unlocked,
              totalBadges: achievements.length,
            ),
          ),
          const SizedBox(height: Gap.lg),

          if (user.isAnonymous) ...[
            const Stagger(index: 1, child: _AnonymousCard()),
            const SizedBox(height: Gap.lg),
          ],

          // Study goals ---------------------------------------------------------
          Stagger(
            index: 2,
            child: SectionHeader(
              title: 'Weekly study goals',
              icon: Icons.flag_outlined,
              trailing: Text(
                'Tap to edit',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: t.onSurfaceVariant),
              ),
            ),
          ),
          Stagger(
            index: 3,
            child: EdgeFade(
              trailing: 32,
              child: SizedBox(
                height: 118,
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
          const SizedBox(height: Gap.xl),

          // Appearance ----------------------------------------------------------
          const Stagger(
            index: 4,
            child: SectionHeader(
              title: 'Appearance',
              icon: Icons.palette_outlined,
            ),
          ),
          const Stagger(index: 5, child: _AppearanceCard()),
          const SizedBox(height: Gap.xl),

          // Focus clock ----------------------------------------------------------
          const Stagger(
            index: 6,
            child: SectionHeader(
              title: 'Focus clock',
              icon: Icons.timer_outlined,
            ),
          ),
          const Stagger(index: 7, child: _ClockFaceCard()),
          const SizedBox(height: Gap.xl),

          // Settings -------------------------------------------------------------
          const Stagger(
            index: 8,
            child: SectionHeader(
              title: 'Settings',
              icon: Icons.settings_outlined,
            ),
          ),
          Stagger(
            index: 9,
            child: Card.filled(
              // Without this the tile ripples paint square corners over the
              // card's rounded ones.
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < settings.length; i++) ...[
                    if (i > 0) Divider(color: t.outlineVariant, height: 1),
                    _SettingTile(
                      spec: settings[i],
                      onTap: () => context.goNamed(settings[i].routeName!),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: Gap.xl),

          // Developer ------------------------------------------------------------
          const Stagger(
            index: 10,
            child: SectionHeader(
              title: 'Developer',
              icon: Icons.build_outlined,
            ),
          ),
          Stagger(
            index: 11,
            child: Card.filled(
              clipBehavior: Clip.antiAlias,
              child: _SettingTile(
                spec: const _SettingSpec(
                  icon: Icons.restart_alt_outlined,
                  label: 'Replay onboarding',
                  subtitle: 'Run the first-launch flow again',
                ),
                onTap: () async {
                  await ref.read(userProvider.notifier).replayOnboarding();
                  // The router has no refresh listenable, so it only re-evaluates
                  // its redirect on a navigation — nudge it once the flag flips.
                  if (context.mounted) context.goNamed(AppRoutes.onboarding);
                },
              ),
            ),
          ),
          Stagger(
            index: 12,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, Gap.sm, 6, 0),
              child: Text(
                'Onboarding starts over from the first screen. Nothing already '
                'logged is deleted.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: t.onSurfaceVariant),
              ),
            ),
          ),
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
    return Card.filled(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.hero),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Gap.xl),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(user: user),
                const SizedBox(width: Gap.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName.trim().isEmpty
                            ? 'Your profile'
                            : user.displayName,
                        style: Theme.of(context).textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: Gap.sm),
                      // Tonal container built from the persona colour, the
                      // same pairing [IconBadge] uses.
                      Chip(
                        backgroundColor: harmonize(
                          user.persona.color,
                          t.primary,
                        ).withValues(alpha: 0.16),
                        avatar: Icon(
                          user.persona.icon,
                          size: 13,
                          color: harmonize(user.persona.color, t.primary),
                        ),
                        label: Text(
                          user.persona.label,
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Gap.sm),
                const _EditProfileButton(),
              ],
            ),
            const SizedBox(height: Gap.xl),
            Row(
              children: [
                Expanded(
                  child: _HeroStat(
                    value: '${stats.totalFocusHours.round()}h',
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
            Row(
              children: [
                Text(
                  'Level ${stats.level}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
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
        child: IconBadge(
          icon: Icons.edit_rounded,
          color: t.primary,
          size: 36,
          radius: 11,
        ),
      ),
    );
  }
}

/// Honest state for a device-only account: what works, what does not, and the
/// one action that changes it.
class _AnonymousCard extends ConsumerStatefulWidget {
  const _AnonymousCard();

  @override
  ConsumerState<_AnonymousCard> createState() => _AnonymousCardState();
}

class _AnonymousCardState extends ConsumerState<_AnonymousCard> {
  bool _busy = false;

  Future<void> _link() async {
    setState(() => _busy = true);
    final auth = ref.read(authServiceProvider);
    try {
      // `linkAccount` upgrades whatever profile the auth service is holding,
      // and it has never seen the one bootstrap hydrated from the store. Hand
      // it over first — otherwise it mints a fresh anonymous uid and drops the
      // name, persona and goal already on this device.
      await auth.updateProfile(ref.read(userProvider));
      final linked = await auth.linkAccount(provider: 'local');
      await ref.read(userProvider.notifier).save(linked);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Account linked. Study groups and the leaderboard are unlocked.',
          ),
        ),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.friendly)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
            Semantics(
              button: true,
              enabled: !_busy,
              label: 'Link an account',
              // The visible label already says it; without this the row is
              // announced twice.
              excludeSemantics: true,
              child: FilledButton(
                onPressed: _busy ? null : _link,
                child: _busy
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: t.onSurfaceVariant,
                        ),
                      )
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.link_rounded, size: 18),
                          SizedBox(width: Gap.sm),
                          Text('Link an account'),
                        ],
                      ),
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
            Row(
              children: [
                IconBadge(
                  icon: settings.mode.icon,
                  color: t.secondary,
                  size: 36,
                  radius: 10,
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Text(
                    'Appearance',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                Text(
                  settings.mode.label,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: t.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: Gap.lg),
            SegmentedButton<int>(
              segments: [
                for (final p in ThemePreference.values)
                  ButtonSegment(value: p.index, label: Text(p.label)),
              ],
              selected: {settings.mode.index},
              onSelectionChanged: (selection) =>
                  notifier.setMode(ThemePreference.values[selection.first]),
            ),
            const SizedBox(height: Gap.xl),
            Text(
              'Palette',
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: t.onSurfaceVariant),
            ),
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
                  Switch(value: settings.amoled, onChanged: notifier.setAmoled),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The clock the focus timer wears, with a live preview of each face.
///
/// The preview is the face itself, drawn small, rather than a name beside a
/// swatch: the four differ in a way words are bad at describing, and a picker
/// that has to explain itself has already failed.
class _ClockFaceCard extends ConsumerWidget {
  const _ClockFaceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).colorScheme;
    final face = ref.watch(clockFaceProvider);
    // The previews draw the timer's own value rather than a sample: it is the
    // one number that is real here, and a face that looks right at a made-up
    // time is no guarantee it looks right at the one on the clock. They do
    // not tick — nothing on this page is running — but they never disagree
    // with what the timer would show either.
    final timer = ref.watch(timerProvider);
    final preset = ref.watch(presetsProvider)[timer.presetIndex];

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBadge(
                  icon: face.icon,
                  color: t.primary,
                  size: 36,
                  radius: 10,
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Text(
                    'Focus clock',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                Text(
                  face.label,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: t.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: Gap.lg),
            LayoutBuilder(
              builder: (context, constraints) {
                // Two up where there is room for two legible previews, one up
                // on a phone. The preview needs the width more than the copy
                // does — a flip card scaled to 40dp is a grey smudge.
                final twoUp = constraints.maxWidth >= 420;
                final width = twoUp
                    ? (constraints.maxWidth - Gap.md) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: Gap.md,
                  runSpacing: Gap.md,
                  children: [
                    for (final option in ClockFace.values)
                      SizedBox(
                        width: width,
                        child: _ClockFaceOption(
                          face: option,
                          remaining: timer.remaining,
                          progress: timer.progressFor(preset),
                          selected: option == face,
                          onTap: () =>
                              ref.read(clockFaceProvider.notifier).set(option),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ClockFaceOption extends StatelessWidget {
  const _ClockFaceOption({
    required this.face,
    required this.remaining,
    required this.progress,
    required this.selected,
    required this.onTap,
  });

  final ClockFace face;
  final Duration remaining;
  final double progress;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      selected: selected,
      label: '${face.label} clock, ${face.blurb}',
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(Gap.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.item),
            color: selected
                ? t.primary.withValues(alpha: 0.12)
                : t.surfaceContainerHighest,
            border: Border.all(
              color: selected ? t.primary : t.outlineVariant,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 42,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: ClockDisplay(
                      remaining: remaining,
                      face: face,
                      accent: t.primary,
                      height: 30,
                      progress: progress,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Gap.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      face.label,
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(color: selected ? t.primary : t.onSurface),
                    ),
                  ),
                  if (selected)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: t.primary,
                    ),
                ],
              ),
              Text(
                face.blurb,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: t.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
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

    return Semantics(
      label: palette.label,
      button: true,
      selected: selected,
      child: Tooltip(
        message: palette.label,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: Motion.quick,
            curve: Motion.standard,
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? t.onSurface
                    : t.outlineVariant.withValues(alpha: 0.5),
                width: selected ? 3 : 1,
              ),
            ),
            // The tick is picked against the swatch, not against the theme:
            // a dark palette needs a light tick on any surface.
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
                  color: s.color,
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
                        Icon(s.icon, size: 13, color: s.color),
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
    this.subtitle,
    this.trailing,
    this.trailingColor,
    this.locked = false,
  });

  final IconData icon;
  final String label;
  final String? routeName;
  final String? subtitle;
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
      leading: IconBadge(
        icon: spec.icon,
        color: t.primary,
        size: 36,
        radius: 10,
      ),
      title: Text(spec.label),
      subtitle: spec.subtitle == null ? null : Text(spec.subtitle!),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spec.locked) ...[
            Icon(Icons.lock_outlined, size: 14, color: t.onSurfaceVariant),
            const SizedBox(width: 6),
          ],
          if (spec.trailing != null) ...[
            Text(
              spec.trailing!,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: spec.trailingColor ?? t.onSurfaceVariant),
            ),
            const SizedBox(width: 6),
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
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(fontSize: 10.5),
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
  Widget build(BuildContext context) =>
      _entered ? widget.child : const SizedBox.shrink();
}
