import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/color_tokens.dart';
import '../../app/theme/glass_theme.dart';
import '../../core/models/social.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/social_providers.dart';
import '../../core/services/auth_service.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_page.dart';
import '../../shared/widgets/glass_surface.dart';
import '../../shared/widgets/glass_toggle.dart';
import 'settings_support.dart';

/// Study Groups — the one social feature behind a real account.
///
/// The gate is a first-class state, not an error: anonymous users keep every
/// other feature, and the screen's job is to explain what linking adds and
/// make the upgrade one tap away rather than hiding the destination.
class StudyGroupsScreen extends ConsumerWidget {
  const StudyGroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canUse = ref.watch(canUseGroupsProvider);
    final groups = ref.watch(groupsProvider);

    return GlassPage(
      title: 'Study Groups',
      subtitle: canUse
          ? '${groups.length} active'
          : 'A real account is required',
      child: canUse ? const _GroupList() : const _SignInGate(),
    );
  }
}

// ---------------------------------------------------------------------------
// Signed-out gate
// ---------------------------------------------------------------------------

class _SignInGate extends ConsumerStatefulWidget {
  const _SignInGate();

  @override
  ConsumerState<_SignInGate> createState() => _SignInGateState();
}

class _SignInGateState extends ConsumerState<_SignInGate> {
  bool _linking = false;

  Future<void> _link() async {
    setState(() => _linking = true);
    try {
      final auth = ref.read(authServiceProvider);
      // bootstrap() hydrates the store directly, so the service has no live
      // session yet. Restoring first is what lets linkAccount() upgrade the
      // existing uid in place instead of minting a fresh anonymous profile.
      await auth.restore();
      final profile = await auth.linkAccount(
        provider: 'email',
        displayName: ref.read(userProvider).displayName,
      );
      await ref.read(userProvider.notifier).save(profile);
      if (!mounted) return;
      showGlassSnack(context, 'Account linked. Study groups are unlocked.');
    } on AuthException catch (e) {
      if (!mounted) return;
      showGlassSnack(context, e.friendly);
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EmptyState(
          icon: Icons.groups_rounded,
          title: 'Sign in to use study groups',
          subtitle:
              'Groups compare your week with other people, so they need a real '
              'account. Linking one is instant and keeps every session you have '
              'already logged.',
          action: GlassActionButton(
            label: _linking ? 'Linking…' : 'Link my account',
            icon: Icons.link_rounded,
            onTap: _linking ? null : _link,
          ),
        ),
        GlassSection(
          title: 'What groups add',
          children: [
            const GlassRow(
              title: 'Weekly group targets',
              subtitle: 'Pool your hours toward a shared goal',
              icon: Icons.flag_rounded,
            ),
            const GlassRow(
              title: 'A private leaderboard',
              subtitle: 'Only the people in the group see the standings',
              icon: Icons.leaderboard_rounded,
            ),
            const GlassRow(
              title: 'Shared focus sessions',
              subtitle: 'Study alongside your group in real time',
              icon: Icons.timer_rounded,
              showDivider: false,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Signed-in list
// ---------------------------------------------------------------------------

class _GroupList extends ConsumerWidget {
  const _GroupList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Your groups', icon: Icons.groups_rounded),
        for (var i = 0; i < groups.length; i++) ...[
          if (i > 0) const SizedBox(height: Gap.md),
          _GroupCard(
            group: groups[i],
            accent: SubjectColors.all[i % SubjectColors.all.length],
          ),
        ],
        const SizedBox(height: Gap.xl),
        GlassSection(
          title: 'Join a group',
          footnote: 'Codes are not case-sensitive.',
          children: [
            GlassRow(
              title: 'Enter an invite code',
              subtitle: 'Join with a code a friend shared',
              icon: Icons.group_add_rounded,
              trailing: const GlassChevron(),
              showDivider: false,
              onTap: () => _join(context, ref),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _join(BuildContext context, WidgetRef ref) async {
    final code = await showGlassInputDialog(
      context: context,
      title: 'Join a group',
      message: 'Enter the invite code a member shared with you.',
      actionLabel: 'Join',
      hintText: 'PHY-4821',
      icon: Icons.group_add_rounded,
    );
    if (code == null || !context.mounted) return;

    // There is no group backend in this build, so the only honest answers are
    // "already in it" and "not a code I know" — a fake success would be worse.
    final match = ref
        .read(groupsProvider)
        .where((g) => g.inviteCode.toUpperCase() == code.toUpperCase())
        .firstOrNull;

    showGlassSnack(
      context,
      match == null
          ? 'No group matches “$code”. Check the code and try again.'
          : 'You are already in ${match.name}.',
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.accent});

  final StudyGroup group;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final percent = (group.progress * 100).round();
    final remaining = group.targetHours - group.weeklyHours;

    return GlassPanel(
      radius: Radii.card,
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GlassIconBadge(
                icon: group.icon,
                color: accent,
                size: 42,
                radius: 12,
                glow: 0.25,
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(group.name, style: context.type.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      '${group.memberCount} members · '
                      '${formatHours(group.weeklyHours)} this week',
                      style: context.type.bodySmall?.copyWith(
                        color: t.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              GlassPill(
                selected: group.progress >= 1,
                accent: accent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                child: Text(
                  '$percent%',
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.lg),
          GlassProgressBar(
            value: group.progress,
            color: accent,
            height: 6,
            semanticLabel: '${group.name} weekly target',
          ),
          const SizedBox(height: Gap.sm),
          Row(
            children: [
              Text(
                '${formatHours(group.weeklyHours)} of '
                '${formatHours(group.targetHours)} target',
                style: context.type.labelSmall,
              ),
              const Spacer(),
              Text(
                remaining <= 0
                    ? 'Target met'
                    : '${formatHours(remaining)} to go',
                style: context.type.labelSmall?.copyWith(
                  color: remaining <= 0 ? accent : t.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
