import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/app_providers.dart';
import '../../core/providers/coach_providers.dart';
import '../../core/providers/shield_providers.dart';
import '../../core/providers/study_providers.dart';
import '../../core/services/native_shield_service.dart';
import '../../features/shield/breath_gate.dart';
import '../router.dart';

/// Root shell: the four tab branches and the frosted navigation bar.
///
/// The branch stack itself is owned by go_router's
/// [StatefulShellRoute.indexedStack] — each tab keeps its own [Navigator], so
/// pushing a settings screen from Profile leaves the other three tabs exactly
/// where they were.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// How wide the content column is allowed to get on a phone-shaped viewport.
  ///
  /// Below [railBreakpoint] the app is one column and this is what keeps a
  /// tablet in portrait from stretching a phone layout across it.
  static const double maxContentWidth = 460;

  /// How wide the content is allowed to get beside the rail.
  ///
  /// Wider than the phone column because the screens have somewhere to put it —
  /// the dashboard goes to two columns — but still capped, because a line of
  /// body text that runs the full width of a tablet is unreadable.
  static const double maxWideContentWidth = 1100;

  /// The width at which the bottom bar becomes a rail.
  ///
  /// Material's own window-size breakpoint between "compact" and "medium".
  /// Below it the bar is the right control; above it a bar stretched across a
  /// tablet is a phone control on a desk.
  static const double railBreakpoint = 720;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A cold start can be a launch the block screen sent us: "open it anyway"
    // brings the app up so the pause can be shown.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkBlockedLaunch());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fade.dispose();
    super.dispose();
  }

  /// A backgrounded app receives no timers. The moment we come back, the focus
  /// timer recomputes from its stored end instant rather than resuming a
  /// counter that has been standing still.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(timerProvider.notifier).sync();
      unawaited(_checkBlockedLaunch());
    }
  }

  /// Shows the pause after the user chose to open a blocked app anyway.
  ///
  /// The block screen hands the app back with the package it was covering, and
  /// the breath gate is the whole reason the choice was offered: a silent
  /// return to the dashboard would turn "open it anyway" into a plain escape
  /// hatch with no cost at all. The extras are read once and cleared natively,
  /// so a later resume cannot replay the same pause.
  ///
  /// The package travels with the gate rather than being dropped here — it is
  /// what the gate hands back when the pause is over.
  Future<void> _checkBlockedLaunch() async {
    final service = ref.read(shieldServiceProvider);
    if (service is! NativeShieldService) return;
    final blocked = await service.takeBlockedApp();
    if (blocked == null || !mounted) return;
    context.push(
      AppRoutes.paths[AppRoutes.breathGate]!,
      extra: BreathGateArgs(
        appName: blocked.label,
        packageId: blocked.packageId,
        graceSeconds: blocked.graceSeconds,
      ),
    );
  }

  void _select(int displayIndex) {
    final branches = _visibleBranches;
    if (displayIndex < 0 || displayIndex >= branches.length) return;
    final branch = branches[displayIndex];
    if (branch == widget.navigationShell.currentIndex) return;
    // A tab change is the one navigation this app has, and it is silent
    // otherwise: the bar is at the far edge of the screen from where the
    // content lands. The lightest haptic is enough to say it registered.
    unawaited(HapticFeedback.selectionClick());
    // `initialLocation: true` when re-tapping a tab pops it back to its root,
    // which is the behaviour every bottom-nav app is expected to have.
    widget.navigationShell.goBranch(
      branch,
      initialLocation: branch == widget.navigationShell.currentIndex,
    );
    _fade.forward(from: 0);
  }

  /// The branches this device's bar offers, in bar order.
  ///
  /// A parent's app is three destinations: the dashboard, the shield and
  /// their profile. The Focus branch still exists and is still reachable —
  /// the dashboard's own call to action starts a session — but a parent's
  /// device is not the one being studied, and a tab for it is a tab that
  /// never gets used.
  List<int> get _visibleBranches =>
      ref.read(userProvider).isGuardian ? const [0, 1, 3] : const [0, 1, 2, 3];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final shielded = ref.watch(activeShieldCountProvider) > 0;
    final wide = MediaQuery.sizeOf(context).width >= AppShell.railBreakpoint;

    // Keyed by branch index, so the bar's order and the router's branches stay
    // one list rather than two that have to agree.
    final all = [
      const NavigationDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: 'Home',
      ),
      NavigationDestination(
        icon: _CoachAnchor(
          anchorKey: ref.watch(coachTargetsProvider).shieldTab,
          child: _ShieldIcon(shielded: shielded, icon: Icons.shield_outlined),
        ),
        selectedIcon: _ShieldIcon(shielded: shielded, icon: Icons.shield),
        label: 'Shield',
      ),
      NavigationDestination(
        // The first-run tips point at this icon from the root overlay, so the
        // key has to be attached where the icon is really built rather than at
        // the destination.
        icon: _CoachAnchor(
          anchorKey: ref.watch(coachTargetsProvider).focusTab,
          child: const Icon(Icons.timer_outlined),
        ),
        selectedIcon: const Icon(Icons.timer),
        label: 'Focus',
      ),
      const NavigationDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: 'You',
      ),
    ];

    final branches = ref.watch(userProvider.select((u) => u.isGuardian))
        ? const [0, 1, 3]
        : const [0, 1, 2, 3];
    final destinations = [for (final branch in branches) all[branch]];
    // The Focus branch can be current while it is not a destination, because
    // the dashboard sends a session there. Home stands in for it rather than
    // leaving the bar with nothing selected.
    final current = branches.indexOf(widget.navigationShell.currentIndex);
    final selectedIndex = current < 0 ? 0 : current;

    // The branch fade, shared by both shapes.
    final body = AnimatedBuilder(
      animation: _fade,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_fade.value);
        return Opacity(
          opacity: 0.001 + 0.999 * t,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.navigationShell,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Driven by the live theme rather than set once in main(), so toggling
      // to dark does not leave dark-on-dark status glyphs.
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: cs.surface,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: wide
          // A tablet gets the rail. The bar is not stretched across it: a
          // four-item bar spanning 1200dp puts Home and You a hand apart, and
          // it costs a strip of height the content could use.
          ? Scaffold(
              body: Row(
                children: [
                  SafeArea(
                    right: false,
                    child: NavigationRail(
                      selectedIndex: selectedIndex,
                      onDestinationSelected: _select,
                      labelType: NavigationRailLabelType.all,
                      backgroundColor: cs.surfaceContainerLow,
                      // Compact: icons and their labels, no extended drawer.
                      // The rail is navigation, not a place to put things.
                      minWidth: 76,
                      groupAlignment: -0.6,
                      destinations: [
                        for (final d in destinations)
                          NavigationRailDestination(
                            icon: d.icon,
                            selectedIcon: d.selectedIcon,
                            label: Text(d.label),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: AppShell.maxWideContentWidth,
                        ),
                        // The branch body is its own semantics container, and
                        // that is load-bearing rather than tidiness: every
                        // route carries a [ModalBarrier], and a barrier wraps
                        // [BlockSemantics], which drops the semantics of
                        // everything painted before it. The rail is painted
                        // before the body, so without this boundary the whole
                        // navigation disappears from the screen reader the
                        // moment a real screen is on the other side of it.
                        // The bottom bar has no such problem — a Scaffold
                        // paints it after the body.
                        child: Semantics(
                          container: true,
                          explicitChildNodes: true,
                          child: body,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : Scaffold(
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppShell.maxContentWidth,
                  ),
                  child: body,
                ),
              ),
              // One of the three places the design allows a real backdrop blur:
              // the bar floats over scrolling content, and the blur is what
              // says so. Everywhere else uses a solid tonal surface.
              bottomNavigationBar: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppShell.maxContentWidth,
                  ),
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: NavigationBar(
                        backgroundColor: cs.surface.withValues(alpha: 0.85),
                        selectedIndex: selectedIndex,
                        onDestinationSelected: _select,
                        destinations: destinations,
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// Attaches a coach-mark key to a destination glyph.
///
/// A [NavigationDestination] takes a widget for its icon, not a key, so the
/// key has to be carried by a widget that is actually built inside the bar —
/// otherwise the first-run tip measures the destination's slot rather than the
/// glyph the user is being told to tap.
class _CoachAnchor extends StatelessWidget {
  const _CoachAnchor({required this.anchorKey, required this.child});

  final Key anchorKey;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: anchorKey, child: child);
}

/// Shield destination glyph with an M3 [Badge] while any shield is armed.
///
/// A dot rather than a count: the number belongs on the Shield screen, where
/// there is room to say what it counts.
class _ShieldIcon extends StatelessWidget {
  const _ShieldIcon({required this.shielded, required this.icon});

  final bool shielded;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (!shielded) return Icon(icon);
    return Badge(
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: Icon(icon),
    );
  }
}

/// Bottom padding a tab's scroll view should leave under its last row.
///
/// The navigation bar is docked in the scaffold's own slot now, so the body is
/// already laid out above it — this is breathing room, not clearance.
const double kNavBarClearance = 24;
