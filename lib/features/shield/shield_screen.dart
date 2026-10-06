import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/shell/app_shell.dart';
import '../../app/theme/color_tokens.dart';
import '../../app/theme/glass_theme.dart';
import '../../core/models/shield.dart';
import '../../core/providers/shield_providers.dart';
import '../../core/services/shield_service.dart';
import '../../shared/widgets/glass_page.dart';
import '../../shared/widgets/glass_surface.dart';
import '../../shared/widgets/glass_toggle.dart';
import '../../shared/widgets/segmented_control.dart';
import '../../shared/widgets/stagger.dart';

/// Tab 2 — the shielding engine: feed blocking, whitelist tiers and profiles.
///
/// The header genuinely floats: the list scrolls underneath it and blurs as it
/// passes, which is the whole point of a frosted sticky bar.
///
/// Everything below the header comes from `shield_providers`; the only local
/// state is which segment is showing. A toggle has to reach its notifier,
/// because that is what persists the change and pushes it to the platform
/// service — local `setState` would make the switch a lie.
class ShieldScreen extends ConsumerStatefulWidget {
  const ShieldScreen({super.key});

  @override
  ConsumerState<ShieldScreen> createState() => _ShieldScreenState();
}

class _ShieldScreenState extends ConsumerState<ShieldScreen> {
  int _segment = 0;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final topInset = MediaQuery.paddingOf(context).top;
    final headerHeight = 172 + topInset;
    final armed = ref.watch(activeShieldCountProvider);
    final total = ref.watch(allFeedRowsProvider).length;

    return Stack(
      children: [
        Positioned.fill(
          // The entrance waits for the branch to be on screen; see
          // [_TabEntrance].
          child: _TabEntrance(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                Gap.lg + 4,
                headerHeight + Gap.md,
                Gap.lg + 4,
                kNavBarClearance,
              ),
              children: [
                switch (_segment) {
                  0 => const _FeedBlockerView(),
                  1 => const _WhitelistView(),
                  _ => const _ProfilesView(),
                },
              ],
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  Gap.lg + 4,
                  topInset + Gap.lg,
                  Gap.lg + 4,
                  Gap.lg,
                ),
                // A dark scrim that dissolves into the content, rather than a
                // light translucent slab — on a dark canvas a white-tinted
                // header reads as a different theme entirely.
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      t.canvasGradient.first.withValues(alpha: 0.96),
                      t.canvasGradient[1].withValues(alpha: 0.90),
                      t.canvasGradient[1].withValues(alpha: 0),
                    ],
                    stops: const [0, 0.80, 1],
                  ),
                ),
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
                                'Feed Shielding Engine',
                                style: context.type.headlineMedium?.copyWith(
                                  fontSize: 24,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Surgically remove addictive feeds',
                                style: context.type.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: Gap.md),
                        _ShieldStatusPill(
                          armed: armed,
                          total: total,
                          onTap: _showStatusSheet,
                        ),
                      ],
                    ),
                    const SizedBox(height: Gap.lg),
                    SegmentedControl(
                      options: const ['Feed Blocker', 'Whitelist', 'Profiles'],
                      index: _segment,
                      onChanged: (i) => setState(() => _segment = i),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Explains what the green dot actually means, and — just as important —
  /// what it does not. The badge is the only place a user can find out that
  /// nothing is being blocked yet, so the sheet says it in plain language.
  void _showStatusSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _ShieldStatusSheet(
        onTryGate: () {
          final blocked = ref
              .read(whitelistProvider)
              .where((e) => e.tier == WhitelistTier.blocked)
              .firstOrNull;
          final app = blocked?.name ?? 'Instagram';
          // The native interceptor does not exist yet, so the demo path fakes
          // the interception the real engine will one day emit.
          final service = ref.read(shieldServiceProvider);
          if (service is RecordingShieldService) service.simulate(app);
          Navigator.of(sheetContext).pop();
          context.push(AppRoutes.paths[AppRoutes.breathGate]!, extra: app);
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
    required this.total,
    required this.onTap,
  });

  final int armed;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final on = armed > 0;
    final color = on ? t.success : t.textTertiary;
    final label = on ? '$armed active' : 'None armed';

    return Semantics(
      button: true,
      container: true,
      label:
          'Shield status. $armed of $total feed shields armed. '
          'Double tap for details.',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Pressable(
          scale: 0.94,
          onTap: onTap,
          child: GlassPanel(
            radius: Radii.pill,
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.md,
              vertical: 16,
            ),
            accent: on ? color : null,
            glowStrength: on ? 0.5 : 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: on ? 0.8 : 0.3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: context.type.labelSmall?.copyWith(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What is armed, which profile is in charge, and the honest footnote about
/// the missing native engine.
class _ShieldStatusSheet extends ConsumerWidget {
  const _ShieldStatusSheet({required this.onTryGate});

  final VoidCallback onTryGate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.glass;
    final armed = ref.watch(activeShieldCountProvider);
    final total = ref.watch(allFeedRowsProvider).length;
    final profile = ref.watch(activeProfileProvider);
    final strict = ref.watch(strictModeProvider);
    final allowed = ref
        .watch(whitelistProvider)
        .where((e) => e.tier == WhitelistTier.alwaysAllowed)
        .length;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: GlassPanel(
          radius: Radii.hero,
          blur: t.blurL2,
          padding: const EdgeInsets.all(Gap.xl),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: t.textTertiary,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                  ),
                ),
                const SizedBox(height: Gap.lg),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'What is being enforced',
                            style: context.type.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Live state of the shield engine',
                            style: context.type.bodySmall?.copyWith(
                              color: t.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _SheetCloseButton(
                      label: 'Close status',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.lg),
                _StatusLine(
                  icon: Icons.shield_rounded,
                  color: armed > 0 ? t.success : t.textTertiary,
                  label: 'Feed shields',
                  value: '$armed of $total armed',
                ),
                _StatusLine(
                  icon: Icons.tune_rounded,
                  color: t.accentPrimary,
                  label: 'Active profile',
                  value: profile?.name ?? 'None',
                ),
                _StatusLine(
                  icon: Icons.lock_rounded,
                  color: strict.enabled ? t.gold : t.textTertiary,
                  label: 'Strict mode',
                  value: strict.enabled
                      ? '${strict.durationMinutes} min session'
                      : 'Off',
                ),
                _StatusLine(
                  icon: Icons.verified_user_rounded,
                  color: t.accentSecondary,
                  label: 'Always allowed',
                  value: '$allowed apps',
                ),
                const SizedBox(height: Gap.md),
                GlassPanel(
                  level: 2,
                  radius: Radii.item,
                  padding: const EdgeInsets.all(Gap.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.construction_rounded,
                        size: 16,
                        color: t.textTertiary,
                      ),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: Text(
                          'The native interceptor is not wired up on this '
                          'build, so nothing is actually blocked yet. Every '
                          'switch here persists and is pushed to the shield '
                          'service, ready for the engine to pick up.',
                          style: context.type.labelSmall?.copyWith(height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Gap.md),
                Divider(color: t.hairline, height: 1),
                GlassRow(
                  title: 'Try the breath gate',
                  subtitle: 'Preview the pause before a blocked app opens',
                  icon: Icons.air_rounded,
                  iconColor: t.accentPrimary,
                  onTap: onTryGate,
                  showDivider: false,
                ),
              ],
            ),
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
    final t = context.glass;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.sm),
        child: Row(
          children: [
            GlassIconBadge(
              icon: icon,
              color: color,
              size: 34,
              radius: 10,
              glow: 0.3,
            ),
            const SizedBox(width: Gap.md),
            Expanded(child: Text(label, style: context.type.bodyLarge)),
            const SizedBox(width: Gap.sm),
            Text(
              value,
              style: context.type.labelMedium?.copyWith(color: t.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// 48dp close affordance shared by both sheets.
class _SheetCloseButton extends StatelessWidget {
  const _SheetCloseButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Pressable(
          scale: 0.85,
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Icon(
                Icons.close_rounded,
                size: 20,
                color: t.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Feed Blocker
// ---------------------------------------------------------------------------

class _FeedBlockerView extends ConsumerWidget {
  const _FeedBlockerView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.glass;
    final groups = ref.watch(feedGroupsProvider);

    // Stagger plays once per element lifetime. This branch is built the first
    // time the tab is shown (go_router does not preload branches), so the
    // entrance lands on the first visit and never on a provider rebuild.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var g = 0; g < groups.length; g++) ...[
          if (g > 0) const SizedBox(height: Gap.xl),
          // Two steps per group so the header leads its panel down the page.
          Stagger(
            index: g * 2,
            child: SectionHeader(
              title: groups[g].title,
              icon: groups[g].icon,
              trailing: Text(
                '${groups[g].rows.where((r) => r.enabled).length} / '
                '${groups[g].rows.length}',
                style: context.type.labelSmall,
              ),
            ),
          ),
          Stagger(
            index: g * 2 + 1,
            child: GlassPanel(
              radius: Radii.card,
              padding: const EdgeInsets.all(Gap.lg),
              child: Column(
                children: [
                  for (var r = 0; r < groups[g].rows.length; r++) ...[
                    if (r > 0) Divider(color: t.hairline, height: Gap.xl),
                    _FeedRowTile(row: groups[g].rows[r]),
                  ],
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: Gap.xl),
        Stagger(
          index: groups.length * 2,
          child: GlassPanel(
            radius: Radii.item,
            padding: const EdgeInsets.all(Gap.md),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: t.textTertiary,
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    'Toggles persist and sync to the shield service. The native '
                    'interceptor is not wired up on this build.',
                    style: context.type.labelSmall?.copyWith(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FeedRowTile extends ConsumerWidget {
  const _FeedRowTile({required this.row});

  final FeedRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.glass;
    final enabled = row.enabled;

    void toggle() {
      HapticFeedback.lightImpact();
      ref.read(feedGroupsProvider.notifier).toggle(row.id, !enabled);
    }

    void setMode(int i) {
      HapticFeedback.selectionClick();
      ref.read(feedGroupsProvider.notifier).setMode(row.id, row.modes![i]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // One semantic node for the whole row: "Block Reels Feed in
        // Instagram, switch, on". Without the exclusion a screen reader would
        // land on an unlabelled button wrapping an unlabelled switch.
        Semantics(
          container: true,
          toggled: enabled,
          label: '${row.title} in ${row.appName}',
          onTap: toggle,
          child: ExcludeSemantics(
            child: Pressable(
              onTap: toggle,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GlassIconBadge(
                    icon: row.icon,
                    color: row.color,
                    glow: enabled ? 0.55 : 0,
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
                                row.title,
                                style: context.type.titleSmall,
                              ),
                            ),
                            if (enabled) ...[
                              const SizedBox(width: 6),
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: t.success,
                                  boxShadow: [
                                    BoxShadow(
                                      color: t.success.withValues(alpha: 0.75),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          row.description,
                          style: context.type.bodySmall?.copyWith(
                            color: t.textTertiary,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Gap.md),
                  GlassToggle(
                    value: enabled,
                    onChanged: (v) =>
                        ref.read(feedGroupsProvider.notifier).toggle(row.id, v),
                    accent: row.color,
                    semanticLabel: '${row.title} in ${row.appName}',
                  ),
                ],
              ),
            ),
          ),
        ),
        if (row.modes != null && enabled) ...[
          const SizedBox(height: Gap.md),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              for (var i = 0; i < row.modes!.length; i++)
                Semantics(
                  button: true,
                  selected: i == row.modeIndex,
                  label: '${row.appName}: ${row.modes![i].label}',
                  onTap: () => setMode(i),
                  child: ExcludeSemantics(
                    child: GlassPill(
                      selected: i == row.modeIndex,
                      accent: row.color,
                      onTap: () => setMode(i),
                      // 16 + a 16px line box = a 48dp chip, the Material
                      // minimum for a control this easy to mis-tap.
                      padding: const EdgeInsets.symmetric(
                        horizontal: Gap.md,
                        vertical: Gap.lg,
                      ),
                      child: Text(
                        row.modes![i].label,
                        style: const TextStyle(fontSize: 12, height: 16 / 12),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Whitelist
// ---------------------------------------------------------------------------

class _WhitelistView extends ConsumerStatefulWidget {
  const _WhitelistView();

  @override
  ConsumerState<_WhitelistView> createState() => _WhitelistViewState();
}

class _WhitelistViewState extends ConsumerState<_WhitelistView> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final query = _search.text.trim().toLowerCase();
    final all = ref.watch(whitelistProvider);
    final visible = query.isEmpty
        ? all
        : all
              .where((e) => e.name.toLowerCase().contains(query))
              .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stagger(
          index: 0,
          child: GlassPanel(
            level: 2,
            radius: Radii.pill,
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 18, color: t.textTertiary),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: TextField(
                    controller: _search,
                    style: context.type.bodyLarge?.copyWith(fontSize: 15),
                    cursorColor: t.accentPrimary,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Search installed apps…',
                      hintStyle: context.type.bodyMedium?.copyWith(
                        color: t.textTertiary,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
                if (query.isNotEmpty)
                  _SheetCloseButton(
                    label: 'Clear search',
                    onTap: () => setState(_search.clear),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Gap.xl),
        if (visible.isEmpty)
          Stagger(index: 1, child: _NoMatches(query: _search.text.trim()))
        else
          for (final tier in WhitelistTier.values)
            if (visible.any((e) => e.tier == tier)) ...[
              Stagger(
                // Tier order, not visible order, so the sequence stays
                // monotonic even when a tier has no matches.
                index: tier.index + 1,
                child: _WhitelistSection(
                  tier: tier,
                  entries: visible
                      .where((e) => e.tier == tier)
                      .toList(growable: false),
                ),
              ),
              const SizedBox(height: Gap.xl),
            ],
      ],
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    return GlassPanel(
      radius: Radii.card,
      padding: const EdgeInsets.all(Gap.xl),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 22, color: t.textTertiary),
          const SizedBox(height: Gap.md),
          Text(
            'No apps match “$query”',
            style: context.type.bodySmall?.copyWith(color: t.textTertiary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _WhitelistSection extends StatelessWidget {
  const _WhitelistSection({required this.tier, required this.entries});

  final WhitelistTier tier;
  final List<WhitelistEntry> entries;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final accent = tier.color;
    final showRemove = tier == WhitelistTier.alwaysAllowed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: Gap.md),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.6),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Gap.sm),
              Text(
                tier.label,
                style: context.type.labelMedium?.copyWith(
                  color: t.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              Text(
                '${entries.length}',
                style: context.type.labelSmall?.copyWith(color: t.textTertiary),
              ),
            ],
          ),
        ),
        GlassPanel(
          radius: Radii.card,
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.lg,
            vertical: Gap.xs,
          ),
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) Divider(color: t.hairline, height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.md),
                  child: _WhitelistRow(
                    entry: entries[i],
                    showRemove: showRemove,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _WhitelistRow extends ConsumerWidget {
  const _WhitelistRow({required this.entry, required this.showRemove});

  final WhitelistEntry entry;
  final bool showRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.glass;
    final blocked = entry.tier == WhitelistTier.blocked;
    final budgeted = entry.budgeted && !blocked;

    // Toggling a whitelist entry is really "is this app let through?" — off
    // means blocked. A budgeted app keeps its budget when it comes back on,
    // which is why this is not a plain two-state write.
    void toggle() {
      HapticFeedback.lightImpact();
      final next = blocked
          ? (entry.budgeted
                ? WhitelistTier.budgeted
                : WhitelistTier.alwaysAllowed)
          : WhitelistTier.blocked;
      ref.read(whitelistProvider.notifier).setTier(entry.id, next);
    }

    void remove() {
      HapticFeedback.mediumImpact();
      ref.read(whitelistProvider.notifier).remove(entry.id);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                container: true,
                toggled: !blocked,
                label: 'Allow ${entry.name}',
                onTap: toggle,
                child: ExcludeSemantics(
                  child: Pressable(
                    onTap: toggle,
                    child: Row(
                      children: [
                        GlassIconBadge(
                          icon: entry.icon,
                          color: entry.color,
                          size: 36,
                          radius: 11,
                          glow: blocked ? 0 : 0.35,
                        ),
                        const SizedBox(width: Gap.md),
                        Expanded(
                          child: Text(
                            entry.name,
                            style: context.type.titleSmall,
                          ),
                        ),
                        if (budgeted)
                          Text(
                            'Daily budget: ${entry.budgetMinutes}m',
                            style: context.type.labelSmall?.copyWith(
                              color: t.textTertiary,
                            ),
                          ),
                        const SizedBox(width: Gap.sm),
                        GlassToggle(
                          value: !blocked,
                          onChanged: (_) => toggle(),
                          accent: entry.tier.color,
                          semanticLabel: 'Allow ${entry.name}',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Kept outside the row's semantic node so the remove action stays
            // independently reachable instead of being swallowed by the
            // toggle region.
            if (showRemove) _RemoveButton(name: entry.name, onTap: remove),
          ],
        ),
        if (budgeted) ...[
          const SizedBox(height: Gap.md),
          Row(
            children: [
              Expanded(
                child: GlassProgressBar(
                  value: entry.usage,
                  color: entry.tier.color,
                  semanticLabel: '${entry.name} daily budget used',
                ),
              ),
              const SizedBox(width: Gap.sm),
              Text(
                '${entry.usedMinutes}m used',
                style: context.type.labelSmall?.copyWith(
                  color: entry.usage > 0.8 ? t.danger : t.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    return Semantics(
      button: true,
      label: 'Remove $name from the list',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Pressable(
          scale: 0.85,
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Icon(
                Icons.remove_circle_outline_rounded,
                size: 18,
                color: t.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profiles
// ---------------------------------------------------------------------------

class _ProfilesView extends ConsumerWidget {
  const _ProfilesView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.glass;
    final profiles = ref.watch(profilesProvider);
    final active = ref.watch(activeProfileProvider);
    final schedules = [
      for (final p in profiles)
        for (final window in p.schedules) (profile: p, window: window),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Stagger(
          index: 0,
          child: SectionHeader(
            title: 'Restriction profiles',
            icon: Icons.tune_rounded,
          ),
        ),
        Stagger(
          index: 1,
          child: SizedBox(
            height: 178,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 2),
              itemCount: profiles.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: Gap.md),
              itemBuilder: (context, i) {
                if (i == profiles.length) {
                  return _AddProfileCard(onTap: () => _showBuilder(context));
                }
                final p = profiles[i];
                return _ProfileCard(
                  profile: p,
                  active: p.id == active?.id,
                  onActivate: () {
                    HapticFeedback.selectionClick();
                    ref.read(profilesProvider.notifier).activate(p.id);
                  },
                );
              },
            ),
          ),
        ),
        const SizedBox(height: Gap.xl),
        const Stagger(
          index: 2,
          child: SectionHeader(
            title: 'Scheduled strictness',
            icon: Icons.schedule_rounded,
          ),
        ),
        Stagger(
          index: 3,
          child: GlassPanel(
            radius: Radii.card,
            padding: const EdgeInsets.all(Gap.lg),
            child: schedules.isEmpty
                ? Text(
                    'No schedules yet. Add one while creating a profile.',
                    style: context.type.bodySmall?.copyWith(
                      color: t.textTertiary,
                    ),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < schedules.length; i++) ...[
                        if (i > 0) Divider(color: t.hairline, height: Gap.xl),
                        _ScheduleRow(
                          label: schedules[i].profile.name,
                          detail: schedules[i].window,
                          color: schedules[i].profile.active
                              ? t.accentPrimary
                              : t.textTertiary,
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  void _showBuilder(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ProfileBuilderSheet(),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.active,
    required this.onActivate,
  });

  final RestrictionProfile profile;
  final bool active;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;

    return Semantics(
      button: true,
      container: true,
      selected: active,
      label: active
          ? '${profile.name} profile, active'
          : 'Activate ${profile.name} profile',
      onTap: onActivate,
      child: ExcludeSemantics(
        child: SizedBox(
          width: 196,
          child: Pressable(
            onTap: onActivate,
            child: GlassPanel(
              radius: Radii.card,
              padding: const EdgeInsets.all(Gap.lg),
              accent: active ? t.accentPrimary : null,
              glowStrength: active ? 0.8 : 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GlassIconBadge(
                        icon: profile.icon,
                        color: active ? t.accentPrimary : t.textTertiary,
                        size: 34,
                        radius: 10,
                        glow: active ? 0.6 : 0,
                      ),
                      const Spacer(),
                      if (active)
                        Icon(
                          Icons.check_circle_rounded,
                          size: 17,
                          color: t.accentPrimary,
                        ),
                    ],
                  ),
                  const SizedBox(height: Gap.md),
                  Text(profile.name, style: context.type.titleSmall),
                  const SizedBox(height: 3),
                  Text(
                    '${profile.blockedApps} apps blocked',
                    style: context.type.labelSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${profile.dailyTargetHours}h daily target',
                    style: context.type.labelSmall,
                  ),
                  const Spacer(),
                  GlassPill(
                    selected: active,
                    onTap: onActivate,
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.md,
                      vertical: 7,
                    ),
                    child: Text(
                      active ? 'Active' : 'Activate',
                      style: const TextStyle(fontSize: 12),
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

class _AddProfileCard extends StatelessWidget {
  const _AddProfileCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    return Semantics(
      button: true,
      label: 'Create a new restriction profile',
      onTap: onTap,
      child: ExcludeSemantics(
        child: SizedBox(
          width: 132,
          child: Pressable(
            onTap: onTap,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.card),
                border: Border.all(
                  color: t.glassL2Border,
                  style: BorderStyle.solid,
                ),
                color: t.glassL1Fill,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_rounded, size: 26, color: t.textTertiary),
                  const SizedBox(height: Gap.sm),
                  Text('New profile', style: context.type.labelSmall),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({
    required this.label,
    required this.detail,
    required this.color,
  });

  final String label;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    return MergeSemantics(
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8),
              ],
            ),
          ),
          const SizedBox(width: Gap.md),
          Expanded(child: Text(label, style: context.type.bodyLarge)),
          Text(
            detail,
            style: context.type.labelMedium?.copyWith(color: t.textTertiary),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile creation
// ---------------------------------------------------------------------------

/// A five-step builder in a near-full-height sheet: name, icon, apps, target,
/// schedule. It writes once, at the end, through the profiles notifier — an
/// abandoned flow must leave no trace.
class _ProfileBuilderSheet extends ConsumerStatefulWidget {
  const _ProfileBuilderSheet();

  @override
  ConsumerState<_ProfileBuilderSheet> createState() =>
      _ProfileBuilderSheetState();
}

class _ProfileBuilderSheetState extends ConsumerState<_ProfileBuilderSheet> {
  static const _stepCount = 5;
  static const _stepTitles = [
    'Name',
    'Icon',
    'Apps',
    'Daily target',
    'Schedule',
  ];
  static const _schedulePresets = [
    'Weekdays 16:00–21:00',
    'Every day 07:00–09:00',
    'Evening 20:00–22:30',
  ];

  final _name = TextEditingController();
  final _apps = <String>{};
  int _step = 0;
  String _icon = ProfileIcons.names.first;
  double _hours = 3;
  String? _schedule;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canAdvance => _step != 0 || _name.text.trim().isNotEmpty;

  void _next() {
    if (_step < _stepCount - 1) {
      setState(() => _step += 1);
    } else {
      _save();
    }
  }

  void _save() {
    ref
        .read(profilesProvider.notifier)
        .add(
          RestrictionProfile(
            id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
            name: _name.text.trim(),
            icon: ProfileIcons.resolve(_icon),
            blockedApps: _apps.length,
            dailyTargetHours: _hours,
            schedules: _schedule == null ? const [] : [_schedule!],
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final media = MediaQuery.of(context);
    // The sheet has to give way to the keyboard rather than be covered by it.
    final height = math.max(
      320.0,
      media.size.height * 0.94 - media.viewInsets.bottom,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.lg, Gap.md, Gap.md),
          child: GlassPanel(
            radius: Radii.hero,
            blur: t.blurL2,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SheetHeader(
                  title: 'New profile',
                  subtitle:
                      'Step ${_step + 1} of $_stepCount · ${_stepTitles[_step]}',
                  onClose: () => Navigator.of(context).pop(),
                ),
                _StepBar(step: _step, count: _stepCount),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      Gap.xl,
                      Gap.lg,
                      Gap.xl,
                      Gap.lg,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: KeyedSubtree(
                        key: ValueKey(_step),
                        child: _buildStep(),
                      ),
                    ),
                  ),
                ),
                _SheetFooter(
                  step: _step,
                  stepCount: _stepCount,
                  canAdvance: _canAdvance,
                  onBack: () => setState(() => _step -= 1),
                  onNext: _next,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep() => switch (_step) {
    0 => _NameStep(controller: _name, onChanged: () => setState(() {})),
    1 => _IconStep(
      selected: _icon,
      name: _name.text.trim(),
      onSelect: (name) => setState(() => _icon = name),
    ),
    2 => _AppsStep(
      selected: _apps,
      onToggle: (name) => setState(
        () => _apps.contains(name) ? _apps.remove(name) : _apps.add(name),
      ),
    ),
    3 => _TargetStep(
      hours: _hours,
      onChanged: (v) => setState(() => _hours = v),
    ),
    _ => _ScheduleStep(
      selected: _schedule,
      presets: _schedulePresets,
      onSelect: (s) => setState(() => _schedule = s),
    ),
  };
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.lg, Gap.md, Gap.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.type.titleMedium),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: context.type.labelSmall?.copyWith(
                    color: t.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          _SheetCloseButton(label: 'Close', onTap: onClose),
        ],
      ),
    );
  }
}

class _StepBar extends StatelessWidget {
  const _StepBar({required this.step, required this.count});

  final int step;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.md, Gap.xl, 0),
      child: Row(
        children: [
          for (var i = 0; i < count; i++)
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                height: 3,
                margin: EdgeInsets.only(right: i == count - 1 ? 0 : Gap.xs),
                decoration: BoxDecoration(
                  color: i <= step ? t.accentPrimary : t.track,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SheetFooter extends StatelessWidget {
  const _SheetFooter({
    required this.step,
    required this.stepCount,
    required this.canAdvance,
    required this.onBack,
    required this.onNext,
  });

  final int step;
  final int stepCount;
  final bool canAdvance;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final isLast = step == stepCount - 1;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.sm, Gap.xl, Gap.lg),
        child: Row(
          children: [
            if (step > 0)
              GlassPill(
                onTap: onBack,
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.xl,
                  vertical: Gap.lg,
                ),
                child: const Text(
                  'Back',
                  style: TextStyle(fontSize: 14, height: 20 / 14),
                ),
              ),
            const Spacer(),
            GlassPill(
              selected: canAdvance,
              onTap: canAdvance ? onNext : null,
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.xl,
                vertical: Gap.lg,
              ),
              child: Text(
                isLast ? 'Save profile' : 'Next',
                style: const TextStyle(fontSize: 14, height: 20 / 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepIntro extends StatelessWidget {
  const _StepIntro({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.type.titleMedium),
        const SizedBox(height: Gap.xs),
        Text(
          subtitle,
          style: context.type.bodySmall?.copyWith(color: t.textTertiary),
        ),
      ],
    );
  }
}

class _NameStep extends StatelessWidget {
  const _NameStep({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepIntro(
          title: 'Name your profile',
          subtitle: 'A label you will recognise at a glance.',
        ),
        const SizedBox(height: Gap.lg),
        GlassPanel(
          level: 2,
          radius: Radii.item,
          padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
          child: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onChanged: (_) => onChanged(),
            style: context.type.bodyLarge?.copyWith(fontSize: 15),
            cursorColor: t.accentPrimary,
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: 'e.g. Exam Week',
              hintStyle: context.type.bodyMedium?.copyWith(
                color: t.textTertiary,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 15),
            ),
          ),
        ),
      ],
    );
  }
}

class _IconStep extends StatelessWidget {
  const _IconStep({
    required this.selected,
    required this.name,
    required this.onSelect,
  });

  final String selected;
  final String name;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepIntro(
          title: 'Pick an icon',
          subtitle: 'Shown on the profile card in the row.',
        ),
        const SizedBox(height: Gap.lg),
        Center(
          child: GlassIconBadge(
            icon: ProfileIcons.resolve(selected),
            color: t.accentPrimary,
            size: 64,
            radius: 20,
            glow: 0.7,
          ),
        ),
        const SizedBox(height: Gap.sm),
        Center(
          child: Text(
            name.isEmpty ? 'Your profile' : name,
            style: context.type.labelMedium,
          ),
        ),
        const SizedBox(height: Gap.xl),
        Wrap(
          spacing: Gap.md,
          runSpacing: Gap.md,
          alignment: WrapAlignment.center,
          children: [
            for (final iconName in ProfileIcons.names)
              _IconChoice(
                name: iconName,
                selected: iconName == selected,
                onTap: () => onSelect(iconName),
              ),
          ],
        ),
      ],
    );
  }
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Icon $name',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Pressable(
          scale: 0.9,
          onTap: onTap,
          child: GlassIconBadge(
            icon: ProfileIcons.resolve(name),
            color: selected ? t.accentPrimary : t.textTertiary,
            size: 52,
            radius: 16,
            glow: selected ? 0.6 : 0,
          ),
        ),
      ),
    );
  }
}

class _AppChoice {
  const _AppChoice(this.name, this.icon, this.color);

  final String name;
  final IconData icon;
  final Color color;
}

class _AppsStep extends ConsumerWidget {
  const _AppsStep({required this.selected, required this.onToggle});

  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choices = <_AppChoice>[];
    for (final row in ref.watch(allFeedRowsProvider)) {
      if (choices.every((c) => c.name != row.appName)) {
        choices.add(_AppChoice(row.appName, row.icon, row.color));
      }
    }
    for (final entry in ref.watch(whitelistProvider)) {
      if (entry.tier == WhitelistTier.blocked &&
          choices.every((c) => c.name != entry.name)) {
        choices.add(_AppChoice(entry.name, entry.icon, entry.color));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepIntro(
          title: 'What should it block?',
          subtitle: '${selected.length} selected · tap to toggle',
        ),
        const SizedBox(height: Gap.lg),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            for (final choice in choices)
              Semantics(
                button: true,
                selected: selected.contains(choice.name),
                label: 'Block ${choice.name}',
                onTap: () => onToggle(choice.name),
                child: ExcludeSemantics(
                  child: GlassPill(
                    selected: selected.contains(choice.name),
                    accent: choice.color,
                    onTap: () => onToggle(choice.name),
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.md,
                      vertical: Gap.lg,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(choice.icon, size: 15, color: choice.color),
                        const SizedBox(width: 6),
                        Text(
                          choice.name,
                          style: const TextStyle(fontSize: 12, height: 16 / 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TargetStep extends StatelessWidget {
  const _TargetStep({required this.hours, required this.onChanged});

  final double hours;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepIntro(
          title: 'Daily focus target',
          subtitle: 'How much focused time this profile aims for each day.',
        ),
        const SizedBox(height: Gap.xl),
        Center(
          child: Text(
            '${hours.toStringAsFixed(1)}h',
            style: context.type.displayMedium,
          ),
        ),
        const SizedBox(height: Gap.sm),
        Slider(
          value: hours,
          min: 1,
          max: 8,
          divisions: 14,
          semanticFormatterCallback: (v) =>
              '${v.toStringAsFixed(1)} hours daily target',
          onChanged: onChanged,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('1h', style: context.type.labelSmall),
              Text('8h', style: context.type.labelSmall),
            ],
          ),
        ),
        const SizedBox(height: Gap.lg),
        Text(
          'You can change this later — it only sets the goal the dashboard '
          'measures against.',
          style: context.type.bodySmall?.copyWith(color: t.textTertiary),
        ),
      ],
    );
  }
}

class _ScheduleStep extends StatelessWidget {
  const _ScheduleStep({
    required this.selected,
    required this.presets,
    required this.onSelect,
  });

  final String? selected;
  final List<String> presets;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepIntro(
          title: 'Schedule (optional)',
          subtitle: 'When this profile should apply itself.',
        ),
        const SizedBox(height: Gap.lg),
        _ScheduleOption(
          label: 'No schedule',
          icon: Icons.remove_circle_outline_rounded,
          selected: selected == null,
          onTap: () => onSelect(null),
        ),
        for (final preset in presets)
          _ScheduleOption(
            label: preset,
            icon: Icons.schedule_rounded,
            selected: selected == preset,
            onTap: () => onSelect(preset),
          ),
      ],
    );
  }
}

class _ScheduleOption extends StatelessWidget {
  const _ScheduleOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        onTap: onTap,
        child: ExcludeSemantics(
          child: Pressable(
            onTap: onTap,
            child: GlassPanel(
              level: selected ? 2 : 1,
              radius: Radii.item,
              accent: selected ? t.accentPrimary : null,
              glowStrength: selected ? 0.6 : 0,
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.lg,
                vertical: Gap.md,
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: selected ? t.accentPrimary : t.textTertiary,
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(child: Text(label, style: context.type.bodyLarge)),
                  if (selected)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: t.accentPrimary,
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
