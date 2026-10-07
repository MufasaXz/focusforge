import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/shell/app_shell.dart';
import '../../app/theme/app_theme.dart';
import '../../core/models/parent.dart';
import '../../core/models/shield.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/parent_providers.dart';
import '../../core/providers/shield_providers.dart';
import '../../core/providers/usage_providers.dart';
import '../../core/services/app_catalog.dart';
import '../../core/services/native_shield_service.dart';
import '../../core/services/parent_service.dart';
import '../../core/services/permission_manager.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/app_icon_avatar.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/icon_badge.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/stagger.dart';
import '../../shared/widgets/sheet_chrome.dart';
import '../parent/parent_lock.dart';
import '../parent/widgets/child_switcher.dart';
import '../settings/settings_support.dart';
import 'breath_gate.dart';

/// Tab 2 — the shielding engine.
///
/// Three faces of one system: the apps the user has put in a tier, the YouTube
/// surfaces that are closed, and what the engine has actually done. Everything
/// on screen is read from `shield_providers`; the only local state is which
/// face is showing and which sheet is open. A control that changed only local
/// state would be a switch that lies — every mutation has to reach its
/// notifier, because that is what persists the rule and pushes it to the
/// native service.
///
/// On a parent's device the tab is about their child instead: the app list is
/// the child's, published by their phone, and a switch here writes a rule that
/// phone picks up. The child's own screen is unchanged — it still manages the
/// apps on the device in your hand.
///
/// The header is a solid surface pinned over the list: content scrolls
/// underneath it, and the tonal edge keeps the two apart. No blur here — the
/// design reserves real backdrop filters for the nav bar, the sheets and the
/// breath gate.
class ShieldScreen extends ConsumerStatefulWidget {
  const ShieldScreen({super.key});

  @override
  ConsumerState<ShieldScreen> createState() => _ShieldScreenState();
}

class _ShieldScreenState extends ConsumerState<ShieldScreen>
    with WidgetsBindingObserver {
  static const _segmentOptions = ['Apps', 'YouTube', 'Activity'];

  /// A parent's tab has no Activity segment: the interceptions it reports are
  /// this device's, and this device is not the one being shielded.
  static const _parentSegments = ['Apps', 'YouTube'];

  int _segment = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The user leaves to grant accessibility or usage access, and comes back.
  ///
  /// Everything read from the platform is re-read here: the grant happens in
  /// Android's settings while this app is not running, so a value cached
  /// before the trip would still say "off" after it. The protected set is
  /// re-read with them, because the trip may also have changed the keyboard
  /// or the launcher — and those are exactly the packages the list drops.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    ref.invalidate(shieldEnabledProvider);
    ref.invalidate(usageAccessProvider);
    ref.invalidate(appUsageTodayProvider);
    ref.invalidate(installedAppsProvider);
    ref.invalidate(protectedPackagesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final topInset = MediaQuery.paddingOf(context).top;

    final user = ref.watch(userProvider);
    final isParent = user.isGuardian;
    final children =
        ref.watch(childrenProvider).valueOrNull ?? const <ChildLink>[];
    final child = isParent ? ref.watch(activeChildProvider) : null;
    final childBlocks = child == null
        ? null
        : ref.watch(childBlocksProvider(child.uid)).valueOrNull;

    // The segments follow the role, and the selection is clamped so switching
    // roles with Activity showing cannot index past the shorter list.
    final segments = isParent ? _parentSegments : _segmentOptions;
    final segment = _segment.clamp(0, segments.length - 1);

    // The switcher rides in the pinned header rather than in each segment's
    // list: whose apps these are is a fact about the whole tab, and it has to
    // stay on screen while the user scrolls their child's app list.
    final showSwitcher = isParent && children.isNotEmpty;
    final headerHeight = 172 + topInset + (showSwitcher ? 56 : 0);

    final armed = ref.watch(activeShieldCountProvider);

    return Stack(
      children: [
        Positioned.fill(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Layout.readable),
              // The entrance waits for the branch to be on screen; see
              // [_TabEntrance].
              child: _TabEntrance(
                // Each segment owns its own scroll view. The app list is the
                // whole device — hundreds of rows on a real phone — and a
                // single `ListView` holding all of them would build every row,
                // every toggle and every icon before the first one was
                // painted. Only the app list needs that; the other two stay as
                // they were.
                child: switch ((isParent, segment)) {
                  (true, _) when child == null => _SegmentScroll(
                    topPadding: headerHeight + Gap.md,
                    child: const _NoChildrenYet(),
                  ),
                  (true, 0) => _ChildAppsView(
                    childUid: child!.uid,
                    childName: child.name,
                    topPadding: headerHeight + Gap.md,
                  ),
                  (true, _) => _SegmentScroll(
                    topPadding: headerHeight + Gap.md,
                    child: _ChildYoutubeView(
                      childUid: child!.uid,
                      childName: child.name,
                    ),
                  ),
                  (false, 0) => _AppsView(topPadding: headerHeight + Gap.md),
                  (false, 1) => _SegmentScroll(
                    topPadding: headerHeight + Gap.md,
                    child: const _YoutubeView(),
                  ),
                  (false, _) => _SegmentScroll(
                    topPadding: headerHeight + Gap.md,
                    child: const _ActivityView(),
                  ),
                },
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          // A solid surface, not a frosted bar: M3 expresses layering through
          // surface tone, and a backdrop filter here would be spent on chrome
          // that never moves. The band is full width; its contents are not.
          child: Container(
            color: cs.surface,
            padding: EdgeInsets.fromLTRB(
              Gap.lg + 4,
              topInset + Gap.lg,
              Gap.lg + 4,
              Gap.lg,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Layout.readable),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Shield',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(fontSize: 24),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isParent
                                    ? 'Close what pulls them away'
                                    : 'Close what pulls you away',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: Gap.md),
                        _ShieldStatusPill(
                          armed: isParent
                              ? (childBlocks?.apps.length ?? 0)
                              : armed,
                          label: isParent
                              ? childBlocks == null
                                    ? 'Reading…'
                                    : childBlocks.apps.isEmpty
                                    ? 'Nothing blocked'
                                    : '${childBlocks.apps.length} blocked'
                              : null,
                          locked: !isParent && ref.watch(parentLockedProvider),
                          // A parent's badge is the way into the child's
                          // dashboard; their own device has nothing to unlock.
                          onTap: isParent
                              ? child == null
                                    ? null
                                    : () => _openChild(child)
                              : _showStatusSheet,
                        ),
                      ],
                    ),
                    const SizedBox(height: Gap.lg),
                    // `double.infinity` makes the button fill the column: the
                    // M3 segmented button otherwise shrink-wraps its segments.
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<int>(
                        segments: [
                          for (var i = 0; i < segments.length; i++)
                            ButtonSegment(value: i, label: Text(segments[i])),
                        ],
                        selected: {segment},
                        showSelectedIcon: false,
                        onSelectionChanged: (selection) =>
                            setState(() => _segment = selection.first),
                      ),
                    ),
                    if (showSwitcher) ...[
                      const SizedBox(height: Gap.md),
                      SizedBox(
                        height: 36,
                        child: children.length > 1
                            ? const ChildChips()
                            : Row(
                                children: [
                                  Icon(
                                    Icons.smartphone_rounded,
                                    size: 15,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: Gap.sm),
                                  Expanded(
                                    child: Text(
                                      '${children.first.name}\'s phone',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The selected child's own page, from the badge.
  void _openChild(ChildLink child) {
    context.pushNamed(
      AppRoutes.parentChild,
      pathParameters: {'uid': child.uid},
    );
  }

  /// The live state of the engine, in plain language.
  ///
  /// The pill is the only place a user can find out that a rule exists but
  /// cannot fire — a budget with no usage access, or a service that has been
  /// switched off in Android's settings — so the sheet names those states
  /// rather than leaving them to be inferred from a grey switch.
  void _showStatusSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _ShieldStatusSheet(
        onPreviewGate: () {
          final blocked = ref
              .read(whitelistProvider)
              .where((e) => e.tier == WhitelistTier.blocked)
              .firstOrNull;
          Navigator.of(sheetContext).pop();
          // No package: a preview is not an interception. The gate leaves the
          // impulse log and the hand-back alone when there is nothing real
          // behind it.
          context.push(
            AppRoutes.paths[AppRoutes.breathGate]!,
            extra: BreathGateArgs(appName: blocked?.name ?? 'YouTube'),
          );
        },
      ),
    );
  }
}

/// The header badge. It reads as a status, but it is really a button — the
/// tappable target is the whole pill, not just the dot.
class _ShieldStatusPill extends StatelessWidget {
  const _ShieldStatusPill({
    required this.armed,
    required this.locked,
    this.label,
    this.onTap,
  });

  final int armed;

  /// True while a linked parent's code stands in front of rule changes.
  final bool locked;

  /// Overrides the count wording — a parent's pill counts their child's blocks
  /// rather than this device's rules, and "armed" would be the wrong word for
  /// a list that is enforced somewhere else.
  final String? label;

  /// Null when there is nothing to open, which is also what makes the pill a
  /// plain badge rather than a control.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final on = armed > 0;
    final color = on ? cs.tertiary : cs.onSurfaceVariant;
    final text = label ?? (on ? '$armed armed' : 'Nothing armed');

    return Semantics(
      button: onTap != null,
      container: true,
      label:
          'Shield status. $text.'
          '${locked ? ' Locked by a parent.' : ''}'
          '${onTap == null ? '' : ' Double tap for details.'}',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Pressable(
          scale: 0.94,
          onTap: onTap,
          // A tonal status pill. The armed state is carried by the tertiary
          // border and the dot, not by a glow.
          child: Card.filled(
            shape: StadiumBorder(
              side: BorderSide(color: on ? cs.tertiary : cs.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.md,
                vertical: 16,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The lock rides in the pill rather than in a banner: it is
                  // a property of every rule on the screen, and the header has
                  // no room for a second row.
                  if (locked) ...[
                    Icon(
                      Icons.lock_rounded,
                      size: 12,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    text,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
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

/// What is armed, what is inert, and why.
class _ShieldStatusSheet extends ConsumerWidget {
  const _ShieldStatusSheet({required this.onPreviewGate});

  final VoidCallback onPreviewGate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final enabled = ref.watch(shieldEnabledProvider).valueOrNull ?? false;
    final native = NativeShieldService.isSupported;
    final blocked = ref.watch(blockedAppsProvider).length;
    final budgeted = ref.watch(budgetedAppsProvider).length;
    final youtube = ref.watch(youtubeRulesProvider);
    final strict = ref.watch(strictModeProvider);
    final usageAccess = ref.watch(usageAccessProvider).valueOrNull ?? false;
    final inert = budgeted > 0 && !usageAccess;

    return SheetSurface(
      padding: const EdgeInsets.all(Gap.xl),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              const SizedBox(height: Gap.lg),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'What is being enforced',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Live state of the shield engine',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  SheetCloseButton(
                    label: 'Close status',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: Gap.lg),
              if (native)
                _StatusLine(
                  icon: enabled
                      ? Icons.verified_user_rounded
                      : Icons.gpp_bad_rounded,
                  color: enabled ? cs.tertiary : cs.error,
                  label: 'App blocking',
                  value: enabled ? 'On' : 'Off',
                ),
              _StatusLine(
                icon: Icons.block_rounded,
                color: blocked > 0 ? cs.tertiary : cs.onSurfaceVariant,
                label: 'Apps blocked',
                value: '$blocked',
              ),
              _StatusLine(
                icon: Icons.hourglass_bottom_rounded,
                color: budgeted > 0
                    ? harmonize(WhitelistTier.budgeted.color, cs.primary)
                    : cs.onSurfaceVariant,
                label: 'Time budgets',
                value: budgeted == 0
                    ? 'None'
                    : usageAccess
                    ? '$budgeted running'
                    : '$budgeted, not reading usage',
              ),
              _StatusLine(
                icon: Icons.smart_display_rounded,
                color: youtube.any ? cs.tertiary : cs.onSurfaceVariant,
                label: 'YouTube',
                value: switch ((youtube.shorts, youtube.feed)) {
                  (true, true) => 'Shorts and feeds closed',
                  (true, false) => 'Shorts closed',
                  (false, true) => 'Feeds closed',
                  _ => 'Untouched',
                },
              ),
              _StatusLine(
                icon: Icons.lock_rounded,
                color: strict.enabled ? cs.tertiary : cs.onSurfaceVariant,
                label: 'Strict mode',
                value: strict.enabled
                    ? '${strict.durationMinutes} min session'
                    : 'Off',
              ),
              if (ref.watch(parentLockedProvider))
                _StatusLine(
                  icon: Icons.family_restroom_rounded,
                  color: cs.primary,
                  label: 'Parent\'s code',
                  value: 'Asked for before any rule changes',
                ),
              if (!native || !enabled || inert) ...[
                const SizedBox(height: Gap.md),
                // The honest footnote. A rule that cannot fire is worse than
                // no rule, because the user believes they are covered.
                Card.outlined(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.item),
                    side: BorderSide(color: cs.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.md),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: Gap.sm),
                        Expanded(
                          child: Text(
                            !native
                                ? 'App blocking runs on Android. On this '
                                      'build the rules are saved and shown, '
                                      'and nothing is closed.'
                                : !enabled
                                ? 'Android\'s accessibility service is off, so '
                                      'no app can be closed. Turn it on from '
                                      'the Apps tab.'
                                : 'Time budgets need usage access before they '
                                      'can count anything. Grant it from the '
                                      'Apps tab.',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: Gap.md),
              Divider(color: cs.outlineVariant, height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.air_outlined, color: cs.primary),
                title: const Text('Preview the pause screen'),
                subtitle: const Text(
                  'The 4-7-8 breath exercise shown before a blocked app opens',
                ),
                onTap: onPreviewGate,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.sm),
        child: Row(
          children: [
            IconBadge(icon: icon, color: color, size: 34, radius: 10),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
            ),
            const SizedBox(width: Gap.sm),
            Text(
              value,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// 48dp close affordance shared by the sheets on this screen.
// ---------------------------------------------------------------------------
// Apps
// ---------------------------------------------------------------------------

/// One segment's worth of content in the screen's standard padding.
///
/// Used by the two segments that are a short, fixed set of sections. The app
/// list does not use it — it builds its own slivers so it can be lazy.
class _SegmentScroll extends StatelessWidget {
  const _SegmentScroll({required this.topPadding, required this.child});

  final double topPadding;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.fromLTRB(
      Gap.lg + 4,
      topPadding,
      Gap.lg + 4,
      kNavBarClearance,
    ),
    children: [child],
  );
}

/// Every app on the device, with a switch on each row.
///
/// There is no "add apps" step and no allowed/blocked split: the list is the
/// device, and a rule is something switched on a row that is already there.
/// The grouping that used to head this screen answered a question nobody asks
/// — "which of my rules are of which kind" — while hiding the one that matters,
/// which is "is this app closed".
class _AppsView extends ConsumerStatefulWidget {
  const _AppsView({required this.topPadding});

  final double topPadding;

  @override
  ConsumerState<_AppsView> createState() => _AppsViewState();
}

class _AppsViewState extends ConsumerState<_AppsView> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final query = _search.text.trim().toLowerCase();

    final all = ref.watch(shieldAppRowsProvider);
    final loading = ref.watch(installedAppsProvider).isLoading;

    final native = NativeShieldService.isSupported;
    final enabled = ref.watch(shieldEnabledProvider).valueOrNull ?? false;
    final usageAccess = ref.watch(usageAccessProvider).valueOrNull ?? false;
    final budgeted = ref.watch(budgetedAppsProvider).length;

    final visible = query.isEmpty
        ? all
        : all
              .where((r) => r.name.toLowerCase().contains(query))
              .toList(growable: false);

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            Gap.lg + 4,
            widget.topPadding,
            Gap.lg + 4,
            0,
          ),
          sliver: SliverList.list(
            children: [
              if (native && !enabled)
                const _PermissionGate(
                  icon: Icons.accessibility_new_rounded,
                  title: 'Turn on app blocking',
                  body:
                      'Android closes an app through its accessibility '
                      'service. FocusForge needs it on before a single rule can '
                      'do anything.',
                  action: 'Open accessibility settings',
                  permission: AppPermission.accessibility,
                ),
              if (native && enabled && budgeted > 0 && !usageAccess)
                const _PermissionGate(
                  icon: Icons.timelapse_rounded,
                  title: 'Time budgets are not counting',
                  body:
                      'A budget needs to read how long an app has been open. '
                      'Without usage access it is armed but inert.',
                  action: 'Open usage access settings',
                  permission: AppPermission.usageAccess,
                ),
              _SearchField(
                controller: _search,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: Gap.xl),
              _ListHeading(
                title: query.isEmpty ? 'All apps' : 'Results',
                note: loading ? 'Reading the device…' : null,
                icon: Icons.apps_rounded,
              ),
              const SizedBox(height: Gap.sm),
            ],
          ),
        ),
        if (loading)
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: Gap.lg + 4),
            sliver: SliverToBoxAdapter(child: SkeletonList(count: 6)),
          )
        else if (visible.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg + 4),
            sliver: SliverToBoxAdapter(
              child: all.isEmpty
                  ? const _NoApps()
                  : _NoMatches(query: _search.text.trim()),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg + 4),
            sliver: SliverList.separated(
              itemCount: visible.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: cs.outlineVariant.withValues(alpha: 0.35),
              ),
              itemBuilder: (context, i) => _AppRuleRow(
                row: visible[i],
                onOpen: () => _openRule(visible[i]),
              ),
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            Gap.lg + 4,
            Gap.xl,
            Gap.lg + 4,
            kNavBarClearance,
          ),
          sliver: SliverToBoxAdapter(
            child: Text(
              'A rule applies the moment you switch it on — there is nothing '
              'to enable afterwards.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }

  /// Opens the full rule for an app: closed, budgeted, or never closed.
  void _openRule(ShieldAppRow row) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => AppRuleSheet(
        packageId: row.packageId,
        name: row.name,
        icon: Icons.android_rounded,
        usedMinutes: row.usedMinutes,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The parent's shield: the selected child's phone
// ---------------------------------------------------------------------------

/// A parent with no children linked yet.
///
/// The tab cannot show another device's apps until there is another device, and
/// saying so is more useful than an empty list that looks like a failed read.
class _NoChildrenYet extends StatelessWidget {
  const _NoChildrenYet();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: Gap.xl),
      child: Card.filled(
        child: Padding(
          padding: const EdgeInsets.all(Gap.xl),
          child: Column(
            children: [
              Icon(
                Icons.child_care_rounded,
                size: 48,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(height: Gap.lg),
              Text(
                'No child linked yet',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Gap.sm),
              Text(
                'This tab closes apps on your child\'s phone. Open Profile → '
                'Parent control and add a child with the six digits their '
                'phone shows; their app list arrives here.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The selected child's apps, with this parent's rules on them.
///
/// The list is the child's, not this device's: their phone publishes it, and a
/// switch here writes a rule their phone picks up. A parent choosing from the
/// apps on their own phone would be choosing apps their child may not have.
class _ChildAppsView extends ConsumerStatefulWidget {
  const _ChildAppsView({
    required this.childUid,
    required this.childName,
    required this.topPadding,
  });

  final String childUid;
  final String childName;
  final double topPadding;

  @override
  ConsumerState<_ChildAppsView> createState() => _ChildAppsViewState();
}

class _ChildAppsViewState extends ConsumerState<_ChildAppsView> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final query = _search.text.trim().toLowerCase();

    // `valueOrNull` on both reads: a denied or offline stream is a state this
    // list has to draw, and `value` would throw out of the build instead.
    final catalogRead = ref.watch(childCatalogProvider(widget.childUid));
    final blocksRead = ref.watch(childBlocksProvider(widget.childUid));
    final catalog = catalogRead.valueOrNull ?? const <CatalogApp>[];
    final blocks = blocksRead.valueOrNull ?? const RemoteBlocks();
    final loading = catalogRead.isLoading || blocksRead.isLoading;

    final visible = query.isEmpty
        ? catalog
        : [
            for (final app in catalog)
              if (app.name.toLowerCase().contains(query) ||
                  app.packageId.toLowerCase().contains(query))
                app,
          ];

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            Gap.lg + 4,
            widget.topPadding,
            Gap.lg + 4,
            0,
          ),
          sliver: SliverList.list(
            children: [
              _EnforceRow(
                childUid: widget.childUid,
                childName: widget.childName,
                blocks: blocks,
              ),
              const SizedBox(height: Gap.lg),
              _SearchField(
                controller: _search,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: Gap.xl),
              _ListHeading(
                title: query.isEmpty ? 'Their apps' : 'Results',
                note: loading && catalog.isEmpty
                    ? 'Reading their device…'
                    : catalog.isEmpty
                    ? null
                    : '${blocks.apps.length} blocked',
                icon: Icons.apps_rounded,
              ),
              const SizedBox(height: Gap.sm),
            ],
          ),
        ),
        if (loading && catalog.isEmpty)
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: Gap.lg + 4),
            sliver: SliverToBoxAdapter(child: SkeletonList(count: 6)),
          )
        else if (catalog.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg + 4),
            sliver: SliverToBoxAdapter(
              child: _NoChildApps(
                name: widget.childName,
                failed: catalogRead.hasError,
              ),
            ),
          )
        else if (visible.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg + 4),
            sliver: SliverToBoxAdapter(
              child: _NoMatches(query: _search.text.trim()),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg + 4),
            sliver: SliverList.separated(
              itemCount: visible.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: cs.outlineVariant.withValues(alpha: 0.35),
              ),
              itemBuilder: (context, i) => _ChildAppRow(
                childUid: widget.childUid,
                app: visible[i],
                block: blocks.apps
                    .where((a) => a.packageId == visible[i].packageId)
                    .firstOrNull,
              ),
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            Gap.lg + 4,
            Gap.xl,
            Gap.lg + 4,
            kNavBarClearance,
          ),
          sliver: SliverToBoxAdapter(
            child: Text(
              'A switch here writes a rule for ${widget.childName}\'s phone. '
              'It applies the next time their device is online.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }
}

/// Whether any of it is closed at all.
///
/// Its own row rather than a corner of the list: a parent who set rules while
/// "watching only" is looking at a list that promises nothing, and the one
/// switch that changes that has to be visible without scrolling for it.
class _EnforceRow extends ConsumerWidget {
  const _EnforceRow({
    required this.childUid,
    required this.childName,
    required this.blocks,
  });

  final String childUid;
  final String childName;
  final RemoteBlocks blocks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Card.filled(
      clipBehavior: Clip.antiAlias,
      color: blocks.enforced ? null : cs.errorContainer,
      child: SwitchListTile.adaptive(
        value: blocks.enforced,
        secondary: Icon(
          blocks.enforced
              ? Icons.shield_rounded
              : Icons.visibility_outlined,
          color: blocks.enforced ? cs.tertiary : cs.onErrorContainer,
        ),
        title: Text(
          blocks.enforced ? 'Closed on their phone' : 'Watching only',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        subtitle: Text(
          blocks.enforced
              ? 'Rules below apply on $childName\'s device'
              : 'Nothing is closed on $childName\'s device yet',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: blocks.enforced ? cs.onSurfaceVariant : cs.onErrorContainer,
          ),
        ),
        onChanged: (value) => unawaited(
          _publishBlocks(
            ref,
            childUid,
            blocks.copyWith(enforced: value),
          ),
        ),
      ),
    );
  }
}

/// One app on the child's device, with the parent's rule on it.
class _ChildAppRow extends ConsumerWidget {
  const _ChildAppRow({
    required this.childUid,
    required this.app,
    required this.block,
  });

  final String childUid;
  final CatalogApp app;
  final RemoteBlock? block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final blocked = block != null;
    final focusOnly = block?.focusOnly ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.md),
      child: Row(
        children: [
          AppIconAvatar(
            packageId: app.packageId,
            fallbackIcon: Icons.android_rounded,
            fallbackColor: blocked ? cs.tertiary : cs.primary,
            size: 40,
            radius: 12,
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.name,
                  style: tt.bodyLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  !blocked
                      ? 'Open'
                      : focusOnly
                      ? 'Closes while they focus'
                      : 'Closes when opened',
                  style: tt.labelSmall?.copyWith(
                    color: blocked ? cs.tertiary : cs.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: Gap.sm),
          // The second state a switch cannot show: blocked all day, or only
          // while a focus block runs. It appears only once a rule exists, so
          // the row never offers a choice that means nothing yet.
          if (blocked) ...[
            IconButton(
              tooltip: focusOnly
                  ? 'Block all day instead'
                  : 'Block only while they focus',
              icon: Icon(
                focusOnly
                    ? Icons.hourglass_bottom_rounded
                    : Icons.calendar_today_rounded,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
              onPressed: () => unawaited(_setFocusOnly(context, ref)),
            ),
          ],
          _ShieldSwitch(
            value: blocked,
            onChanged: (on) => unawaited(_setBlocked(context, ref, on)),
            semanticLabel: blocked
                ? 'Stop blocking ${app.name}'
                : 'Block ${app.name}',
          ),
        ],
      ),
    );
  }

  Future<void> _setBlocked(
    BuildContext context,
    WidgetRef ref,
    bool blocked,
  ) async {
    HapticFeedback.selectionClick();
    final current =
        ref.read(childBlocksProvider(childUid)).valueOrNull ??
        const RemoteBlocks();
    final next = blocked
        ? [
            ...current.apps,
            RemoteBlock(packageId: app.packageId, name: app.name),
          ]
        : [
            for (final a in current.apps)
              if (a.packageId != app.packageId) a,
          ];
    // Blocking turns enforcement on. A parent who switches an app closed
    // means it to close, and a rule that lands in a watching-only list is a
    // rule that does nothing on the phone it was written for.
    final updated = current.copyWith(
      apps: next,
      enforced: blocked ? true : current.enforced,
    );
    await _publishBlocks(ref, childUid, updated);
  }

  Future<void> _setFocusOnly(BuildContext context, WidgetRef ref) async {
    final current =
        ref.read(childBlocksProvider(childUid)).valueOrNull ??
        const RemoteBlocks();
    await _publishBlocks(
      ref,
      childUid,
      current.copyWith(
        apps: [
          for (final a in current.apps)
            if (a.packageId == app.packageId)
              RemoteBlock(
                packageId: a.packageId,
                name: a.name,
                focusOnly: !a.focusOnly,
              )
            else
              a,
        ],
      ),
    );
  }
}

/// Writes a block list for a child, with the failures said out loud.
Future<void> _publishBlocks(
  WidgetRef ref,
  String childUid,
  RemoteBlocks blocks,
) async {
  try {
    await ref.read(parentServiceProvider).publishBlocks(childUid, blocks);
  } on PairException catch (error) {
    final context = ref.context;
    if (context.mounted) showAppSnack(context, error.friendly);
  }
}

/// Their phone has not sent its app list — or the read was refused.
class _NoChildApps extends StatelessWidget {
  const _NoChildApps({required this.name, required this.failed});

  final String name;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xl),
      child: Card.filled(
        child: Padding(
          padding: const EdgeInsets.all(Gap.xl),
          child: Column(
            children: [
              Icon(
                failed ? Icons.cloud_off_rounded : Icons.apps_rounded,
                size: 48,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(height: Gap.md),
              Text(
                failed
                    ? 'Can\'t read their app list'
                    : 'No app list from $name\'s phone yet',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Gap.sm),
              Text(
                failed
                    ? 'The list could not be read just now. Nothing has '
                          'changed on their device.'
                    : 'Their phone publishes the apps it has while FocusForge '
                          'is open and linked. It arrives here as soon as it '
                          'does.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The child's YouTube, closed the same three ways this device's can be.
///
/// The surfaces are written into the child's block list rather than into this
/// device's rules: their engine reads the parent's YouTube rules ahead of
/// whatever is set locally, which is what makes this a control over their
/// phone and not over this one.
class _ChildYoutubeView extends ConsumerWidget {
  const _ChildYoutubeView({required this.childUid, required this.childName});

  final String childUid;
  final String childName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final read = ref.watch(childBlocksProvider(childUid));
    final blocks = read.valueOrNull ?? const RemoteBlocks();
    final rules = blocks.youtube;
    final wholeApp = blocks.apps
        .where((a) => a.packageId == AppCatalog.youtubePackage)
        .firstOrNull;

    if (read.hasError && read.valueOrNull == null) {
      return _NoChildApps(name: childName, failed: true);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stagger(
          index: 0,
          child: Card.filled(
            child: Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: Row(
                children: [
                  AppIconAvatar(
                    packageId: AppCatalog.youtubePackage,
                    fallbackIcon: Icons.smart_display_rounded,
                    fallbackColor: cs.error,
                    size: 48,
                    radius: 14,
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('YouTube'),
                        const SizedBox(height: 2),
                        Text(
                          rules.any
                              ? 'Partly closed — the rest still works'
                              : 'Everything still works',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: Gap.xl),
        Stagger(
          index: 1,
          child: SectionHeader(title: 'Surfaces', icon: Icons.tune_rounded),
        ),
        Stagger(
          index: 2,
          child: Card.filled(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _SurfaceSwitch(
                  icon: Icons.slow_motion_video_rounded,
                  title: 'Block Shorts',
                  body:
                      'The Shorts player closes on $childName\'s phone. '
                      'Ordinary videos keep playing, so a lecture link still '
                      'works.',
                  value: rules.shorts,
                  onChanged: (v) => unawaited(
                    _publishBlocks(
                      ref,
                      childUid,
                      blocks.copyWith(youtube: rules.copyWith(shorts: v)),
                    ),
                  ),
                ),
                Divider(color: cs.outlineVariant, height: 1),
                _SurfaceSwitch(
                  icon: Icons.dynamic_feed_rounded,
                  title: 'Block home & search',
                  body:
                      'Removes the recommendation feed and search results on '
                      'their phone. A video has to be opened from a direct '
                      'link.',
                  value: rules.feed,
                  onChanged: (v) => unawaited(
                    _publishBlocks(
                      ref,
                      childUid,
                      blocks.copyWith(youtube: rules.copyWith(feed: v)),
                    ),
                  ),
                ),
                if (rules.any) ...[
                  Divider(color: cs.outlineVariant, height: 1),
                  _SurfaceSwitch(
                    icon: Icons.center_focus_strong_rounded,
                    title: 'Only while focusing',
                    body:
                        'Arms both switches while a focus block runs on their '
                        'device. YouTube is free the rest of the day.',
                    value: rules.focusOnly,
                    onChanged: (v) => unawaited(
                      _publishBlocks(
                        ref,
                        childUid,
                        blocks.copyWith(youtube: rules.copyWith(focusOnly: v)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: Gap.xl),
        Stagger(
          index: 3,
          child: SectionHeader(
            title: 'Or the whole app',
            icon: Icons.block_rounded,
          ),
        ),
        Stagger(
          index: 4,
          child: Card.filled(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: Icon(
                wholeApp == null
                    ? Icons.lock_outline_rounded
                    : Icons.lock_open_rounded,
                color: cs.onSurfaceVariant,
              ),
              title: Text(
                wholeApp == null
                    ? 'Block all of YouTube'
                    : 'Stop blocking YouTube',
              ),
              subtitle: Text(
                wholeApp == null
                    ? 'Closes the app on their phone, Shorts and lectures '
                          'alike'
                    : 'Removes it from their blocked list',
              ),
              onTap: () {
                HapticFeedback.selectionClick();
                unawaited(
                  _publishBlocks(
                    ref,
                    childUid,
                    blocks.copyWith(
                      apps: wholeApp == null
                          ? [
                              ...blocks.apps,
                              const RemoteBlock(
                                packageId: AppCatalog.youtubePackage,
                                name: 'YouTube',
                              ),
                            ]
                          : [
                              for (final a in blocks.apps)
                                if (a.packageId != AppCatalog.youtubePackage) a,
                            ],
                      enforced: wholeApp == null ? true : blocks.enforced,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: Gap.lg),
        Stagger(
          index: 5,
          child: Card.outlined(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.item),
              side: BorderSide(color: cs.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(
                      'Shorts are recognised by the names YouTube gives its '
                      'own screens on $childName\'s phone, and the block '
                      'applies the next time their device is online.',
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A section heading inside the app list.
class _ListHeading extends StatelessWidget {
  const _ListHeading({required this.title, required this.icon, this.note});

  final String title;
  final IconData icon;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Both sides flex. The heading and its note are the two longest strings in
    // the list, and a Row of two unbounded texts overflows the moment the
    // reader has large type on — which is exactly when an overflow stripe is
    // least welcome.
    return Row(
      children: [
        Icon(icon, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (note != null) ...[
          const SizedBox(width: Gap.sm),
          Flexible(
            child: Text(
              note!,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: cs.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ],
    );
  }
}

/// A blocking rule that cannot fire until the OS grants something.
class _PermissionGate extends ConsumerWidget {
  const _PermissionGate({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.permission,
  });

  final IconData icon;
  final String title;
  final String body;
  final String action;
  final AppPermission permission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xl),
      child: Card(
        color: cs.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 20, color: cs.onErrorContainer),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(color: cs.onErrorContainer),
                        ),
                        const SizedBox(height: Gap.xs),
                        Text(
                          body,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: cs.onErrorContainer.withValues(
                                  alpha: 0.86,
                                ),
                                height: 1.4,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.md),
              FilledButton(
                onPressed: () async {
                  await const PermissionManager().request(permission);
                  // The answer arrives on resume, not here — the grant happens
                  // in a settings page this app is not running behind.
                  ref.invalidate(shieldEnabledProvider);
                  ref.invalidate(usageAccessProvider);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: cs.onErrorContainer,
                  foregroundColor: cs.errorContainer,
                  minimumSize: const Size.fromHeight(44),
                ),
                child: Text(action),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasText = controller.text.isNotEmpty;

    return TextField(
      controller: controller,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 15),
      cursorColor: cs.primary,
      textInputAction: TextInputAction.search,
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: cs.surfaceContainerHigh,
        hintText: 'Search every app…',
        hintStyle: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: cs.onSurfaceVariant),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 18,
          color: cs.onSurfaceVariant,
        ),
        suffixIcon: !hasText
            ? null
            : SheetCloseButton(
                label: 'Clear search',
                onTap: () {
                  controller.clear();
                  onChanged();
                },
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.pill),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.pill),
          borderSide: BorderSide(color: cs.primary),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Gap.lg,
          vertical: Gap.md,
        ),
      ),
    );
  }
}

/// Shown before the first app is added.
/// No apps to show at all — the device list came back empty.
///
/// Distinct from "nothing is armed yet": with the whole device on screen, an
/// empty list is never the user's doing. It means the platform would not
/// answer, and saying so is more useful than an invitation to add something.
class _NoApps extends StatelessWidget {
  const _NoApps();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xl),
        child: Column(
          children: [
            IconBadge(
              icon: Icons.phonelink_erase_rounded,
              color: cs.onSurfaceVariant,
              size: 56,
              radius: 18,
            ),
            const SizedBox(height: Gap.lg),
            Text(
              'No apps to list',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: Gap.sm),
            Text(
              'Android did not hand over the installed app list. That is a '
              'platform problem rather than a settings one — nothing here can '
              'be switched on until it answers.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xl),
      child: Card.filled(
        child: Padding(
          padding: const EdgeInsets.all(Gap.xl),
          child: Column(
            children: [
              Icon(
                Icons.search_off_outlined,
                size: 48,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(height: Gap.md),
              Text(
                'No app matches “$query”',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One app, one switch.
///
/// The whole row opens the full rule; the switch is the one-tap answer to "is
/// this closed", which is the only question most people come here with.
class _AppRuleRow extends ConsumerWidget {
  const _AppRuleRow({required this.row, required this.onOpen});

  final ShieldAppRow row;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final tier = row.rule?.tier;
    final accent = harmonize(tier?.color ?? cs.primary, cs.primary);

    return Semantics(
      button: true,
      label: _semanticLabel,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.md),
          child: Row(
            children: [
              AppIconAvatar(
                packageId: row.packageId,
                fallbackIcon: Icons.android_rounded,
                fallbackColor: accent,
                size: 40,
                radius: 12,
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            row.name,
                            style: tt.bodyLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (row.isSystem) ...[
                          const SizedBox(width: Gap.sm),
                          _Tag(label: 'System'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _meta,
                      style: tt.labelSmall?.copyWith(
                        color: row.isRestricted ? accent : cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Gap.sm),
              _ShieldSwitch(
                value: row.isRestricted,
                // Always live: an app the engine refuses to cover is filtered
                // out upstream and never gets a row to begin with. The rule
                // change itself may still be behind a parent's code.
                onChanged: (on) => _setRestricted(context, ref, on),
                semanticLabel: row.isRestricted
                    ? 'Close ${row.name}'
                    : 'Stop closing ${row.name}',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setRestricted(
    BuildContext context,
    WidgetRef ref,
    bool restricted,
  ) async {
    HapticFeedback.selectionClick();
    await runWithParentUnlock(context, ref, () async {
      final notifier = ref.read(whitelistProvider.notifier);

      if (!restricted) {
        final existing = ref
            .read(whitelistProvider)
            .where((e) => e.packageId == row.packageId)
            .firstOrNull;
        if (existing != null) await notifier.remove(existing.id);
        return;
      }

      await notifier.addInstalledApp(
        packageId: row.packageId,
        name: row.name,
        tier: WhitelistTier.blocked,
      );
    });
  }

  String get _meta {
    return switch (row.rule?.tier) {
      WhitelistTier.blocked => 'Closes when opened',
      WhitelistTier.focusOnly => 'Closes while you focus',
      WhitelistTier.budgeted =>
        '${formatMinutes(row.usedMinutes)} of '
            '${formatMinutes(row.rule?.budgetMinutes ?? 0)} used today',
      WhitelistTier.alwaysAllowed => 'Never closed',
      null when row.usedMinutes > 0 =>
        '${formatMinutes(row.usedMinutes)} today',
      null => row.isSystem ? 'System app' : 'Open — not restricted',
    };
  }

  String get _semanticLabel {
    return switch (row.rule?.tier) {
      WhitelistTier.blocked => '${row.name}, closes when opened',
      WhitelistTier.focusOnly => '${row.name}, closes while focusing',
      WhitelistTier.budgeted =>
        '${row.name}, ${formatMinutes(row.rule?.budgetMinutes ?? 0)} a day, '
            '${formatMinutes(row.usedMinutes)} used today',
      WhitelistTier.alwaysAllowed => '${row.name}, never closed',
      null => '${row.name}, not restricted',
    };
  }
}

/// A small factual tag — "System", and nothing that is not a fact.
class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: cs.onSurfaceVariant,
          fontSize: 10,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// The rule switch.
///
/// Not a Material switch: this is the one control on the screen that changes
/// what the phone does, so it is drawn as a shield that closes. The knob
/// travels on a spring and overshoots slightly, which is what makes flipping it
/// feel like a physical control rather than like a value being assigned — and
/// the glyph inside the knob means the state is legible without reading the
/// track colour, which matters for the two states that are one hue apart.
class _ShieldSwitch extends StatefulWidget {
  const _ShieldSwitch({
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String semanticLabel;

  @override
  State<_ShieldSwitch> createState() => _ShieldSwitchState();
}

class _ShieldSwitchState extends State<_ShieldSwitch>
    with SingleTickerProviderStateMixin {
  static const _width = 56.0;
  static const _height = 32.0;
  static const _knob = 24.0;
  static const _inset = 4.0;

  late final AnimationController _c = AnimationController(
    vsync: this,
    value: widget.value ? 1 : 0,
  );

  @override
  void didUpdateWidget(_ShieldSwitch old) {
    super.didUpdateWidget(old);
    if (old.value == widget.value) return;
    _c.animateWith(
      SpringSimulation(Motion.settle, _c.value, widget.value ? 1 : 0, 0),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = widget.onChanged != null;

    return Semantics(
      label: widget.semanticLabel,
      toggled: widget.value,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => widget.onChanged!(!widget.value) : null,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final fill = _c.value.clamp(0.0, 1.0);
            // The travel is allowed a hair past each end so the overshoot is
            // visible; the colour is not, or the track would flash.
            final travel = _c.value.clamp(-0.05, 1.05);

            final track = Color.lerp(
              cs.surfaceContainerHighest,
              enabled ? cs.primary : cs.surfaceContainerHighest,
              fill,
            );
            final knob = Color.lerp(cs.onSurfaceVariant, cs.onPrimary, fill);

            return Opacity(
              opacity: enabled ? 1 : 0.55,
              child: Container(
                width: _width,
                height: _height,
                padding: const EdgeInsets.all(_inset),
                decoration: BoxDecoration(
                  color: track,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Align(
                  alignment: Alignment(-1 + 2 * travel, 0),
                  child: Container(
                    width: _knob,
                    height: _knob,
                    decoration: BoxDecoration(
                      color: knob,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.value
                          ? Icons.shield_rounded
                          : Icons.shield_outlined,
                      size: 14,
                      color: track,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Per-app rule editor, for any app on the device.
///
/// Opened from a row that may have no rule at all yet, so it works from the
/// package rather than from an entry: the entry is created when the user saves,
/// which is what keeps the list free of a separate "add" step.
///
/// A sheet rather than controls on the row because the tiers are mutually
/// exclusive and the budget only means something in one of them — showing them
/// together is the only way the choice reads as one decision.
class AppRuleSheet extends ConsumerStatefulWidget {
  const AppRuleSheet({
    super.key,
    required this.packageId,
    required this.name,
    required this.icon,
    required this.usedMinutes,
  });

  final String packageId;
  final String name;
  final IconData icon;
  final int usedMinutes;

  @override
  ConsumerState<AppRuleSheet> createState() => _AppRuleSheetState();
}

class _AppRuleSheetState extends ConsumerState<AppRuleSheet> {
  late WhitelistTier _tier;
  late int _budget;
  bool _hadRule = false;

  static const _step = 5;
  static const _min = 5;
  static const _max = 8 * 60;

  @override
  void initState() {
    super.initState();
    final existing = _existing;
    _hadRule = existing != null;
    _tier = existing?.tier ?? WhitelistTier.blocked;
    _budget = existing?.budgetMinutes ?? WhitelistNotifier.defaultBudgetMinutes;
  }

  WhitelistEntry? get _existing => ref
      .read(whitelistProvider)
      .where((e) => e.packageId == widget.packageId)
      .firstOrNull;

  Future<void> _apply() async {
    if (!await confirmParentUnlock(context, ref)) return;
    if (!mounted) return;
    final notifier = ref.read(whitelistProvider.notifier);
    await notifier.addInstalledApp(
      packageId: widget.packageId,
      name: widget.name,
      tier: _tier,
      budgetMinutes: _budget,
    );
    // `addInstalledApp` moves an app that is already listed by changing its
    // tier, and a tier change deliberately drops the budget — so a budgeted
    // save has to set the allowance back. Doing it here rather than in the
    // notifier keeps "moving to another tier clears the budget" true.
    if (_tier == WhitelistTier.budgeted) {
      await notifier.setBudget('pkg:${widget.packageId}', _budget);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    if (!await confirmParentUnlock(context, ref)) return;
    if (!mounted) return;
    final existing = _existing;
    if (existing != null) {
      await ref.read(whitelistProvider.notifier).remove(existing.id);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = harmonize(_tier.color, cs.primary);
    final used = widget.usedMinutes;

    return SheetSurface(
      padding: const EdgeInsets.all(Gap.xl),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              const SizedBox(height: Gap.lg),
              Row(
                children: [
                  AppIconAvatar(
                    packageId: widget.packageId,
                    fallbackIcon: widget.icon,
                    fallbackColor: accent,
                    size: 48,
                    radius: 14,
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.packageId,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  SheetCloseButton(
                    label: 'Close',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: Gap.lg),
              for (final tier in WhitelistTier.values) ...[
                _TierOption(
                  tier: tier,
                  selected: _tier == tier,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _tier = tier);
                  },
                ),
                const SizedBox(height: Gap.sm),
              ],
              if (_tier == WhitelistTier.budgeted) ...[
                const SizedBox(height: Gap.md),
                Card.filled(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Gap.md,
                      Gap.sm,
                      Gap.md,
                      Gap.md,
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Daily allowance',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            _StepButton(
                              icon: Icons.remove_rounded,
                              label: 'Less time',
                              enabled: _budget > _min,
                              onTap: () => setState(
                                () => _budget = (_budget - _step).clamp(
                                  _min,
                                  _max,
                                ),
                              ),
                            ),
                            Semantics(
                              label: 'Daily allowance',
                              value: formatMinutes(_budget),
                              child: SizedBox(
                                width: 68,
                                child: Text(
                                  formatMinutes(_budget),
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                            ),
                            _StepButton(
                              icon: Icons.add_rounded,
                              label: 'More time',
                              enabled: _budget < _max,
                              onTap: () => setState(
                                () => _budget = (_budget + _step).clamp(
                                  _min,
                                  _max,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (used > 0) ...[
                          const SizedBox(height: Gap.sm),
                          Semantics(
                            label: 'Used today',
                            value: formatMinutes(used),
                            child: LinearProgressIndicator(
                              value: _budget == 0
                                  ? 0
                                  : (used / _budget).clamp(0.0, 1.0),
                              color: used >= _budget
                                  ? cs.error
                                  : harmonize(
                                      WhitelistTier.budgeted.color,
                                      cs.primary,
                                    ),
                              backgroundColor: cs.surfaceContainerHighest,
                              minHeight: 5,
                            ),
                          ),
                          const SizedBox(height: Gap.xs),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${formatMinutes(used)} used today',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: Gap.xl),
              Row(
                children: [
                  // Only offered when there is something to remove: on an app
                  // with no rule the button would be a no-op dressed as an
                  // action.
                  if (_hadRule) ...[
                    Expanded(
                      child: TextButton.icon(
                        onPressed: _remove,
                        style: TextButton.styleFrom(
                          foregroundColor: cs.error,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                        label: const Text('Remove'),
                      ),
                    ),
                    const SizedBox(width: Gap.md),
                  ],
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _apply,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text('Save rule'),
                    ),
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

class _TierOption extends StatelessWidget {
  const _TierOption({
    required this.tier,
    required this.selected,
    required this.onTap,
  });

  final WhitelistTier tier;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = harmonize(tier.color, cs.primary);
    final (icon, body) = switch (tier) {
      WhitelistTier.blocked => (
        Icons.block_rounded,
        'Closes as soon as it opens.',
      ),
      WhitelistTier.focusOnly => (
        Icons.center_focus_strong_rounded,
        'Closed while a focus block runs, and open the rest of the day.',
      ),
      WhitelistTier.budgeted => (
        Icons.hourglass_bottom_rounded,
        'Open until the day\'s allowance is spent, then it closes.',
      ),
      WhitelistTier.alwaysAllowed => (
        Icons.check_circle_outline_rounded,
        'Never closed. Useful for the apps your work runs through.',
      ),
    };

    return Semantics(
      button: true,
      selected: selected,
      label: '${tier.label}. $body',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Pressable(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(Gap.md),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.12)
                  : cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(Radii.item),
              border: Border.all(
                color: selected ? accent : cs.outlineVariant,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? accent : cs.onSurfaceVariant,
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tier.label,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        body,
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_rounded, size: 20, color: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      onTap: enabled ? onTap : null,
      child: ExcludeSemantics(
        child: Pressable(
          scale: 0.86,
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: Icon(
                icon,
                size: 18,
                color: enabled ? cs.onSurface : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// YouTube
// ---------------------------------------------------------------------------

class _YoutubeView extends ConsumerWidget {
  const _YoutubeView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final rules = ref.watch(youtubeRulesProvider);
    final installed = ref.watch(installedAppsProvider).valueOrNull;
    final youtubeInstalled =
        installed == null ||
        installed.any((a) => a.packageId == AppCatalog.youtubePackage);
    final fullyBlocked = ref
        .watch(whitelistProvider)
        .any(
          (e) =>
              e.packageId == AppCatalog.youtubePackage &&
              e.tier == WhitelistTier.blocked,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stagger(
          index: 0,
          child: Card.filled(
            child: Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: Row(
                children: [
                  AppIconAvatar(
                    packageId: AppCatalog.youtubePackage,
                    fallbackIcon: Icons.smart_display_rounded,
                    fallbackColor: cs.error,
                    size: 48,
                    radius: 14,
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'YouTube',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          rules.any
                              ? 'Partly closed — the rest still works'
                              : 'Everything still works',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: Gap.xl),
        Stagger(
          index: 1,
          child: SectionHeader(title: 'Surfaces', icon: Icons.tune_rounded),
        ),
        Stagger(
          index: 2,
          child: Card.filled(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _SurfaceSwitch(
                  icon: Icons.slow_motion_video_rounded,
                  title: 'Block Shorts',
                  body:
                      'The Shorts player closes. Ordinary videos keep playing, '
                      'so a lecture link still works.',
                  value: rules.shorts,
                  onChanged: (v) => unawaited(
                    runWithParentUnlock(
                      context,
                      ref,
                      () => ref
                          .read(youtubeRulesProvider.notifier)
                          .setShorts(v),
                    ),
                  ),
                ),
                Divider(color: cs.outlineVariant, height: 1),
                _SurfaceSwitch(
                  icon: Icons.dynamic_feed_rounded,
                  title: 'Block home & search',
                  body:
                      'Removes the recommendation feed and search results. A '
                      'video has to be opened from a direct link.',
                  value: rules.feed,
                  onChanged: (v) => unawaited(
                    runWithParentUnlock(
                      context,
                      ref,
                      () => ref.read(youtubeRulesProvider.notifier).setFeed(v),
                    ),
                  ),
                ),
                // Only meaningful once something is being closed, and a
                // switch that arms nothing is the inert control this screen
                // does not have.
                if (rules.any) ...[
                  Divider(color: cs.outlineVariant, height: 1),
                  _SurfaceSwitch(
                    icon: Icons.center_focus_strong_rounded,
                    title: 'Only while focusing',
                    body:
                        'Arms both switches while a focus block runs. '
                        'YouTube is free the rest of the day.',
                    value: rules.focusOnly,
                    onChanged: (v) => unawaited(
                      runWithParentUnlock(
                        context,
                        ref,
                        () => ref
                            .read(youtubeRulesProvider.notifier)
                            .setFocusOnly(v),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: Gap.lg),
        Stagger(
          index: 3,
          child: Card.outlined(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.item),
              side: BorderSide(color: cs.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.science_outlined,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(
                      'Shorts are recognised by the names YouTube gives its '
                      'own screens, not by reading what is on them. A future '
                      'YouTube update can rename them, and the block would '
                      'stop firing until FocusForge is updated to match.',
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (youtubeInstalled) ...[
          const SizedBox(height: Gap.xl),
          Stagger(
            index: 4,
            child: SectionHeader(
              title: 'Or the whole app',
              icon: Icons.block_rounded,
            ),
          ),
          Stagger(
            index: 5,
            child: Card.filled(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: Icon(
                  fullyBlocked
                      ? Icons.lock_open_rounded
                      : Icons.lock_outline_rounded,
                  color: cs.onSurfaceVariant,
                ),
                title: Text(
                  fullyBlocked
                      ? 'Stop blocking YouTube'
                      : 'Block all of YouTube',
                ),
                subtitle: Text(
                  fullyBlocked
                      ? 'Removes it from the blocked list'
                      : 'Closes the app entirely, Shorts and lectures alike',
                ),
                onTap: () {
                  HapticFeedback.selectionClick();
                  unawaited(
                    runWithParentUnlock(context, ref, () async {
                      final notifier = ref.read(whitelistProvider.notifier);
                      if (fullyBlocked) {
                        await notifier.remove(
                          'pkg:${AppCatalog.youtubePackage}',
                        );
                      } else {
                        await notifier.addInstalledApp(
                          packageId: AppCatalog.youtubePackage,
                          name: 'YouTube',
                          tier: WhitelistTier.blocked,
                        );
                      }
                    }),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SurfaceSwitch extends StatelessWidget {
  const _SurfaceSwitch({
    required this.icon,
    required this.title,
    required this.body,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SwitchListTile.adaptive(
      value: value,
      onChanged: (v) {
        HapticFeedback.selectionClick();
        onChanged(v);
      },
      secondary: Icon(icon, color: value ? cs.tertiary : cs.onSurfaceVariant),
      title: Text(title, style: Theme.of(context).textTheme.titleSmall),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          body,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Activity
// ---------------------------------------------------------------------------

class _ActivityView extends ConsumerWidget {
  const _ActivityView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final events = ref.watch(breathEventsProvider);
    final usage = ref.watch(appUsageTodayProvider).valueOrNull;
    final usageAccess = ref.watch(usageAccessProvider).valueOrNull ?? false;
    final rules = ref.watch(enrichedWhitelistProvider);

    final walkedAway = events.where((e) => e.walkedAway).length;
    final openedAnyway = events.length - walkedAway;
    final recent = events.reversed.take(12).toList(growable: false);

    // Only the apps the user has a rule for: a usage list of everything on the
    // phone is a screen the user cannot act on.
    final measured = [
      for (final entry in rules)
        if (entry.packageId != null && (usage?[entry.packageId] ?? 0) > 0)
          entry,
    ]..sort((a, b) => b.usedMinutes.compareTo(a.usedMinutes));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stagger(
          index: 0,
          child: Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'Walked away',
                  value: '$walkedAway',
                  icon: Icons.air_rounded,
                  color: cs.tertiary,
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: _StatTile(
                  label: 'Went in anyway',
                  value: '$openedAnyway',
                  icon: Icons.login_rounded,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.xl),
        Stagger(
          index: 1,
          child: SectionHeader(
            title: 'Recent blocks',
            icon: Icons.history_rounded,
          ),
        ),
        Stagger(
          index: 2,
          child: events.isEmpty
              ? const _EmptyLog()
              : Card.filled(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < recent.length; i++) ...[
                        if (i > 0) Divider(color: cs.outlineVariant, height: 1),
                        _EventRow(event: recent[i]),
                      ],
                    ],
                  ),
                ),
        ),
        const SizedBox(height: Gap.xl),
        Stagger(
          index: 3,
          child: SectionHeader(
            title: 'Today on your list',
            icon: Icons.schedule_rounded,
          ),
        ),
        Stagger(
          index: 4,
          child: !usageAccess
              ? const _UsageNotice(
                  icon: Icons.timelapse_rounded,
                  body:
                      'Usage access is off, so today\'s screen time cannot be '
                      'read. Grant it from the Apps tab to see real numbers '
                      'here.',
                )
              : measured.isEmpty
              ? const _UsageNotice(
                  icon: Icons.hourglass_empty_rounded,
                  body:
                      'Nothing on your list has been opened yet today. The '
                      'numbers appear here as soon as something is.',
                )
              : Card.filled(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.lg,
                      vertical: Gap.sm,
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < measured.length; i++) ...[
                          if (i > 0)
                            Divider(color: cs.outlineVariant, height: 1),
                          _UsageRow(
                            entry: measured[i],
                            maxMinutes: measured.first.usedMinutes,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Card.filled(
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(icon: icon, color: color, size: 34, radius: 10),
              const SizedBox(height: Gap.md),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final BreathEvent event;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final walked = event.walkedAway;
    final color = walked ? cs.tertiary : cs.onSurfaceVariant;

    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.lg,
          vertical: Gap.md,
        ),
        child: Row(
          children: [
            IconBadge(
              icon: walked ? Icons.air_rounded : Icons.login_rounded,
              color: color,
              size: 34,
              radius: 10,
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.appName.isEmpty ? 'An app' : event.appName,
                    style: Theme.of(context).textTheme.bodyLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    formatRelativeTime(event.at),
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Gap.sm),
            _OutcomePill(
              label: walked ? 'Walked away' : 'Opened anyway',
              color: color,
            ),
          ],
        ),
      ),
    );
  }
}

/// The outcome of one interception, as a pill.
///
/// The two states used to be plain coloured text, which reads as a sentence
/// rather than as a column of results — finding the rows that went the wrong
/// way meant reading every one of them. A tinted stadium makes the column
/// scannable: the shape says "this is a result" before the words do. The fill
/// is the state's own colour at low alpha rather than a fixed green or red, so
/// it survives a palette switch and a true-black surface without a second
/// guess.
class _OutcomePill extends StatelessWidget {
  const _OutcomePill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm + 2, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _UsageRow extends StatelessWidget {
  const _UsageRow({required this.entry, required this.maxMinutes});

  final WhitelistEntry entry;
  final int maxMinutes;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = harmonize(entry.tier.color, cs.primary);
    final share = maxMinutes == 0 ? 0.0 : entry.usedMinutes / maxMinutes;

    return Semantics(
      label: '${entry.name}, ${formatMinutes(entry.usedMinutes)} today',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.md),
          child: Row(
            children: [
              AppIconAvatar(
                packageId: entry.packageId,
                fallbackIcon: entry.icon,
                fallbackColor: accent,
                size: 34,
                radius: 10,
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.name,
                            style: Theme.of(context).textTheme.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: Gap.sm),
                        Text(
                          formatMinutes(entry.usedMinutes),
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: Gap.sm),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.pill),
                      child: LinearProgressIndicator(
                        value: share,
                        color: accent,
                        backgroundColor: cs.surfaceContainerHighest,
                        minHeight: 4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UsageNotice extends StatelessWidget {
  const _UsageNotice({required this.icon, required this.body});

  final IconData icon;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card.outlined(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.item),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(
                body,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLog extends StatelessWidget {
  const _EmptyLog();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xl),
        child: Column(
          children: [
            IconBadge(
              icon: Icons.history_rounded,
              color: cs.onSurfaceVariant,
              size: 48,
              radius: 16,
            ),
            const SizedBox(height: Gap.md),
            Text(
              'Nothing blocked yet',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: Gap.xs),
            Text(
              'Every time a rule fires it is logged here — and whether you '
              'went in anyway or walked away.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fades a tab's content in when the branch first builds.
///
/// The tab branches are kept alive by the shell, so a plain [Stagger] would
/// have finished animating long before the user ever reaches the tab. This
/// holds the entrance until the widget is actually laid out on screen.
class _TabEntrance extends StatefulWidget {
  const _TabEntrance({required this.child});

  final Widget child;

  @override
  State<_TabEntrance> createState() => _TabEntranceState();
}

class _TabEntranceState extends State<_TabEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void initState() {
    super.initState();
    // One frame late: the branch is built while the shell is still laying the
    // nav bar out, and starting immediately would spend the animation behind
    // the first paint.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}
