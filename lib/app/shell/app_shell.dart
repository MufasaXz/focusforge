import 'package:flutter/material.dart';

import '../../features/dashboard/dashboard_screen.dart';
import '../../features/focus/focus_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/shield/shield_screen.dart';
import '../../shared/widgets/glass_nav_bar.dart';
import '../../shared/widgets/mesh_background.dart';

/// Root shell: ambient canvas, the four tab screens, and the floating nav bar.
///
/// Screens stay mounted (state — timers, toggles, scroll position — survives
/// tab switches) while only the active one paints. Switching runs a short
/// fade-through so the incoming screen rises into place.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  /// The app is phone-shaped; on wide viewports it is centred at this width.
  static const double maxContentWidth = 460;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  int _index = 0;
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

  void _select(int i) {
    if (i == _index) return;
    setState(() {
      _index = i;
      _compact = false;
    });
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
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                      child: Stack(
                        children: [
                          for (var i = 0; i < _items.length; i++)
                            Offstage(
                              offstage: i != _index,
                              child: TickerMode(
                                enabled: i == _index,
                                child: _screenFor(i),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: GlassNavBar(
                    index: _index,
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
    );
  }

  Widget _screenFor(int i) => switch (i) {
        0 => const DashboardScreen(),
        1 => const ShieldScreen(),
        2 => const FocusScreen(),
        _ => const ProfileScreen(),
      };
}

/// Bottom padding every screen should reserve so content clears the nav bar.
const double kNavBarClearance = 118;
