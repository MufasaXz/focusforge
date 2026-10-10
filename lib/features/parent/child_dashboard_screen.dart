import '../../shared/widgets/glass_surface.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/models/parent.dart';
import '../../core/providers/parent_providers.dart';
import '../../core/services/parent_service.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/icon_badge.dart';
import '../../shared/widgets/progress_ring.dart';
import '../../shared/widgets/skeleton.dart';
import '../settings/settings_support.dart';
import 'widgets/week_strip.dart';

/// One child, as their parent sees them.
///
/// Three parts: the summary the child's device publishes — today's numbers and
/// the week's shape — the apps this parent keeps closed, and the four-digit
/// code that guards the link. The summary is deliberately small: minutes,
/// sessions, goal, streak, leading subject. A dashboard that showed the
/// session log would be a parent reading their child's whole day rather than
/// checking that the work is happening.
///
/// Every stream here is read with `valueOrNull`, never `value`: a denied or
/// offline read is a state this page has to draw, and `value` throws out of
/// the build when a stream is in error — which is what left the screen blank.
class ChildDashboardScreen extends ConsumerStatefulWidget {
  const ChildDashboardScreen({super.key, required this.childUid});

  final String childUid;

  @override
  ConsumerState<ChildDashboardScreen> createState() =>
      _ChildDashboardScreenState();
}

class _ChildDashboardScreenState extends ConsumerState<ChildDashboardScreen> {
  bool _unlinking = false;
  Future<void> _unlink(ChildLink child) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Unlink ${child.name}?',
      message: 'Their study summary will stop sharing and the Shield rules you set will lift.',
      confirmLabel: 'Unlink device',
      destructive: true,
      icon: Icons.link_off_rounded,
    );
    if (!confirmed || !mounted) return;
    setState(() => _unlinking = true);
    try {
      await ref.read(parentServiceProvider).unlink(child.uid);
      if (mounted) context.go(AppRoutes.paths[AppRoutes.parentControl]!);
    } on PairException catch (e) {
      if (mounted) {
        setState(() => _unlinking = false);
        showAppSnack(context, e.friendly);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    // Reached by deep link as well as by tapping a row, and the pickers on the
    // other screens read the selection rather than the route.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(selectedChildProvider.notifier).select(widget.childUid);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final children = ref.watch(childrenProvider);
    final list = children.valueOrNull ?? const <ChildLink>[];
    final child = list.where((c) => c.uid == widget.childUid).firstOrNull;

    final progressRead = ref.watch(childProgressProvider(widget.childUid));
    final blocksRead = ref.watch(childBlocksProvider(widget.childUid));
    final progress = progressRead.valueOrNull;
    final blocks = blocksRead.valueOrNull;

    // The list itself can fail or still be loading. Both are drawn rather than
    // fallen through: an empty page with a title is what a parent would report
    // as a broken screen.
    if (child == null && children.isLoading && list.isEmpty) {
      return AppPage(
        title: 'Child',
        subtitle: 'Their device',
        child: const SkeletonList(count: 4, itemHeight: 84),
      );
    }

    return AppPage(
      title: child?.name ?? 'Child',
      subtitle: 'Their device',
      trailing: list.length > 1
          ? _ChildSwitcher(current: widget.childUid)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (child == null)
            EmptyState(
              icon: Icons.link_off_rounded,
              title: children.hasError
                  ? 'Connection could not be checked'
                  : 'This child is not linked any more',
              subtitle: children.hasError
                  ? 'Their record could not be read just now. Pull the list '
                        'open again from Parent control.'
                  : 'Their device is no longer on your list, so there is '
                        'nothing here to watch or to block.',
              action: TextButton(
                onPressed: () =>
                    context.go(AppRoutes.paths[AppRoutes.parentControl]!),
                child: const Text('Back to Parent control'),
              ),
            )
          else ...[
            if (progressRead.hasError && progress == null)
              const _Unreachable(
                what: 'summary',
                body:
                    'Their phone publishes a summary as it is used, and this '
                    'device could not read it. It fills in as soon as the read '
                    'goes through.',
              )
            else if (progress == null || progress.updatedAt == null)
              const EmptyState(
                icon: Icons.hourglass_empty_rounded,
                title: 'Nothing from their device yet',
                subtitle:
                    'Their phone publishes a summary as it is used. This page '
                    'fills in as soon as it does.',
              )
            else
              _ProgressCard(progress: progress),
            const SizedBox(height: Gap.lg),
            if (blocksRead.hasError && blocks == null)
              const _Unreachable(
                what: 'block list',
                body:
                    'The rules set for their device could not be read just '
                    'now. Nothing has changed on their phone.',
              )
            else
              _BlocksSection(
                childUid: widget.childUid,
                blocks: blocks ?? const RemoteBlocks(),
              ),
            _SecurityCodeSection(childUid: widget.childUid, name: child.name),
            const SizedBox(height: Gap.lg),
            OutlinedButton.icon(
              onPressed: _unlinking ? null : () => _unlink(child),
              icon: const Icon(Icons.link_off_rounded),
              label: Text(_unlinking ? 'Unlinking…' : 'Unlink this device'),
            ),
          ],
        ],
      ),
    );
  }
}

/// A read that failed, said plainly.
class _Unreachable extends StatelessWidget {
  const _Unreachable({required this.what, required this.body});

  final String what;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card.outlined(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.cloud_off_rounded, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Can\'t read their $what',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Who this page is about, when there is more than one child to look at.
class _ChildSwitcher extends ConsumerWidget {
  const _ChildSwitcher({required this.current});

  final String current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children =
        ref.watch(childrenProvider).valueOrNull ?? const <ChildLink>[];

    return PopupMenuButton<String>(
      tooltip: 'Switch child',
      icon: const Icon(Icons.switch_account_rounded),
      onSelected: (uid) {
        if (uid == current) return;
        ref.read(selectedChildProvider.notifier).select(uid);
        context.pushReplacementNamed(
          AppRoutes.parentChild,
          pathParameters: {'uid': uid},
        );
      },
      itemBuilder: (context) => [
        for (final child in children)
          PopupMenuItem(
            value: child.uid,
            child: Row(
              children: [
                if (child.uid == current) ...[
                  const Icon(Icons.check_rounded, size: 16),
                  const SizedBox(width: Gap.sm),
                ],
                Text(child.name),
              ],
            ),
          ),
      ],
    );
  }
}

/// Today's numbers and the week's shape, with the age of the reading attached.
///
/// The date matters more than the numbers: a parent looking at "3h 20m" that
/// was published four days ago is looking at a stale reading, and a dashboard
/// that does not say so is lying by omission.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.progress});

  final ChildProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final today = _todayKey();
    final stale = progress.day != null && progress.day != today;

    return Card.outlined(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.hero),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ProgressRing(
                  value: progress.goalProgress,
                  size: 92,
                  stroke: 8,
                  semanticLabel:
                      '${progress.minutes} of ${progress.goalMinutes} minutes '
                      'today, ${(progress.goalProgress * 100).round()} percent',
                  child: Text(
                    '${(progress.goalProgress * 100).round()}%',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: Gap.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatHoursShort(progress.minutes / 60),
                        style: theme.textTheme.headlineSmall,
                      ),
                      Text(
                        'of a ${formatMinutes(progress.goalMinutes)} goal',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: Gap.sm),
                      Wrap(
                        spacing: Gap.sm,
                        runSpacing: Gap.xs,
                        children: [
                          _Chip(
                            icon: Icons.check_circle_outline_rounded,
                            label: progress.sessions == 1
                                ? '1 session'
                                : '${progress.sessions} sessions',
                          ),
                          if (progress.streak > 1)
                            _Chip(
                              icon: Icons.local_fire_department_rounded,
                              label: '${progress.streak}-day streak',
                            ),
                          if (progress.topSubject != null)
                            _Chip(
                              icon: Icons.menu_book_rounded,
                              label: progress.topSubject!,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.lg),
            WeekStrip(progress: progress),
            const SizedBox(height: Gap.md),
            Row(
              children: [
                Icon(
                  stale ? Icons.history_rounded : Icons.schedule_rounded,
                  size: 14,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: Gap.xs),
                Expanded(
                  child: Text(
                    stale
                        ? 'Last seen ${formatRelativeTime(progress.updatedAt!)} '
                              '— ${progress.day}'
                        : 'Updated ${formatRelativeTime(progress.updatedAt!)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
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

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

// -- Blocking ----------------------------------------------------------------

/// What is closed on their device, and the switch that decides whether any of
/// it is in force.
class _BlocksSection extends ConsumerWidget {
  const _BlocksSection({required this.childUid, required this.blocks});

  final String childUid;
  final RemoteBlocks blocks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'Blocks on their device',
          icon: Icons.block_rounded,
        ),
        GlassCard(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              SwitchListTile.adaptive(
                value: blocks.enforced,
                title: const Text('Enforce these blocks'),
                subtitle: Text(
                  blocks.enforced
                      ? 'Closed on their device now'
                      : 'Watching only — nothing is closed',
                ),
                onChanged: (value) =>
                    unawaited(_setEnforced(ref, childUid, value)),
              ),
              Divider(height: 1, color: cs.outlineVariant),
              for (final app in blocks.apps)
                ListTile(
                  leading: IconBadge(
                    icon: app.focusOnly
                        ? Icons.hourglass_bottom_rounded
                        : Icons.block_rounded,
                    color: app.focusOnly
                        ? const Color(0xFFFFD08A)
                        : const Color(0xFFB79CFF),
                  ),
                  title: Text(app.name),
                  subtitle: Text(
                    app.focusOnly
                        ? 'Closed only while they are focusing'
                        : 'Closed all day',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: 'Remove ${app.name}',
                    onPressed: () => unawaited(_removeApp(ref, childUid, app)),
                  ),
                ),
              if (blocks.apps.isEmpty)
                ListTile(
                  leading: Icon(Icons.apps_rounded, color: cs.onSurfaceVariant),
                  title: const Text('No apps blocked'),
                  subtitle: const Text('Add one from their app list'),
                ),
              ListTile(
                leading: const IconBadge(
                  icon: Icons.add_rounded,
                  color: Color(0xFF7FA9FF),
                ),
                title: const Text('Add apps to block'),
                subtitle: const Text('From the apps on their device'),
                onTap: () => unawaited(_addApps(context, ref, childUid)),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),
        Text(
          'Their device picks these up the next time it is online. The Shield '
          'tab blocks their apps too, and reaches the same list.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Gap.xl),
      ],
    );
  }
}

Future<void> _setEnforced(WidgetRef ref, String childUid, bool value) async {
  final current =
      ref.read(childBlocksProvider(childUid)).valueOrNull ??
      const RemoteBlocks();
  await ref
      .read(parentServiceProvider)
      .publishBlocks(childUid, current.copyWith(enforced: value));
}

Future<void> _removeApp(WidgetRef ref, String childUid, RemoteBlock app) async {
  final current =
      ref.read(childBlocksProvider(childUid)).valueOrNull ??
      const RemoteBlocks();
  await ref
      .read(parentServiceProvider)
      .publishBlocks(
        childUid,
        current.copyWith(
          apps: [
            for (final a in current.apps)
              if (a.packageId != app.packageId) a,
          ],
        ),
      );
}

/// Picks apps from the child's own list.
///
/// The list comes from the child's device because that is the only place that
/// knows what is installed. A parent choosing from a canned catalogue of
/// famous apps would be choosing a name, not an app.
Future<void> _addApps(
  BuildContext context,
  WidgetRef ref,
  String childUid,
) async {
  final catalog = ref.read(childCatalogProvider(childUid)).valueOrNull;
  if (catalog == null || catalog.isEmpty) {
    showAppSnack(
      context,
      'Their device has not sent its app list yet. It does that while the '
      'app is open and linked.',
    );
    return;
  }
  final current =
      ref.read(childBlocksProvider(childUid)).valueOrNull ??
      const RemoteBlocks();

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) =>
        _AppPickerSheet(childUid: childUid, catalog: catalog, blocks: current),
  );
}

class _AppPickerSheet extends ConsumerStatefulWidget {
  const _AppPickerSheet({
    required this.childUid,
    required this.catalog,
    required this.blocks,
  });

  final String childUid;
  final List<CatalogApp> catalog;
  final RemoteBlocks blocks;

  @override
  ConsumerState<_AppPickerSheet> createState() => _AppPickerSheetState();
}

class _AppPickerSheetState extends ConsumerState<_AppPickerSheet> {
  late RemoteBlocks _blocks = widget.blocks;
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<CatalogApp> get _visible {
    final q = _query.trim().toLowerCase();
    final matches = q.isEmpty
        ? widget.catalog
        : [
            for (final app in widget.catalog)
              if (app.name.toLowerCase().contains(q) ||
                  app.packageId.toLowerCase().contains(q))
                app,
          ];
    return matches.take(200).toList(growable: false);
  }

  Future<void> _toggle(CatalogApp app) async {
    final blocked = _blocks.apps.any((a) => a.packageId == app.packageId);
    final next = blocked
        ? [
            for (final a in _blocks.apps)
              if (a.packageId != app.packageId) a,
          ]
        : [
            ..._blocks.apps,
            RemoteBlock(packageId: app.packageId, name: app.name),
          ];
    final updated = _blocks.copyWith(apps: next);
    setState(() => _blocks = updated);
    await ref
        .read(parentServiceProvider)
        .publishBlocks(widget.childUid, updated);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final visible = _visible;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Apps on their device',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  '${_blocks.apps.length} blocked · changes arrive on their '
                  'phone the next time it is online',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: Gap.md),
                TextField(
                  controller: _search,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    hintText: 'Search apps',
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: controller,
              padding: EdgeInsets.only(
                bottom: Gap.xl + MediaQuery.paddingOf(context).bottom,
              ),
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final app = visible[index];
                final block = _blocks.apps
                    .where((a) => a.packageId == app.packageId)
                    .firstOrNull;
                return ListTile(
                  title: Text(app.name),
                  subtitle: Text(
                    block == null
                        ? app.packageId
                        : block.focusOnly
                        ? 'Blocked while focusing'
                        : 'Blocked all day',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  leading: Switch.adaptive(
                    value: block != null,
                    onChanged: (_) => unawaited(_toggle(app)),
                  ),
                  // A second tap on an already-blocked row is the way to say
                  // "only while focusing" — the third state a switch cannot
                  // show.
                  trailing: block == null
                      ? null
                      : IconButton(
                          tooltip: block.focusOnly
                              ? 'Block all day instead'
                              : 'Block only while focusing',
                          icon: Icon(
                            block.focusOnly
                                ? Icons.hourglass_bottom_rounded
                                : Icons.calendar_today_rounded,
                            size: 18,
                          ),
                          onPressed: () => unawaited(_setFocusOnly(app, block)),
                        ),
                  onTap: () => unawaited(_toggle(app)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setFocusOnly(CatalogApp app, RemoteBlock block) async {
    final updated = _blocks.copyWith(
      apps: [
        for (final a in _blocks.apps)
          if (a.packageId == app.packageId)
            RemoteBlock(
              packageId: a.packageId,
              name: a.name,
              focusOnly: !a.focusOnly,
            )
          else
            a,
      ],
    );
    setState(() => _blocks = updated);
    await ref
        .read(parentServiceProvider)
        .publishBlocks(widget.childUid, updated);
  }
}

// -- The security code -------------------------------------------------------

/// The four digits a parent sets, and the child's way past them.
///
/// Set here, on the parent's phone, and carried in the link record itself: the
/// child's device checks what was typed against the digest, and the parent's
/// app is the only place the code can be armed or changed. It is a speed bump,
/// not a lock — a child can still clear the app's data — and the sheet says so
/// rather than implying otherwise.
class _SecurityCodeSection extends ConsumerWidget {
  const _SecurityCodeSection({required this.childUid, required this.name});

  final String childUid;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final code = ref.watch(childGuardianProvider(childUid)).valueOrNull?.code;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Security code', icon: Icons.lock_rounded),
        GlassCard(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: IconBadge(
              icon: code == null ? Icons.lock_open_rounded : Icons.lock_rounded,
              color: const Color(0xFFFFD08A),
            ),
            title: Text(
              code == null
                  ? 'Set a four-digit code'
                  : 'A code is set for $name',
            ),
            subtitle: Text(
              code == null
                  ? '$name\'s device can unlink itself without asking'
                  : '$name must enter it to unlink their device',
            ),
            trailing: const AppChevron(),
            onTap: () => unawaited(
              code == null
                  ? _setCode(context, ref, childUid, name)
                  : _changeCode(context, ref, childUid, name),
            ),
          ),
        ),
        const SizedBox(height: Gap.md),
        Text(
          'A speed bump, not a lock: clearing the app\'s data or uninstalling '
          'it removes the link along with everything else. The same code '
          'unlocks the shield on $name\'s device.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: Gap.xl),
      ],
    );
  }
}

Future<void> _setCode(
  BuildContext context,
  WidgetRef ref,
  String childUid,
  String name,
) async {
  final code = await showAppInputDialog(
    context: context,
    title: 'Set a four-digit code',
    message:
        'Pick four digits only you and $name know. $name will need them to '
        'unlink their device, and to change the shield on it.',
    actionLabel: 'Set code',
    hintText: 'Four digits',
    icon: Icons.lock_rounded,
    keyboardType: TextInputType.number,
  );
  if (code == null) return;
  if (!ParentCode.looksValid(code)) {
    if (context.mounted) showAppSnack(context, 'Use exactly four digits.');
    return;
  }
  if (!context.mounted) return;
  await _publish(context, ref, childUid, ParentCode.of(code), 'Code set.');
}

Future<void> _changeCode(
  BuildContext context,
  WidgetRef ref,
  String childUid,
  String name,
) async {
  final action = await showAppDialog<String>(
    context: context,
    builder: (context) => _CodeActions(name: name),
  );
  if (action == null || !context.mounted) return;
  if (action == 'change') {
    await _setCode(context, ref, childUid, name);
    return;
  }
  await _publish(context, ref, childUid, null, 'Code removed.');
}

/// Writes the code to the link record and says what happened.
Future<void> _publish(
  BuildContext context,
  WidgetRef ref,
  String childUid,
  ParentCode? code,
  String done,
) async {
  try {
    await ref.read(parentServiceProvider).publishCode(childUid, code);
    if (context.mounted) showAppSnack(context, done);
  } on PairException catch (error) {
    if (context.mounted) showAppSnack(context, error.friendly);
  }
}

class _CodeActions extends StatelessWidget {
  const _CodeActions({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const IconBadge(
              icon: Icons.lock_rounded,
              color: Color(0xFFFFD08A),
              size: 40,
              radius: 12,
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(
                'The code for $name',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.lg),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.password_rounded),
          title: const Text('Set a new code'),
          onTap: () => Navigator.of(context).pop('change'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.lock_open_rounded),
          title: const Text('Remove the code'),
          subtitle: const Text('Their device can unlink itself again'),
          onTap: () => Navigator.of(context).pop('remove'),
        ),
        const SizedBox(height: Gap.md),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// `yyyy-mm-dd`, matching what the child's device writes.
String _todayKey() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}
