import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/study_providers.dart';
import '../../shared/widgets/glass_nav_bar.dart';
import '../../shared/widgets/mesh_background.dart';

/// Root shell: ambient canvas, the four tab branches, and the floating nav bar.
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
  bool _compact = false;

  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    value: 1,
  );

  static const _items = <NavItem>[
    NavItem(
      icon: Icons.grid_view_rounded,
      activeIcon: Icons.grid_view_rounded,
      label: 'Home',
    ),
    NavItem(
      icon: Icons.shield_outlined,
      activeIcon: Icons.shield_rounded,
      label: 'Shield',
      statusDot: true,
    ),
    NavItem(
      icon: Icons.timer_outlined,
      activeIcon: Icons.timer_rounded,
      label: 'Focus',
    ),
    NavItem(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'You',
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    }
  }

  void _select(int i) {
    if (i == widget.navigationShell.currentIndex) return;
    // `initialLocation: true` when re-tapping a tab pops it back to its root,
    // which is the behaviour every bottom-nav app is expected to have.
    widget.navigationShell.goBranch(
      i,
      initialLocation: i == widget.navigationShell.currentIndex,
    );
    setState(() => _compact = false);
    _fade.forward(from: 0);
  }

  /// Shrink the bar while the user scrolls down, restore it on the way up.
  bool _onScroll(ScrollNotification n) {
    if (n is! ScrollUpdateNotification) return false;
    final delta = n.scrollDelta ?? 0;
    if (delta > 3 && !_compact && n.metrics.pixels > 48) {
      setState(() => _compact = true);
    } else if (delta < -3 && _compact) {
      setState(() => _compact = false);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Driven by the live theme rather than set once in main(), so toggling
      // to dark does not leave dark-on-dark status glyphs.
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: MeshBackground(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppShell.maxContentWidth,
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onScroll,
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
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: GlassNavBar(
                      index: widget.navigationShell.currentIndex,
                      items: _items,
                      compact: _compact,
                      onChanged: _select,
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

/// Bottom padding every screen should reserve so content clears the nav bar.
const double kNavBarClearance = 118;
