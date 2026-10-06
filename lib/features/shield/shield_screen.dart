import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/shell/app_shell.dart';
import '../../app/theme/app_theme.dart';
import '../../core/models/shield.dart';
import '../../core/providers/shield_providers.dart';
import '../../core/providers/usage_providers.dart';
import '../../core/services/app_catalog.dart';
import '../../core/services/native_shield_service.dart';
import '../../core/services/permission_manager.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/app_icon_avatar.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/icon_badge.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/stagger.dart';
import 'app_picker_sheet.dart';
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
  /// before the trip would still say "off" after it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    ref.invalidate(shieldEnabledProvider);
    ref.invalidate(usageAccessProvider);
    ref.invalidate(appUsageTodayProvider);
    ref.invalidate(installedAppsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final topInset = MediaQuery.paddingOf(context).top;
    final headerHeight = 172 + topInset;
    final armed = ref.watch(activeShieldCountProvider);

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
                  0 => const _AppsView(),
                  1 => const _YoutubeView(),
                  _ => const _ActivityView(),
                },
              ],
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          // A solid surface, not a frosted bar: M3 expresses layering through
          // surface tone, and a backdrop filter here would be spent on chrome
          // that never moves.
          child: Container(
            color: cs.surface,
            padding: EdgeInsets.fromLTRB(
              Gap.lg + 4,
              topInset + Gap.lg,
              Gap.lg + 4,
              Gap.lg,
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
                            'Shield',
                            style: Theme.of(
                              context,
                            ).textTheme.headlineMedium?.copyWith(fontSize: 24),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Close what pulls you away',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Gap.md),
                    _ShieldStatusPill(
                      armed: armed,
                      onTap: _showStatusSheet,
                    ),
                  ],
                ),
                const SizedBox(height: Gap.lg),
                // `double.infinity` makes the button fill the header: the M3
                // segmented button otherwise shrink-wraps its segments.
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    segments: [
                      for (var i = 0; i < _segmentOptions.length; i++)
                        ButtonSegment(
                          value: i,
                          label: Text(_segmentOptions[i]),
                        ),
                    ],
                    selected: {_segment},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) =>
                        setState(() => _segment = selection.first),
                  ),
                ),
              ],
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
  const _ShieldStatusPill({required this.armed, required this.onTap});

  final int armed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final on = armed > 0;
    final color = on ? cs.tertiary : cs.onSurfaceVariant;
    final label = on ? '$armed armed' : 'Nothing armed';

    return Semantics(
      button: true,
      container: true,
      label: 'Shield status. $armed rules armed. Double tap for details.',
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
                    label,
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

    return _SheetSurface(
      padding: const EdgeInsets.all(Gap.xl),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SheetHandle(),
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
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
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
                            style: Theme.of(
                              context,
                            ).textTheme.labelSmall?.copyWith(height: 1.4),
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
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// 48dp close affordance shared by the sheets on this screen.
class _SheetCloseButton extends StatelessWidget {
  const _SheetCloseButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The grabber at the top of every sheet on this screen.
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
      ),
    );
  }
}

/// Frosted bottom-sheet surface.
///
/// A sheet genuinely floats over the page, so its backdrop filter is one of
/// the three the design allows — σ24, per the redesign guide. The top corners
/// are the sheet's own; the bottom edge sits flush with the screen.
class _SheetSurface extends StatelessWidget {
  const _SheetSurface({required this.child, this.padding = EdgeInsets.zero});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(Radii.hero),
      ),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          color: cs.surfaceContainerLow.withValues(alpha: 0.9),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Apps
// ---------------------------------------------------------------------------

class _AppsView extends ConsumerStatefulWidget {
  const _AppsView();

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
    final all = ref.watch(enrichedWhitelistProvider);
    final native = NativeShieldService.isSupported;
    final enabled = ref.watch(shieldEnabledProvider).valueOrNull ?? false;
    final usageAccess = ref.watch(usageAccessProvider).valueOrNull ?? false;
    final budgeted = ref.watch(budgetedAppsProvider).length;

    final visible = query.isEmpty
        ? all
        : all
              .where((e) => e.name.toLowerCase().contains(query))
              .toList(growable: false);

    var index = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (native && !enabled)
          Stagger(
            index: index++,
            child: const _PermissionGate(
              icon: Icons.accessibility_new_rounded,
              title: 'Turn on app blocking',
              body:
                  'Android closes an app through its accessibility service. '
                  'FocusForge needs it on before a single rule can do '
                  'anything.',
              action: 'Open accessibility settings',
              permission: AppPermission.accessibility,
            ),
          ),
        if (native && enabled && budgeted > 0 && !usageAccess)
          Stagger(
            index: index++,
            child: const _PermissionGate(
              icon: Icons.timelapse_rounded,
              title: 'Time budgets are not counting',
              body:
                  'A budget needs to read how long an app has been open. '
                  'Without usage access it is armed but inert.',
              action: 'Open usage access settings',
              permission: AppPermission.usageAccess,
            ),
          ),
        Stagger(
          index: index++,
          child: FilledButton.tonalIcon(
            onPressed: () => showAppPickerSheet(context),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add apps'),
          ),
        ),
        const SizedBox(height: Gap.xl),
        if (all.isEmpty)
          Stagger(index: index++, child: const _NoRules())
        else ...[
          Stagger(
            index: index++,
            child: _SearchField(
              controller: _search,
              onChanged: () => setState(() {}),
            ),
          ),
          const SizedBox(height: Gap.xl),
          if (visible.isEmpty)
            Stagger(index: index++, child: _NoMatches(query: _search.text.trim()))
          else
            for (final tier in WhitelistTier.values)
              if (visible.any((e) => e.tier == tier)) ...[
                Stagger(
                  // Tier order, not visible order, so the sequence stays
                  // monotonic even when a tier has no matches.
                  index: index++,
                  child: _RuleSection(
                    tier: tier,
                    entries: visible
                        .where((e) => e.tier == tier)
                        .toList(growable: false),
                  ),
                ),
                const SizedBox(height: Gap.xl),
              ],
        ],
        Text(
          'A rule applies the moment you add it — there is nothing to switch '
          'on afterwards.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
        ),
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
        hintText: 'Search your rules…',
        hintStyle: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 18,
          color: cs.onSurfaceVariant,
        ),
        suffixIcon: !hasText
            ? null
            : _SheetCloseButton(
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
class _NoRules extends StatelessWidget {
  const _NoRules();

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
              IconBadge(
                icon: Icons.shield_outlined,
                color: cs.primary,
                size: 56,
                radius: 18,
              ),
              const SizedBox(height: Gap.lg),
              Text(
                'Nothing is armed yet',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: Gap.sm),
              Text(
                'Add the apps you open without meaning to. Blocked apps close '
                'the moment they open; budgeted ones close once the day\'s '
                'allowance is spent.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
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
                'No rule matches “$query”',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuleSection extends StatelessWidget {
  const _RuleSection({required this.tier, required this.entries});

  final WhitelistTier tier;
  final List<WhitelistEntry> entries;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = harmonize(tier.color, cs.primary);

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
                ),
              ),
              const SizedBox(width: Gap.sm),
              Text(
                tier.label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              Text(
                '${entries.length}',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Card.filled(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.lg,
              vertical: Gap.xs,
            ),
            child: Column(
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0) Divider(color: cs.outlineVariant, height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Gap.md),
                    child: _RuleRow(entry: entries[i]),
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

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.entry});

  final WhitelistEntry entry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = harmonize(entry.tier.color, cs.primary);
    final budgeted = entry.tier == WhitelistTier.budgeted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          container: true,
          label: _semanticLabel(entry),
          onTap: () => _openRuleSheet(context, entry),
          child: ExcludeSemantics(
            child: Pressable(
              onTap: () => _openRuleSheet(context, entry),
              child: Row(
                children: [
                  AppIconAvatar(
                    packageId: entry.packageId,
                    fallbackIcon: entry.icon,
                    fallbackColor: accent,
                    size: 40,
                    radius: 12,
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.name,
                          style: Theme.of(context).textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          _subtitle(entry),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  _TierChip(tier: entry.tier, color: accent),
                ],
              ),
            ),
          ),
        ),
        if (budgeted) ...[
          const SizedBox(height: Gap.md),
          Semantics(
            label: '${entry.name} daily budget used',
            value: '${entry.usedMinutes} of ${entry.budgetMinutes} minutes',
            child: LinearProgressIndicator(
              value: entry.usage,
              color: entry.overBudget ? cs.error : accent,
              backgroundColor: cs.surfaceContainerHighest,
              minHeight: 5,
            ),
          ),
        ],
      ],
    );
  }

  static String _subtitle(WhitelistEntry entry) => switch (entry.tier) {
    WhitelistTier.blocked => 'Closes when opened',
    WhitelistTier.budgeted =>
      '${formatMinutes(entry.usedMinutes)} of '
          '${formatMinutes(entry.budgetMinutes ?? 0)} used today',
    WhitelistTier.alwaysAllowed => 'Never closed',
  };

  static String _semanticLabel(WhitelistEntry entry) => switch (entry.tier) {
    WhitelistTier.blocked => '${entry.name}, blocked. Change rule',
    WhitelistTier.budgeted =>
      '${entry.name}, budgeted at ${entry.budgetMinutes} minutes a day, '
          '${entry.usedMinutes} used. Change rule',
    WhitelistTier.alwaysAllowed =>
      '${entry.name}, always allowed. Change rule',
  };
}

/// The tier, as a chip. Tapping it opens the same sheet the row does — the
/// chip is a label first, so it carries the state in words rather than in
/// colour alone.
class _TierChip extends StatelessWidget {
  const _TierChip({required this.tier, required this.color});

  final WhitelistTier tier;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        switch (tier) {
          WhitelistTier.blocked => 'Blocked',
          WhitelistTier.budgeted => 'Budgeted',
          WhitelistTier.alwaysAllowed => 'Allowed',
        },
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Per-app rule editor.
///
/// A sheet rather than a row of controls: the three tiers are mutually
/// exclusive and the budget only means something in one of them, so showing
/// them together is the only way the choice reads as one decision.
Future<void> _openRuleSheet(BuildContext context, WhitelistEntry entry) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _AppRuleSheet(entry: entry),
  );
}

class _AppRuleSheet extends ConsumerStatefulWidget {
  const _AppRuleSheet({required this.entry});

  final WhitelistEntry entry;

  @override
  ConsumerState<_AppRuleSheet> createState() => _AppRuleSheetState();
}

class _AppRuleSheetState extends ConsumerState<_AppRuleSheet> {
  late WhitelistTier _tier = widget.entry.tier;
  late int _budget =
      widget.entry.budgetMinutes ?? WhitelistNotifier.defaultBudgetMinutes;

  static const _step = 5;
  static const _min = 5;
  static const _max = 8 * 60;

  Future<void> _apply() async {
    final notifier = ref.read(whitelistProvider.notifier);
    if (_tier == WhitelistTier.budgeted) {
      await notifier.setTier(widget.entry.id, _tier);
      await notifier.setBudget(widget.entry.id, _budget);
    } else {
      await notifier.setTier(widget.entry.id, _tier);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    await ref.read(whitelistProvider.notifier).remove(widget.entry.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // The live row, so the usage bar reflects what the platform reports rather
    // than the snapshot the sheet was opened with.
    final live = ref
        .watch(enrichedWhitelistProvider)
        .where((e) => e.id == widget.entry.id)
        .firstOrNull;
    final entry = live ?? widget.entry;

    return _SheetSurface(
      padding: const EdgeInsets.all(Gap.xl),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SheetHandle(),
              const SizedBox(height: Gap.lg),
              Row(
                children: [
                  AppIconAvatar(
                    packageId: entry.packageId,
                    fallbackIcon: entry.icon,
                    fallbackColor: harmonize(entry.tier.color, cs.primary),
                    size: 48,
                    radius: 14,
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.name,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          entry.packageId ?? 'No package — cannot be enforced',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  _SheetCloseButton(
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
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleSmall,
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
                        if (entry.usedMinutes > 0) ...[
                          const SizedBox(height: Gap.sm),
                          Semantics(
                            label: 'Used today',
                            value: formatMinutes(entry.usedMinutes),
                            child: LinearProgressIndicator(
                              value: (_budget == 0
                                  ? 0
                                  : entry.usedMinutes / _budget),
                              color: entry.usedMinutes >= _budget
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
                              '${formatMinutes(entry.usedMinutes)} used today',
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
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _remove,
                      style: TextButton.styleFrom(
                        foregroundColor: cs.error,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Remove'),
                    ),
                  ),
                  const SizedBox(width: Gap.md),
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
          child: SectionHeader(
            title: 'Surfaces',
            icon: Icons.tune_rounded,
          ),
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
                  onChanged: (v) =>
                      ref.read(youtubeRulesProvider.notifier).setShorts(v),
                ),
                Divider(color: cs.outlineVariant, height: 1),
                _SurfaceSwitch(
                  icon: Icons.dynamic_feed_rounded,
                  title: 'Block home & search',
                  body:
                      'Removes the recommendation feed and search results. A '
                      'video has to be opened from a direct link.',
                  value: rules.feed,
                  onChanged: (v) =>
                      ref.read(youtubeRulesProvider.notifier).setFeed(v),
                ),
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
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(height: 1.4),
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
                  fullyBlocked ? 'Stop blocking YouTube' : 'Block all of YouTube',
                ),
                subtitle: Text(
                  fullyBlocked
                      ? 'Removes it from the blocked list'
                      : 'Closes the app entirely, Shorts and lectures alike',
                ),
                onTap: () {
                  HapticFeedback.selectionClick();
                  final notifier = ref.read(whitelistProvider.notifier);
                  if (fullyBlocked) {
                    notifier.remove('pkg:${AppCatalog.youtubePackage}');
                  } else {
                    notifier.addInstalledApp(
                      packageId: AppCatalog.youtubePackage,
                      name: 'YouTube',
                      tier: WhitelistTier.blocked,
                    );
                  }
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
      secondary: Icon(
        icon,
        color: value ? cs.tertiary : cs.onSurfaceVariant,
      ),
      title: Text(title, style: Theme.of(context).textTheme.titleSmall),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          body,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
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
                        if (i > 0)
                          Divider(color: cs.outlineVariant, height: 1),
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
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
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
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
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
      padding: const EdgeInsets.symmetric(
        horizontal: Gap.sm + 2,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
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
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(height: 1.4),
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
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
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
