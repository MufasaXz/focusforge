import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/social.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/social_providers.dart';
import '../../core/services/auth_service.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/icon_badge.dart';
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

    return AppPage(
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
          icon: Icons.groups_outlined,
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
        AppSection(
          title: 'What groups add',
          children: [
            const ListTile(
              leading: Icon(Icons.flag_outlined),
              title: Text('Weekly group targets'),
              subtitle: Text('Pool your hours toward a shared goal'),
            ),
            const Divider(height: 1, indent: 56),
            const ListTile(
              leading: Icon(Icons.leaderboard_outlined),
              title: Text('A private leaderboard'),
              subtitle: Text('Only the people in the group see the standings'),
            ),
            const Divider(height: 1, indent: 56),
            const ListTile(
              leading: Icon(Icons.timer_outlined),
              title: Text('Shared focus sessions'),
              subtitle: Text('Study alongside your group in real time'),
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
    // Harmonised so each group's colour sits in the live theme's temperature.
    final accents = SubjectPalette.harmonized(
      Theme.of(context).colorScheme.primary,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Your groups', icon: Icons.groups_rounded),
        for (var i = 0; i < groups.length; i++) ...[
          if (i > 0) const SizedBox(height: Gap.md),
          _GroupCard(
            group: groups[i],
            accent: accents[i % SubjectPalette.count],
          ),
        ],
        const SizedBox(height: Gap.xl),
        AppSection(
          title: 'Join a group',
          footnote: 'Codes are not case-sensitive.',
          children: [
            ListTile(
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('Enter an invite code'),
              subtitle: const Text('Join with a code a friend shared'),
              trailing: const AppChevron(),
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
    final cs = Theme.of(context).colorScheme;
    final percent = (group.progress * 100).round();
    final remaining = group.targetHours - group.weeklyHours;

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconBadge(
                  icon: group.icon,
                  color: accent,
                  size: 42,
                  radius: 12,
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        group.name,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${group.memberCount} members · '
                        '${formatHours(group.weeklyHours)} this week',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Chip(
                  label: Text('$percent%'),
                  backgroundColor: group.progress >= 1
                      ? accent.withValues(alpha: 0.16)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: Gap.lg),
            Semantics(
              label: '${group.name} weekly target',
              value: '$percent percent',
              child: LinearProgressIndicator(
                value: group.progress,
                color: accent,
                backgroundColor: cs.surfaceContainerHighest,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: Gap.sm),
            Row(
              children: [
                Text(
                  '${formatHours(group.weeklyHours)} of '
                  '${formatHours(group.targetHours)} target',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const Spacer(),
                Text(
                  remaining <= 0
                      ? 'Target met'
                      : '${formatHours(remaining)} to go',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: remaining <= 0 ? accent : cs.onSurfaceVariant,
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
