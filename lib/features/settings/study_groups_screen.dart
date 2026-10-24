import '../../core/localization/app_strings.dart';
import '../../shared/widgets/glass_surface.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/social.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/community_providers.dart';
import '../../shared/widgets/community_safety.dart';
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
        showAppSnack(
          context,
          tr("Could not change the group. Please try again."),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    if (!await confirmCommunityTerms(context) || !mounted) return;
    final name = await showAppInputDialog(
      context: context,
      title: tr("Start a study group"),
      message: tr("Choose a name your friends will recognise."),
      actionLabel: tr("Next"),
      hintText: tr("Sunday study club"),
      icon: Icons.groups_outlined,
    );
    if (name == null || !mounted) return;
    if (name.trim().isEmpty || name.trim().length > 60) {
      showAppSnack(context, tr("Use a name between 1 and 60 characters."));
      return;
    }
    final target = await showAppInputDialog(
      context: context,
      title: tr("Your shared weekly goal"),
      message: tr(
        "Total hours for everyone together. Weeks run Monday to Sunday in UTC.",
      ),
      actionLabel: tr("Create group"),
      hintText: '10',
      icon: Icons.flag_outlined,
      keyboardType: TextInputType.number,
    );
    if (target == null || !mounted) return;
    final hours = int.tryParse(target);
    if (hours == null || hours < 1 || hours > 1000) {
      showAppSnack(context, tr("Choose a goal from 1 to 1,000 hours."));
      return;
    }
    await _change(
      () => ref
          .read(studyGroupServiceProvider)
          .create(name, hours, ref.read(userProvider).displayName),
    );
  }

  Future<void> _join() async {
    if (!await confirmCommunityTerms(context) || !mounted) return;
    final code = await showAppInputDialog(
      context: context,
      title: tr("Join a study group"),
      message: tr(
        "Joining shares your name, weekly focus minutes and active focus timer with members.",
      ),
      actionLabel: tr("Join group"),
      hintText: 'ABCD-EFGH-JK',
      icon: Icons.group_add_outlined,
    );
    if (code == null || !mounted) return;
    final clean = code.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (ref.read(groupsProvider).any((g) => g.inviteCode == clean)) {
      showAppSnack(context, tr("You are already in that group."));
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
      title: context.tr("Study groups"),
      subtitle: context.tr("Make room for focused company"),
      child: !canUse
          ? AccountGate(
              title: context.tr("Study better, together"),
              subtitle: context.tr(
                "Link an account to create a private group or join friends with an invite code. Your existing sessions stay with you.",
              ),
              unlocked: context.tr("Study groups are unlocked."),
              sectionTitle: context.tr("A shared rhythm"),
              items: [
                GateItem(
                  Icons.flag_outlined,
                  context.tr("One weekly goal"),
                  context.tr("Everyone’s completed focus minutes count"),
                ),
                GateItem(
                  Icons.leaderboard_outlined,
                  context.tr("Private standings"),
                  context.tr("Visible only to members of your group"),
                ),
                GateItem(
                  Icons.timer_outlined,
                  context.tr("Focus alongside friends"),
                  context.tr("See who has a focus timer running"),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ContentCard(
                  key: const ValueKey('groups-hero'),
                  color: Color.alphaBlend(
                    Theme.of(context).colorScheme.primary
                        .withValues(alpha: .09),
                    Theme.of(context).colorScheme.surfaceContainerLow,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.hero),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionHeader(
                          title: context.tr("A shared rhythm"),
                          icon: Icons.groups_outlined,
                        ),
                        const SizedBox(height: Gap.md),
                        Text(
                          context.tr("A little company. A lot of focus."),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: Gap.sm),
                        Text(
                          context.tr(
                            "Everyone’s completed focus minutes count",
                          ),
                        ),
                        const SizedBox(height: Gap.lg),
                        Wrap(
                          spacing: Gap.sm,
                          runSpacing: Gap.sm,
                          children: [
                            FilledButton.icon(
                              onPressed: available && !_busy ? _create : null,
                              icon: const Icon(Icons.add_rounded),
                              label: Text(context.tr("Create group")),
                            ),
                            OutlinedButton.icon(
                              onPressed: available && !_busy ? _join : null,
                              icon: const Icon(Icons.group_add_outlined),
                              label: Text(context.tr("Join with code")),
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
                  Text(
                    context.tr(
                      "Study groups are unavailable in this build. Use the connected Android app.",
                    ),
                  )
                else ...[
                  SectionHeader(
                    title: context.tr("Your groups"),
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
                      title: context.tr("Groups could not load"),
                      children: [
                        ListTile(
                          title: Text(
                            context.tr("Check your connection and try again"),
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
                          Padding(
                            padding: EdgeInsets.all(Gap.lg),
                            child: Text(
                              context.tr(
                                "Your next study circle starts here. Create a group, then share its code.",
                              ),
                            ),
                          ),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final twoColumns =
                                constraints.maxWidth >= 600 &&
                                MediaQuery.textScalerOf(context).scale(14) <=
                                    19;
                            final width = twoColumns
                                ? (constraints.maxWidth - Gap.md) / 2
                                : constraints.maxWidth;
                            return Wrap(
                              spacing: Gap.md,
                              runSpacing: Gap.md,
                              children: [
                                for (final group in list)
                                  SizedBox(
                                    width: width,
                                    child: Stagger(
                                      key: ValueKey(group.id),
                                      index: list.indexOf(group),
                                      child: _GroupCard(group: group),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: Gap.lg),
                Text(
                  context.tr(
                    "Up to 32 members per group. Members see your name, weekly totals and focus status. Weeks reset on Monday at 00:00 UTC. Leaving removes your row.",
                  ),
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
    final progress = (hours / group.targetHours).clamp(0.0, 1.0);
    return ContentCard(
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.tr("{0} members", [group.memberCount]),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const AppChevron(),
                ],
              ),
              const SizedBox(height: Gap.lg),
              if (members.isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: Gap.lg),
                  child: LinearProgressIndicator(),
                )
              else if (members.hasError)
                Text(
                  context.tr(
                    "Progress could not sync. Open the group to retry.",
                  ),
                )
              else ...[
                // The shared goal, as the card's headline: how far the circle
                // has got through the week it set itself.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formatHoursShort(hours),
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            context.tr("of {0} this week", [
                              formatHoursShort(group.targetHours),
                            ]),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    // A live member tells more than a count: someone is in a
                    // block right now, so the dot is lit rather than listed.
                    if (focusing > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Gap.sm,
                          vertical: Gap.xs,
                        ),
                        decoration: BoxDecoration(
                          color: cs.tertiary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timer_rounded,
                              size: 13,
                              color: cs.tertiary,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              context.tr("{0} focusing", [focusing]),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: cs.tertiary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: Gap.md),
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: cs.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: Gap.sm),
                Text(
                  context.tr("{0} of the shared goal", [
                    '${(progress * 100).round()}%',
                  ]),
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
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
      title: tr("Leave {0}?", [group.name]),
      message: tr(
        "Your progress will be removed from this group. If you own it, ownership passes to another member. The last member closes the group.",
      ),
      confirmLabel: tr("Leave group"),
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
          tr("Could not leave. Check your connection and try again."),
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
      subtitle: context.tr("{0} members · This week", [group.memberCount]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSection(
            title: context.tr("Invite your circle"),
            children: [
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: Text(
                  group.inviteCode,
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                subtitle: Text(
                  context.tr("Tap to copy · Anyone with this code can join"),
                ),
                trailing: const Icon(Icons.copy_rounded),
                onTap: () async {
                  await Clipboard.setData(
                    ClipboardData(text: group.inviteCode),
                  );
                  if (context.mounted) {
                    showAppSnack(context, context.tr("Invite code copied."));
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
            label: Text(context.tr("Start your focus timer")),
          ),
          const SizedBox(height: Gap.xl),
          SectionHeader(
            title: context.tr("Weekly standings"),
            icon: Icons.leaderboard_outlined,
          ),
          members.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => TextButton.icon(
              onPressed: () => ref.invalidate(groupMembersProvider(group.id)),
              icon: const Icon(Icons.refresh),
              label: Text(context.tr("Retry member progress")),
            ),
            data: (list) {
              final hidden = ref.watch(blockedCommunityUsersProvider);
              final rows =
                  [
                    for (final member in list)
                      if (!hidden.contains(member.uid)) member,
                  ]..sort(
                    (a, b) => (b.week == week ? b.minutes : 0).compareTo(
                      a.week == week ? a.minutes : 0,
                    ),
                  );
              return AppSection(
                title: context.tr("Completed focus"),
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0)
                      const Divider(
                        height: 1,
                        indent: 72,
                        endIndent: Gap.lg,
                      ),
                    _MemberTile(
                      rank: i + 1,
                      member: rows[i],
                      isMe: rows[i].uid == uid,
                      active: rows[i].focusingAt(now),
                      week: week,
                      groupId: group.id,
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: Gap.md),
          TextButton.icon(
            onPressed: () => reportCommunityContent(
              context,
              uid: group.ownerUid,
              name: group.name,
              groupId: group.id,
            ),
            icon: const Icon(Icons.flag_outlined),
            label: Text(context.tr("Report group")),
          ),
          const SizedBox(height: Gap.xl),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _leave(group),
            icon: const Icon(Icons.logout_rounded),
            label: Text(
              _busy ? context.tr("Leaving…") : context.tr("Leave group"),
            ),
          ),
        ],
      ),
    );
  }
}

/// One member's row in a group: rank, name, live status and this week's hours.
///
/// The leader gets the group's colour; an active member gets a lit status dot.
/// The two are the same row otherwise, so the table reads as a ranking rather
/// than as a contact list with a number beside it.
class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.rank,
    required this.member,
    required this.isMe,
    required this.active,
    required this.week,
    required this.groupId,
  });

  final int rank;
  final GroupMember member;
  final bool isMe;
  final bool active;
  final String week;
  final String groupId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final medal = switch (rank) {
      1 => harmonize(const Color(0xFFB8860B), cs.primary),
      2 => cs.secondary,
      3 => cs.tertiary,
      _ => cs.onSurfaceVariant,
    };
    final hours = (member.week == week ? member.minutes : 0) / 60;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Gap.md,
        vertical: 2,
      ),
      leading: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: medal.withValues(alpha: rank <= 3 ? 0.14 : 0.0),
          shape: BoxShape.circle,
        ),
        child: Text(
          '$rank',
          style: tt.labelLarge?.copyWith(
            color: rank <= 3 ? medal : cs.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              member.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: Gap.xs),
            Text(
              '· ${context.tr("You")}',
              style: tt.labelSmall?.copyWith(color: cs.primary),
            ),
          ],
        ],
      ),
      subtitle: Row(
        children: [
          if (active) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.tertiary,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              active
                  ? context.tr("Focusing now")
                  : context.tr("Ready for another session"),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.labelMedium?.copyWith(
                color: active ? cs.tertiary : cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatHoursShort(hours),
            style: tt.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (!isMe)
            CommunityMemberMenu(
              uid: member.uid,
              name: member.name,
              groupId: groupId,
            ),
        ],
      ),
    );
  }
}
