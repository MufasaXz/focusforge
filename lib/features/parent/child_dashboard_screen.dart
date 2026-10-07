import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/parent.dart';
import '../../core/providers/parent_providers.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/icon_badge.dart';
import '../../shared/widgets/progress_ring.dart';
import '../settings/settings_support.dart';

/// One child, as their parent sees them.
///
/// Two halves: the summary the child's device publishes, and the block list
/// this device sets. The summary is deliberately small — minutes, sessions,
/// goal, streak, leading subject — because a dashboard that showed the session
/// log would be a parent reading their child's whole day rather than checking
/// that the work is happening.
class ChildDashboardScreen extends ConsumerStatefulWidget {
  const ChildDashboardScreen({super.key, required this.childUid});

  final String childUid;

  @override
  ConsumerState<ChildDashboardScreen> createState() =>
      _ChildDashboardScreenState();
}

class _ChildDashboardScreenState extends ConsumerState<ChildDashboardScreen> {
  @override
  void initState() {
    super.initState();
    // Reached by deep link as well as by tapping a row, and the picker sheet
    // reads the selection rather than the route.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(selectedChildProvider.notifier).select(widget.childUid);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final children = ref.watch(childrenProvider).value ?? const <ChildLink>[];
    final child = children
        .where((c) => c.uid == widget.childUid)
        .firstOrNull;
    final progress = ref.watch(childProgressProvider(widget.childUid)).value;
    final blocks = ref.watch(childBlocksProvider(widget.childUid)).value;

    return AppPage(
      title: child?.name ?? 'Child',
      subtitle: 'Their device',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (progress == null || progress.updatedAt == null)
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
          _BlocksSection(
            childUid: widget.childUid,
            blocks: blocks ?? const RemoteBlocks(),
          ),
        ],
      ),
    );
  }
}

/// Today's numbers, with the age of the reading attached.
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
        Card.filled(
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
                onChanged: (value) => unawaited(_setEnforced(ref, value)),
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
                    onPressed: () => unawaited(_removeApp(ref, app)),
                  ),
                ),
              if (blocks.apps.isEmpty)
                ListTile(
                  leading: Icon(
                    Icons.apps_rounded,
                    color: cs.onSurfaceVariant,
                  ),
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
                onTap: () => unawaited(_addApps(context, ref)),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),
        Text(
          'Their device picks these up the next time it is online. YouTube is '
          'blocked from the Shield screen on their device.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Gap.xl),
      ],
    );
  }
}

Future<void> _setEnforced(WidgetRef ref, bool value) async {
  final childUid = ref.read(selectedChildProvider);
  if (childUid == null) return;
  final current =
      ref.read(childBlocksProvider(childUid)).value ?? const RemoteBlocks();
  await ref
      .read(parentServiceProvider)
      .publishBlocks(childUid, current.copyWith(enforced: value));
}

Future<void> _removeApp(WidgetRef ref, RemoteBlock app) async {
  final childUid = ref.read(selectedChildProvider);
  if (childUid == null) return;
  final current =
      ref.read(childBlocksProvider(childUid)).value ?? const RemoteBlocks();
  await ref.read(parentServiceProvider).publishBlocks(
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
Future<void> _addApps(BuildContext context, WidgetRef ref) async {
  final childUid = ref.read(selectedChildProvider);
  if (childUid == null) return;
  final catalog = ref.read(childCatalogProvider(childUid)).value;
  if (catalog == null || catalog.isEmpty) {
    showAppSnack(
      context,
      'Their device has not sent its app list yet. It does that while the '
      'app is open and linked.',
    );
    return;
  }
  final current =
      ref.read(childBlocksProvider(childUid)).value ?? const RemoteBlocks();

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _AppPickerSheet(
      childUid: childUid,
      catalog: catalog,
      blocks: current,
    ),
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
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
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

/// `yyyy-mm-dd`, matching what the child's device writes.
String _todayKey() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}
