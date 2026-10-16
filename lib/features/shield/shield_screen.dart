import '../../core/localization/app_strings.dart';
import '../../shared/widgets/glass_surface.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/shell/app_shell.dart';
import '../../app/theme/app_theme.dart';
import '../../core/models/shield.dart';
import '../../core/providers/shield_providers.dart';
import '../../core/providers/usage_providers.dart';
import '../../core/services/native_shield_service.dart';
import '../../core/services/permission_manager.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/app_icon_avatar.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/app_segmented_control.dart';
import '../../shared/widgets/icon_badge.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/widgets/stagger.dart';
import '../../shared/widgets/sheet_chrome.dart';
import 'breath_gate.dart';
import 'shield_access.dart';
import 'shield_overview.dart';

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
/// The header sits above the scrollable list and grows with the text size.
/// A tonal edge keeps the two apart. No blur here — the
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
    ref.invalidate(overlayAccessProvider);
    ref.invalidate(appBlockingRunningProvider);
    ref.invalidate(appBlockingPausedProvider);
    ref.invalidate(usageAccessProvider);
    ref.invalidate(appUsageTodayProvider);
    ref.invalidate(installedAppsProvider);
    ref.invalidate(protectedPackagesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final topInset = MediaQuery.paddingOf(context).top;

    final segments = _segmentOptions;
    final segment = _segment.clamp(0, segments.length - 1);
    final armed = ref.watch(activeShieldCountProvider);

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(
              bottom: BorderSide(
                color: cs.outlineVariant.withValues(alpha: .35),
              ),
            ),
          ),
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final title = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr("Shield"),
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(
                                  letterSpacing: -1,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: Gap.xs),
                          Text(
                            context.tr("Make distraction a little harder."),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      );
                      final status = _ShieldStatusPill(
                        armed: armed,
                        onTap: _showStatusSheet,
                      );
                      final stacked =
                          constraints.maxWidth < 330 ||
                          MediaQuery.textScalerOf(context).scale(14) > 20;
                      if (stacked) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            title,
                            const SizedBox(height: Gap.md),
                            status,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: title),
                          const SizedBox(width: Gap.sm),
                          status,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: Gap.lg),
                  AppSegmentedControl<int>(
                    options: {
                      for (var i = 0; i < segments.length; i++) i: segments[i],
                    },
                    selected: segment,
                    onChanged: (value) => setState(() => _segment = value),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Layout.readable),
              child: _TabEntrance(
                child: switch (segment) {
                  0 => const _AppsView(topPadding: Gap.lg),
                  1 => const _SegmentScroll(
                    topPadding: Gap.lg,
                    child: _YoutubeView(),
                  ),
                  _ => const _SegmentScroll(
                    topPadding: Gap.lg,
                    child: _ActivityView(),
                  ),
                },
              ),
            ),
          ),
        ),
      ],
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
  const _ShieldStatusPill({required this.armed, this.onTap});

  final int armed;

  /// Null when there is nothing to open, which is also what makes the pill a
  /// plain badge rather than a control.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final on = armed > 0;
    final color = on ? cs.tertiary : cs.onSurfaceVariant;
    final text = on
        ? context.tr("{0} rules", [armed])
        : context.tr("View status");

    return Semantics(
      button: onTap != null,
      container: true,
      label: context.tr("Shield status. {0}.{1}", [
        text,
        onTap == null ? '' : ' Double tap for details.',
      ]),
      onTap: onTap,
      child: ExcludeSemantics(
        child: Pressable(
          scale: 0.94,
          onTap: onTap,
          // Premium status pill: the armed state lifts with a quiet tertiary
          // glow, so protection reads as active rather than outlined.
          child: Container(
            decoration: ShapeDecoration(
              shape: StadiumBorder(
                side: BorderSide(
                  color: on ? cs.tertiary : cs.outlineVariant,
                  width: on ? 1.5 : 1,
                ),
              ),
              color: cs.surfaceContainerLow,
              shadows: on
                  ? [
                      BoxShadow(
                        color: cs.tertiary.withValues(alpha: 0.28),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.md,
                vertical: 16,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      text,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
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
    final usageAccess = ref.watch(usageAccessProvider).valueOrNull ?? false;
    final overlay = ref.watch(overlayAccessProvider).valueOrNull ?? false;
    final enabled =
        usageAccess &&
        overlay &&
        (ref.watch(appBlockingRunningProvider).valueOrNull ?? false);
    final native = NativeShieldService.isSupported;
    final blocked = ref.watch(blockedAppsProvider).length;
    final budgeted = ref.watch(budgetedAppsProvider).length;
    final youtube = ref.watch(youtubeRulesProvider);
    final youtubeAccess = ref.watch(shieldEnabledProvider).valueOrNull ?? false;
    final strict = ref.watch(strictModeProvider);
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
                          context.tr("What is being enforced"),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.tr("Live state of the shield engine"),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  SheetCloseButton(
                    label: context.tr("Close status"),
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
                  label: context.tr("App blocking"),
                  value: enabled ? 'On' : context.tr("Off"),
                ),
              _StatusLine(
                icon: Icons.block_rounded,
                color: blocked > 0 ? cs.tertiary : cs.onSurfaceVariant,
                label: context.tr("Apps blocked"),
                value: blocked > 0 && native && !enabled
                    ? context.tr("{0} inactive", [blocked])
                    : '$blocked',
              ),
              _StatusLine(
                icon: Icons.hourglass_bottom_rounded,
                color: budgeted > 0
                    ? harmonize(WhitelistTier.budgeted.color, cs.primary)
                    : cs.onSurfaceVariant,
                label: context.tr("Time budgets"),
                value: budgeted == 0
                    ? context.tr("None")
                    : !enabled
                    ? context.tr("{0} inactive", [budgeted])
                    : usageAccess
                    ? context.tr("{0} running", [budgeted])
                    : context.tr("{0}, not reading usage", [budgeted]),
              ),
              _StatusLine(
                icon: Icons.smart_display_rounded,
                color: youtube.any ? cs.tertiary : cs.onSurfaceVariant,
                label: context.tr("YouTube"),
                value: youtube.any && !youtubeAccess
                    ? context.tr("Accessibility access is off")
                    : switch ((youtube.shorts, youtube.feed)) {
                        (true, true) => context.tr("Shorts and feeds closed"),
                        (true, false) => context.tr("Shorts closed"),
                        (false, true) => context.tr("Feeds closed"),
                        _ => context.tr("Untouched"),
                      },
              ),
              _StatusLine(
                icon: Icons.lock_rounded,
                color: strict.enabled ? cs.tertiary : cs.onSurfaceVariant,
                label: context.tr("Strict mode"),
                value: strict.enabled
                    ? context.tr("{0} min session", [strict.durationMinutes])
                    : context.tr("Off"),
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
                                ? context.tr(
                                    "App blocking runs on Android. On this build the rules are saved and shown, and nothing is closed.",
                                  )
                                : !enabled
                                ? context.tr(
                                    "App boundaries are off. Check Usage access and Draw over other apps, then enable an app rule. Review app usage on Home.",
                                  )
                                : context.tr(
                                    "Time budgets need usage access before they can count anything. Review app usage on Home.",
                                  ),
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
              Material(
                color: Colors.transparent,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.air_outlined, color: cs.primary),
                  title: Text(context.tr("Preview the pause screen")),
                  subtitle: Text(
                    context.tr(
                      "The 4-7-8 breath exercise shown before a blocked app opens",
                    ),
                  ),
                  onTap: onPreviewGate,
                ),
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
  int _filter = 0;

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
    final enabled = ref.watch(appBlockingRunningProvider).valueOrNull ?? false;
    final usageAccess = ref.watch(usageAccessProvider).valueOrNull ?? false;
    final budgeted = ref.watch(budgetedAppsProvider).length;

    bool matchesRule(ShieldAppRow row) => switch (_filter) {
      1 => row.rule?.tier == WhitelistTier.blocked,
      2 => row.rule?.tier == WhitelistTier.focusOnly,
      3 => row.rule?.tier == WhitelistTier.budgeted,
      _ => true,
    };
    final visible = all
        .where(
          (row) =>
              matchesRule(row) &&
              (query.isEmpty ||
                  row.name.toLowerCase().contains(query) ||
                  row.packageId.toLowerCase().contains(query)),
        )
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
              const ShieldOverview(),
              const SizedBox(height: Gap.lg),
              if (native && enabled && budgeted > 0 && !usageAccess)
                _PermissionGate(
                  icon: Icons.timelapse_rounded,
                  title: context.tr("Time budgets are not counting"),
                  body: context.tr(
                    "A budget needs to read how long an app has been open. Use Allow app usage on Home before enabling this rule.",
                  ),
                  action: context.tr("Review app usage on Home"),
                  permission: AppPermission.usageAccess,
                ),
              _SearchField(
                controller: _search,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: Gap.md),
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.xs,
                children: [
                  for (final (index, label) in [
                    context.tr("All"),
                    context.tr("Blocked"),
                    context.tr("Focus only"),
                    context.tr("Budgets"),
                  ].indexed)
                    ChoiceChip(
                      label: Text(label),
                      selected: _filter == index,
                      onSelected: (_) => setState(() => _filter = index),
                    ),
                ],
              ),
              const SizedBox(height: Gap.xl),
              _ListHeading(
                title: query.isEmpty && _filter == 0
                    ? context.tr("All apps")
                    : context.tr("Results"),
                note: loading ? context.tr("Reading the device…") : null,
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
                  : Column(
                      children: [
                        _NoMatches(
                          query: query.isEmpty
                              ? context.tr("this filter")
                              : _search.text.trim(),
                        ),
                        TextButton.icon(
                          onPressed: () => setState(() {
                            _search.clear();
                            _filter = 0;
                          }),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(context.tr("Show all apps")),
                        ),
                      ],
                    ),
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
              context.tr(
                "Rules apply after Android access is allowed. You can change or remove a rule at any time.",
              ),
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
                  await requestShieldPermission(context, ref, permission);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: cs.onErrorContainer,
                  foregroundColor: cs.errorContainer,
                  minimumSize: const Size.fromHeight(48),
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
        hintText: context.tr("Search every app…"),
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
                label: context.tr("Clear search"),
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
    return ContentCard(
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
              context.tr("No apps to list"),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: Gap.sm),
            Text(
              context.tr(
                "Android did not hand over the installed app list. That is a platform problem rather than a settings one — nothing here can be switched on until it answers.",
              ),
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
      child: ContentCard(
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
                context.tr("No app matches “{0}”", [query]),
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
    final usage = ref.watch(usageAccessProvider).valueOrNull ?? false;
    final overlay = ref.watch(overlayAccessProvider).valueOrNull ?? false;
    final running = ref.watch(appBlockingRunningProvider).valueOrNull ?? false;
    final inactive =
        NativeShieldService.isSupported &&
        row.isRestricted &&
        (!usage || !overlay || !running);
    final needsUsage = inactive && overlay && !usage;
    final meta = needsUsage
        ? context.tr("Allow app usage")
        : inactive
        ? context.tr("Inactive · Rule saved")
        : _meta;

    return Semantics(
      button: true,
      label: inactive
          ? context.tr("{0}, saved rule, {1}", [row.name, meta])
          : _semanticLabel,
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
                          _Tag(label: context.tr("System")),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
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
                    ? context.tr("Stop closing {0}", [row.name])
                    : context.tr("Close {0}", [row.name]),
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
    if (restricted && !await ensureShieldAccess(context, ref)) return;
    if (!context.mounted) return;
    await _applyLocalChange(context, ref, () async {
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
      WhitelistTier.blocked => tr("Closes when opened"),
      WhitelistTier.focusOnly => tr("Closes while you focus"),
      WhitelistTier.budgeted => tr("{0} of {1} used today", [
        formatMinutes(row.usedMinutes),
        formatMinutes(row.rule?.budgetMinutes ?? 0),
      ]),
      WhitelistTier.alwaysAllowed => tr("Never closed"),
      null when row.usedMinutes > 0 => tr("{0} today", [
        formatMinutes(row.usedMinutes),
      ]),
      null => row.isSystem ? tr("System app") : tr("Open — not restricted"),
    };
  }

  String get _semanticLabel {
    return switch (row.rule?.tier) {
      WhitelistTier.blocked => tr("{0}, closes when opened", [row.name]),
      WhitelistTier.focusOnly => tr("{0}, closes while focusing", [row.name]),
      WhitelistTier.budgeted => tr("{0}, {1} a day, {2} used today", [
        row.name,
        formatMinutes(row.rule?.budgetMinutes ?? 0),
        formatMinutes(row.usedMinutes),
      ]),
      WhitelistTier.alwaysAllowed => tr("{0}, never closed", [row.name]),
      null => tr("{0}, not restricted", [row.name]),
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
    if (_tier.isEnforced && !await ensureShieldAccess(context, ref)) {
      return;
    }
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
                    label: context.tr("Close"),
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
                ContentCard(
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
                                context.tr("Daily allowance"),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            _StepButton(
                              icon: Icons.remove_rounded,
                              label: context.tr("Less time"),
                              enabled: _budget > _min,
                              onTap: () => setState(
                                () => _budget = (_budget - _step).clamp(
                                  _min,
                                  _max,
                                ),
                              ),
                            ),
                            Semantics(
                              label: context.tr("Daily allowance"),
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
                              label: context.tr("More time"),
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
                            label: context.tr("Used today"),
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
                              context.tr("{0} used today", [
                                formatMinutes(used),
                              ]),
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
                        label: Text(context.tr("Remove")),
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
                      child: Text(context.tr("Save rule")),
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
        context.tr("Closes as soon as it opens."),
      ),
      WhitelistTier.focusOnly => (
        Icons.center_focus_strong_rounded,
        context.tr(
          "Closed while a focus block runs, and open the rest of the day.",
        ),
      ),
      WhitelistTier.budgeted => (
        Icons.hourglass_bottom_rounded,
        context.tr("Open until the day's allowance is spent, then it closes."),
      ),
      WhitelistTier.alwaysAllowed => (
        Icons.check_circle_outline_rounded,
        context.tr("Never closed. Useful for the apps your work runs through."),
      ),
    };

    return Semantics(
      button: true,
      selected: selected,
      label: '${context.tr(tier.label)}. $body',
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
                        context.tr(tier.label),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stagger(
          index: 1,
          child: Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: Row(
              children: [
                Container(
                  width: 25,
                  height: 18,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF0000),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 17,
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Semantics(
                  header: true,
                  child: Text(
                    context.tr("YouTube"),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
        Stagger(
          index: 2,
          child: GlassCard(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _SurfaceSwitch(
                  icon: Icons.slow_motion_video_rounded,
                  title: context.tr("Block Shorts"),
                  body: context.tr(
                    "The Shorts player closes. Ordinary videos keep playing, so a lecture link still works.",
                  ),
                  value: rules.shorts,
                  onChanged: (v) => _changeSurface(
                    context,
                    ref,
                    v,
                    () => ref.read(youtubeRulesProvider.notifier).setShorts(v),
                    feature: context.tr("Shorts blocking"),
                  ),
                ),
                Divider(color: cs.outlineVariant, height: 1),
                _SurfaceSwitch(
                  icon: Icons.dynamic_feed_rounded,
                  title: context.tr("Block home & search"),
                  body: context.tr(
                    "Removes the recommendation feed and search results. A video has to be opened from a direct link.",
                  ),
                  value: rules.feed,
                  onChanged: (v) => _changeSurface(
                    context,
                    ref,
                    v,
                    () => ref.read(youtubeRulesProvider.notifier).setFeed(v),
                    feature: context.tr("YouTube filtering"),
                  ),
                ),
                // Only meaningful once something is being closed, and a
                // switch that arms nothing is the inert control this screen
                // does not have.
                if (rules.any) ...[
                  Divider(color: cs.outlineVariant, height: 1),
                  _SurfaceSwitch(
                    icon: Icons.center_focus_strong_rounded,
                    title: context.tr("Only while focusing"),
                    body: context.tr(
                      "Arms your YouTube filters while a focus block runs. YouTube is free the rest of the day.",
                    ),
                    value: rules.focusOnly,
                    onChanged: (v) => unawaited(
                      _applyLocalChange(
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
      ],
    );
  }
}

Future<void> _changeSurface(
  BuildContext context,
  WidgetRef ref,
  bool enabling,
  Future<void> Function() apply, {
  String? feature,
}) async {
  if (enabling &&
      !await ensureShieldAccess(
        context,
        ref,
        requiresAccessibility: true,
        feature: feature,
      )) {
    return;
  }
  if (!context.mounted) return;
  await _applyLocalChange(context, ref, apply);
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
                  label: context.tr("Walked away"),
                  value: '$walkedAway',
                  icon: Icons.air_rounded,
                  color: cs.tertiary,
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: _StatTile(
                  label: context.tr("Went in anyway"),
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
            title: context.tr("Recent blocks"),
            icon: Icons.history_rounded,
          ),
        ),
        Stagger(
          index: 2,
          child: events.isEmpty
              ? const _EmptyLog()
              : ContentCard(
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
            title: context.tr("Today on your list"),
            icon: Icons.schedule_rounded,
          ),
        ),
        Stagger(
          index: 4,
          child: !usageAccess
              ? _UsageNotice(
                  icon: Icons.timelapse_rounded,
                  body: context.tr(
                    "Usage access is off, so today's screen time cannot be read. Grant it from the Apps tab to see real numbers here.",
                  ),
                )
              : measured.isEmpty
              ? _UsageNotice(
                  icon: Icons.hourglass_empty_rounded,
                  body: context.tr(
                    "Nothing on your list has been opened yet today. The numbers appear here as soon as something is.",
                  ),
                )
              : ContentCard(
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
      child: ContentCard(
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
                    event.appName.isEmpty
                        ? context.tr("An app")
                        : event.appName,
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
              label: walked
                  ? context.tr("Walked away")
                  : context.tr("Opened anyway"),
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
      label: context.tr("{0}, {1} today", [
        entry.name,
        formatMinutes(entry.usedMinutes),
      ]),
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
    return ContentCard(
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
              context.tr("Nothing blocked yet"),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: Gap.xs),
            Text(
              context.tr(
                "Every time a rule fires it is logged here — and whether you went in anyway or walked away.",
              ),
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

Future<void> _applyLocalChange(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() apply,
) => apply();
