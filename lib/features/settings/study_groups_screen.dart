import '../../shared/widgets/glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/social.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/parent_providers.dart';
import '../../core/providers/social_providers.dart';
import '../../core/services/study_group_service.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/icon_badge.dart';
import '../../shared/widgets/stagger.dart';
import 'account_gate.dart';
import 'settings_support.dart';

class StudyGroupsScreen extends ConsumerStatefulWidget {
  const StudyGroupsScreen({super.key});
  @override
  ConsumerState<StudyGroupsScreen> createState() => _StudyGroupsScreenState();
}

class _StudyGroupsScreenState extends ConsumerState<StudyGroupsScreen> {
  bool _busy = false;
  Future<void> _change(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on GroupException catch (e) {
      if (mounted) showAppSnack(context, e.message);
    } catch (_) {
      if (mounted) {
        showAppSnack(context, 'Could not change the group. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final name = await showAppInputDialog(
      context: context,
      title: 'Start a study group',
      message: 'Choose a name your friends will recognise.',
      actionLabel: 'Next',
      hintText: 'Sunday study club',
      icon: Icons.groups_outlined,
    );
    if (name == null || !mounted) return;
    if (name.trim().isEmpty || name.trim().length > 60) {
      showAppSnack(context, 'Use a name between 1 and 60 characters.');
      return;
    }
    final target = await showAppInputDialog(
      context: context,
      title: 'Your shared weekly goal',
      message: 'Total hours for everyone together. Weeks run Monday to Sunday in UTC.',
      actionLabel: 'Create group',
      hintText: '10',
      icon: Icons.flag_outlined,
      keyboardType: TextInputType.number,
    );
    if (target == null || !mounted) return;
    final hours = int.tryParse(target);
    if (hours == null || hours < 1 || hours > 1000) {
      showAppSnack(context, 'Choose a goal from 1 to 1,000 hours.');
      return;
    }
    await _change(
      () => ref
          .read(studyGroupServiceProvider)
          .create(name, hours, ref.read(userProvider).displayName),
    );
  }

  Future<void> _join() async {
    final code = await showAppInputDialog(
      context: context,
      title: 'Join a study group',
      message: 'Joining shares your name, weekly focus minutes and active focus timer with members.',
      actionLabel: 'Join group',
      hintText: 'ABCD-EFGH-JK',
      icon: Icons.group_add_outlined,
    );
    if (code == null || !mounted) return;
    final clean = code.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (ref.read(groupsProvider).any((g) => g.inviteCode == clean)) {
      showAppSnack(context, 'You are already in that group.');
      return;
    }
    await _change(
      () => ref
          .read(studyGroupServiceProvider)
          .join(code, ref.read(userProvider).displayName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canUse = ref.watch(canUseGroupsProvider);
    final available = ref.watch(studyGroupServiceProvider).available;
    final groups = ref.watch(cloudGroupsProvider);
    ref.watch(groupPublisherProvider);
    final syncError = ref.watch(groupSyncErrorProvider);
    return AppPage(
      title: 'Study groups',
      subtitle: 'Make room for focused company',
      child: !canUse
          ? const AccountGate(
              title: 'Study better, together',
              subtitle: 'Link an account to create a private group or join friends with an invite code. Your existing sessions stay with you.',
              unlocked: 'Study groups are unlocked.',
              sectionTitle: 'A shared rhythm',
              items: [
                GateItem(
                  Icons.flag_outlined,
                  'One weekly goal',
                  'Everyone’s completed focus minutes count',
                ),
                GateItem(
                  Icons.leaderboard_outlined,
                  'Private standings',
                  'Visible only to members of your group',
                ),
                GateItem(
                  Icons.timer_outlined,
                  'Focus alongside friends',
                  'See who has a focus timer running',
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GlassCard(
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconBadge(
                          icon: Icons.groups_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: Gap.md),
                        Text(
                          'A little company. A lot of focus.',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: Gap.sm),
                        const Text(
                          'Share a weekly goal, see real progress and find out who is studying. Your session log stays on your device.',
                        ),
                        const SizedBox(height: Gap.lg),
                        Wrap(
                          spacing: Gap.sm,
                          runSpacing: Gap.sm,
                          children: [
                            FilledButton.icon(
                              onPressed: available && !_busy ? _create : null,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Create group'),
                            ),
                            OutlinedButton.icon(
                              onPressed: available && !_busy ? _join : null,
                              icon: const Icon(Icons.group_add_outlined),
                              label: const Text('Join with code'),
                            ),
                          ],
                        ),
                        if (_busy)
                          const Padding(
                            padding: EdgeInsets.only(top: Gap.md),
                            child: LinearProgressIndicator(),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Gap.xl),
                if (!available)
                  const Text(
                    'Study groups are unavailable in this build. Use the connected Android app.',
                  )
                else ...[
                  const SectionHeader(
                    title: 'Your groups',
                    icon: Icons.groups_rounded,
                  ),
                  if (syncError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Gap.md),
                      child: Text(syncError),
                    ),
                  groups.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) => AppSection(
                      title: 'Groups could not load',
                      children: [
                        ListTile(
                          title: const Text(
                            'Check your connection and try again',
                          ),
                          trailing: const Icon(Icons.refresh),
                          onTap: () => ref.invalidate(cloudGroupsProvider),
                        ),
                      ],
                    ),
                    data: (list) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (list.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(Gap.lg),
                            child: Text(
                              'Your next study circle starts here. Create a group, then share its code.',
                            ),
                          ),
                        for (final group in list)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Gap.md),
                            child: Stagger(
                              key: ValueKey(group.id),
                              index: list.indexOf(group),
                              child: _GroupCard(group: group),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: Gap.lg),
                Text(
                  'Up to 32 members per group. Members see your name, weekly totals and focus status. Weeks reset on Monday at 00:00 UTC. Leaving removes your row.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
    );
  }
}

class _GroupCard extends ConsumerWidget {
  const _GroupCard({required this.group});
  final StudyGroup group;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(groupMembersProvider(group.id));
    final week = ref.watch(groupWeekProvider);
    final cs = Theme.of(context).colorScheme;
    final rows = members.valueOrNull ?? [];
    final hours =
        rows.where((m) => m.week == week).fold(0, (sum, m) => sum + m.minutes) /
        60;
    final now = ref.watch(groupClockProvider).valueOrNull ?? DateTime.now();
    final focusing = rows.where((m) => m.focusingAt(now)).length;
    return GlassCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.card),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => _GroupDetail(group: group)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconBadge(icon: group.icon, color: cs.primary),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Text(
                      group.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const AppChevron(),
                ],
              ),
              const SizedBox(height: Gap.md),
              Text(
                '${group.memberCount} members · $focusing focusing now',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: Gap.lg),
              if (members.isLoading)
                const LinearProgressIndicator()
              else if (members.hasError)
                const Text('Progress could not sync. Open the group to retry.')
              else ...[
                Text(
                  '${formatHoursShort(hours)} of ${formatHoursShort(group.targetHours)}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: Gap.sm),
                LinearProgressIndicator(
                  value: (hours / group.targetHours).clamp(0, 1),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupDetail extends ConsumerStatefulWidget {
  const _GroupDetail({required this.group});
  final StudyGroup group;
  @override
  ConsumerState<_GroupDetail> createState() => _GroupDetailState();
}

class _GroupDetailState extends ConsumerState<_GroupDetail> {
  bool _busy = false;
  Future<void> _leave(StudyGroup group) async {
    final yes = await showAppConfirmDialog(
      context: context,
      title: 'Leave ${group.name}?',
      message: 'Your progress will be removed from this group. If you own it, ownership passes to another member. The last member closes the group.',
      confirmLabel: 'Leave group',
      destructive: true,
      icon: Icons.logout,
    );
    if (!yes || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(studyGroupServiceProvider).leave(group);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        showAppSnack(
          context,
          'Could not leave. Check your connection and try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final group =
        ref
            .watch(groupsProvider)
            .where((g) => g.id == widget.group.id)
            .firstOrNull ??
        widget.group;
    final members = ref.watch(groupMembersProvider(group.id));
    final week = ref.watch(groupWeekProvider);
    final uid = ref.watch(accountUidProvider);
    final now = ref.watch(groupClockProvider).valueOrNull ?? DateTime.now();
    return AppPage(
      title: group.name,
      onBack: () => Navigator.of(context).pop(),
      subtitle: '${group.memberCount} members · This week',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSection(
            title: 'Invite your circle',
            children: [
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: Text(
                  group.inviteCode,
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                subtitle: const Text(
                  'Tap to copy · Anyone with this code can join',
                ),
                trailing: const Icon(Icons.copy_rounded),
                onTap: () async {
                  await Clipboard.setData(
                    ClipboardData(text: group.inviteCode),
                  );
                  if (context.mounted) {
                    showAppSnack(context, 'Invite code copied.');
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: Gap.lg),
          FilledButton.icon(
            onPressed: () {
              final router = GoRouter.of(context);
              Navigator.pop(context);
              router.go('/focus');
            },
            icon: const Icon(Icons.timer_outlined),
            label: const Text('Start your focus timer'),
          ),
          const SizedBox(height: Gap.xl),
          const SectionHeader(
            title: 'Weekly standings',
            icon: Icons.leaderboard_outlined,
          ),
          members.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => TextButton.icon(
              onPressed: () => ref.invalidate(groupMembersProvider(group.id)),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry member progress'),
            ),
            data: (list) {
              final rows = [...list]
                ..sort(
                  (a, b) => (b.week == week ? b.minutes : 0).compareTo(
                    a.week == week ? a.minutes : 0,
                  ),
                );
              return AppSection(
                title: 'Completed focus',
                children: [
                  for (final member in rows)
                    ListTile(
                      leading: Icon(
                        member.focusingAt(now)
                            ? Icons.timer_rounded
                            : Icons.person_outline,
                      ),
                      title: Text(
                        '${member.name}${member.uid == uid ? ' · You' : ''}',
                      ),
                      subtitle: Text(
                        member.focusingAt(now)
                            ? 'Focusing now'
                            : 'Ready for another session',
                      ),
                      trailing: Text(
                        formatHoursShort(
                          (member.week == week ? member.minutes : 0) / 60,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: Gap.xl),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _leave(group),
            icon: const Icon(Icons.logout_rounded),
            label: Text(_busy ? 'Leaving…' : 'Leave group'),
          ),
        ],
      ),
    );
  }
}
