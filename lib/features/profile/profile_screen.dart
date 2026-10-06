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
import '../../shared/widgets/glass_surface.dart';
import '../../shared/widgets/glass_toggle.dart';
import '../../shared/widgets/progress_ring.dart';
import '../../shared/widgets/segmented_control.dart';
import '../../shared/widgets/stagger.dart';
import 'widgets/edit_profile_sheet.dart';
import 'widgets/glass_button.dart';
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
        icon: Icons.groups_rounded,
        label: 'Study Groups',
        routeName: AppRoutes.groups,
        trailing: '${groups.length} active',
        locked: user.isAnonymous,
      ),
      _SettingSpec(
        icon: Icons.emoji_events_rounded,
        label: 'Achievements',
        routeName: AppRoutes.achievements,
        trailing: '$unlocked / ${achievements.length}',
      ),
      _SettingSpec(
        icon: Icons.leaderboard_rounded,
        label: 'Leaderboard',
        routeName: AppRoutes.leaderboard,
        trailing: rank == null ? null : '#$rank',
        locked: user.isAnonymous,
      ),
      _SettingSpec(
        icon: Icons.lock_rounded,
        label: 'Strict Mode',
        routeName: AppRoutes.strictMode,
        trailing: strict.enabled ? 'On' : 'Off',
        trailingColor: strict.enabled ? t.error : null,
      ),
      _SettingSpec(
        icon: Icons.notifications_active_rounded,
        label: 'Notifications',
        routeName: AppRoutes.notifications,
      ),
      _SettingSpec(
        icon: Icons.shield_rounded,
        label: 'Data & Privacy',
        routeName: AppRoutes.privacy,
      ),
      _SettingSpec(
        icon: Icons.info_rounded,
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
              icon: Icons.flag_rounded,
              trailing: Text(
                'Tap to edit',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: t.onSurfaceVariant),
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
              icon: Icons.palette_rounded,
            ),
          ),
          const Stagger(index: 5, child: _AppearanceCard()),
          const SizedBox(height: Gap.xl),

          // Settings -------------------------------------------------------------
          const Stagger(
            index: 6,
            child: SectionHeader(
              title: 'Settings',
              icon: Icons.settings_rounded,
            ),
          ),
          Stagger(
            index: 7,
            child: GlassPanel(
              radius: Radii.card,
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.lg,
                vertical: Gap.xs,
              ),
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
            index: 8,
            child: SectionHeader(title: 'Developer', icon: Icons.build_rounded),
          ),
          Stagger(
            index: 9,
            child: GlassPanel(
              radius: Radii.card,
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.lg,
                vertical: Gap.xs,
              ),
              child: _SettingTile(
                spec: const _SettingSpec(
                  icon: Icons.restart_alt_rounded,
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
            index: 10,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, Gap.sm, 6, 0),
              child: Text(
                'Onboarding starts over from the first screen. Nothing already '
                'logged is deleted.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: t.onSurfaceVariant),
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
    required this.unlocked,
    required this.totalBadges,
  });

  final UserProfile user;
  final GamificationStats stats;
  final int unlocked;
  final int totalBadges;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).colorScheme;
    return GlassPanel(
      radius: Radii.hero,
      blur: 18,
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
                    GlassPill(
                      selected: true,
                      accent: user.persona.color,
                      padding: const EdgeInsets.symmetric(
                        horizontal: Gap.md,
                        vertical: 5,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            user.persona.icon,
                            size: 12,
                            color: user.persona.color,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            user.persona.label,
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        ],
                      ),
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
                  value: '${stats.currentStreak}',
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
              Text('Level ${stats.level}', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              Text(
                '${stats.xp} / ${stats.xpForNext} XP',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          GlassProgressBar(
            value: stats.levelProgress,
            color: t.secondary,
            height: 7,
            semanticLabel:
                'Level ${stats.level}, ${stats.xp} of ${stats.xpForNext} XP',
          ),
        ],
      ),
    );
  }
}

/// Persona-coloured initials disc. The initials are decoration; the spoken
/// label carries the identity.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.user});

  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).colorScheme;
    final ink = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF0A1020)
        : Colors.white;
    final label = user.displayName.trim().isEmpty
        ? 'Profile avatar'
        : 'Avatar for ${user.displayName}';

    return Semantics(
      image: true,
      label: label,
      excludeSemantics: true,
      child: Container(
        width: 74,
        height: 74,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              t.primary.withValues(alpha: 0.85),
              t.secondary.withValues(alpha: 0.85),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: t.primary.withValues(alpha: 0.35),
              blurRadius: 22,
              spreadRadius: -4,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          user.initials,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: ink,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
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
        child: GlassIconBadge(
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.friendly)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).colorScheme;
    return GlassPanel(
      radius: Radii.card,
      padding: const EdgeInsets.all(Gap.lg),
      accent: t.primary,
      glowStrength: 0.2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GlassIconBadge(
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
                    Text('Local account', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      'You are using a local account. Everything you log stays '
                      'on this device and is never uploaded.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: t.onSurfaceVariant,
                      ),
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
              Icon(Icons.lock_rounded, size: 14, color: t.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Study groups and the leaderboard need a linked account.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: t.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.lg),
          GlassButton(
            label: 'Link an account',
            icon: Icons.link_rounded,
            busy: _busy,
            onTap: _link,
          ),
        ],
      ),
    );
  }
}

/// Three-way theme control. The badge and the trailing label both read from
/// the live enum, so the row states the current choice without a second tap.
class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).colorScheme;
    final pref = ref.watch(themeProvider);

    return GlassPanel(
      radius: Radii.card,
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
        children: [
          Row(
            children: [
              GlassIconBadge(
                icon: pref.icon,
                color: t.secondary,
                size: 36,
                radius: 10,
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Text('Appearance', style: Theme.of(context).textTheme.bodyLarge),
              ),
              Text(
                pref.label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: t.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: Gap.lg),
          SegmentedControl(
            options: [for (final p in ThemePreference.values) p.label],
            index: pref.index,
            accent: t.secondary,
            onChanged: (i) =>
                ref.read(themeProvider.notifier).set(ThemePreference.values[i]),
          ),
        ],
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
        child: GlassPanel(
          radius: Radii.card,
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
                      Text(s.name, style: Theme.of(context).textTheme.titleSmall),
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
                      Icon(Icons.tune_rounded, size: 12, color: t.onSurfaceVariant),
                    ],
                  ),
                ],
              ),
            ],
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
    return Pressable(
      onTap: onTap,
      scale: 0.985,
      child: ConstrainedBox(
        // Material's minimum target. The icon badge already carries the row
        // past 48dp; the constraint keeps that true if the badge shrinks.
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.md),
          child: Row(
            children: [
              GlassIconBadge(
                icon: spec.icon,
                color: t.primary,
                size: 36,
                radius: 10,
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(spec.label, style: Theme.of(context).textTheme.bodyLarge),
                    if (spec.subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          spec.subtitle!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: t.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (spec.locked) ...[
                Icon(Icons.lock_rounded, size: 14, color: t.onSurfaceVariant),
                const SizedBox(width: 6),
              ],
              if (spec.trailing != null) ...[
                Text(
                  spec.trailing!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: spec.trailingColor ?? t.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: t.onSurfaceVariant,
              ),
            ],
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
          style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 10.5),
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
