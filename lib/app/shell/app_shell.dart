import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/coach_providers.dart';
import '../../core/providers/shield_providers.dart';
import '../../core/providers/study_providers.dart';
import '../../core/services/native_shield_service.dart';
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

  /// The app is phone-shaped; on wide viewports it is centred at this width.
  static const double maxContentWidth = 460;

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
  Future<void> _checkBlockedLaunch() async {
    final service = ref.read(shieldServiceProvider);
    if (service is! NativeShieldService) return;
    final blocked = await service.takeBlockedApp();
    if (blocked == null || !mounted) return;
    final label = blocked['label'];
    context.push(
      AppRoutes.paths[AppRoutes.breathGate]!,
      extra: label is String && label.isNotEmpty ? label : 'That app',
    );
  }

  void _select(int i) {
    if (i == widget.navigationShell.currentIndex) return;
    // `initialLocation: true` when re-tapping a tab pops it back to its root,
    // which is the behaviour every bottom-nav app is expected to have.
    widget.navigationShell.goBranch(
      i,
      initialLocation: i == widget.navigationShell.currentIndex,
    );
    _fade.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final shielded = ref.watch(activeShieldCountProvider) > 0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Driven by the live theme rather than set once in main(), so toggling
      // to dark does not leave dark-on-dark status glyphs.
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: cs.surface,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppShell.maxContentWidth),
            child: AnimatedBuilder(
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
            ),
          ),
        ),
        // One of the three places the design allows a real backdrop blur: the
        // bar floats over scrolling content, and the blur is what says so.
        // Everywhere else uses a solid tonal surface.
        bottomNavigationBar: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppShell.maxContentWidth),
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: NavigationBar(
                  backgroundColor: cs.surface.withValues(alpha: 0.85),
                  selectedIndex: widget.navigationShell.currentIndex,
                  onDestinationSelected: _select,
                  destinations: [
                    const NavigationDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: _ShieldIcon(
                        shielded: shielded,
                        icon: Icons.shield_outlined,
                      ),
                      selectedIcon: _ShieldIcon(
                        shielded: shielded,
                        icon: Icons.shield,
                      ),
                      label: 'Shield',
                    ),
                    NavigationDestination(
                      // The first-run tips point at this icon from the root
                      // overlay, so the key has to be attached where the icon
                      // is really built rather than at the destination.
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
                  ],
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
  Widget build(BuildContext context) => KeyedSubtree(key: anchorKey, child: child);
}

/// Shield destination glyph with an M3 [Badge] while any shield is armed.
///
/// A dot rather than a count: the number belongs on the Shield screen, where
/// there is room to say what it counts.
class _ShieldIcon extends StatelessWidget {  const _ShieldIcon({required this.shielded, required this.icon});

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
