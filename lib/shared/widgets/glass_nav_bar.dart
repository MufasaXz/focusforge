import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/theme/color_tokens.dart';
import '../../app/theme/glass_theme.dart';
import 'glass_surface.dart';

class NavItem {
  const NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.statusDot = false,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;

  /// Small pulsing indicator — used for "protection active" style states.
  /// Deliberately not a number: counts belong in the content, not the chrome.
  final bool statusDot;
}

/// Floating frosted navigation bar.
///
/// Three details do the heavy lifting:
///  1. it floats — inset from every edge, so content scrolls visibly past it;
///  2. the indicator is a *morphing* pill — it stretches while travelling and
///     settles with a spring overshoot instead of snapping;
///  3. it shrinks on scroll — labels drop out and the bar gets shorter as the
///     user scrolls down, then returns when they scroll back up.
class GlassNavBar extends StatefulWidget {
  const GlassNavBar({
    super.key,
    required this.index,
    required this.items,
    required this.onChanged,
    this.compact = false,
  });

  final int index;
  final List<NavItem> items;
  final ValueChanged<int> onChanged;

  /// Drives the shrink-on-scroll state.
  final bool compact;

  static const double height = 70;
  static const double compactHeight = 58;

  /// Distance from the bottom of the screen to the bottom of the bar.
  static const double bottomInset = 12;

  @override
  State<GlassNavBar> createState() => _GlassNavBarState();
}

class _GlassNavBarState extends State<GlassNavBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    value: 1,
  );

  late int _from = widget.index;

  @override
  void didUpdateWidget(covariant GlassNavBar old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _from = old.index;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final height =
        widget.compact ? GlassNavBar.compactHeight : GlassNavBar.height;
    final r = BorderRadius.circular(Radii.pill);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.compact ? 24 : 16,
        0,
        widget.compact ? 24 : 16,
        GlassNavBar.bottomInset + bottomInset,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
        height: height,
        decoration: BoxDecoration(
          borderRadius: r,
          boxShadow: [
            BoxShadow(
              color: t.navShadow.withValues(alpha: t.navShadow.a * 0.6),
              blurRadius: 44,
              spreadRadius: -8,
              offset: const Offset(0, 18),
            ),
            BoxShadow(
              color: t.navShadow.withValues(alpha: t.navShadow.a * 0.9),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: r,
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: t.navFill,
                borderRadius: r,
                border: Border.all(color: t.navBorder),
              ),
              child: Stack(
                children: [
                  // Inset rim.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Padding(
                        padding: const EdgeInsets.all(1),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(Radii.pill),
                            border: Border.all(color: t.innerRim),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Specular top edge.
                  Positioned(
                    top: 0,
                    left: 40,
                    right: 40,
                    child: IgnorePointer(
                      child: Container(
                        height: 1,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              t.specular.withValues(alpha: 0),
                              t.specular,
                              t.specular.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final itemWidth =
                          constraints.maxWidth / widget.items.length;
                      return AnimatedBuilder(
                        animation: _c,
                        builder: (context, _) => Stack(
                          children: [
                            _indicator(context, itemWidth, r),
                            Row(
                              children: [
                                for (var i = 0; i < widget.items.length; i++)
                                  SizedBox(
                                    width: itemWidth,
                                    child: _NavButton(
                                      item: widget.items[i],
                                      selected: widget.index == i,
                                      compact: widget.compact,
                                      onTap: () => widget.onChanged(i),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _indicator(BuildContext context, double itemWidth, BorderRadius r) {
    final t = context.glass;
    final barHeight = widget.compact
        ? GlassNavBar.compactHeight
        : GlassNavBar.height;

    // easeOutBack overshoots the target, then settles — the "expressive"
    // motion feel without a physics simulation.
    final eased = Curves.easeOutBack.transform(_c.value.clamp(0.0, 1.0));
    final position = ui.lerpDouble(_from, widget.index, eased)!;

    // Bulge mid-flight so the pill looks like it is stretching toward its
    // destination rather than teleporting.
    final bulge = math.sin(math.pi * _c.value.clamp(0.0, 1.0));
    final width = itemWidth * (1 + 0.18 * bulge);
    final left = position * itemWidth + (itemWidth - width) / 2;
    final height = barHeight - 14;

    return Positioned(
      left: left,
      top: barHeight / 2 - height / 2,
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: r,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              t.accentPrimary.withValues(alpha: 0.30),
              t.accentSecondary.withValues(alpha: 0.18),
            ],
          ),
          border: Border.all(color: t.accentPrimary.withValues(alpha: 0.48)),
          boxShadow: [
            BoxShadow(
              color: t.accentPrimary.withValues(alpha: 0.34),
              blurRadius: 24,
              spreadRadius: -4,
            ),
            BoxShadow(
              color: t.accentPrimary.withValues(alpha: 0.14),
              blurRadius: 44,
              spreadRadius: -6,
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: r,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [t.sheen, t.sheen.withValues(alpha: 0)],
                      stops: const [0, 0.7],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final NavItem item;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final showLabel = selected && !compact;

    return Pressable(
      onTap: onTap,
      scale: 0.90,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  selected ? item.activeIcon : item.icon,
                  size: compact ? 21 : 22.5,
                  color: selected ? t.textPrimary : t.textSecondary,
                ),
                if (item.statusDot)
                  Positioned(
                    right: -5,
                    top: -3,
                    child: _StatusDot(selected: selected),
                  ),
              ],
            ),
            ClipRect(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                alignment: Alignment.centerLeft,
                child: AnimatedOpacity(
                  opacity: showLabel ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: showLabel
                      ? Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            item.label,
                            style: context.type.labelLarge?.copyWith(
                              color: t.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              letterSpacing: -0.2,
                            ),
                          ),
                        )
                      : const SizedBox(width: 0, height: 0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slow-breathing dot signalling an active background state.
class _StatusDot extends StatefulWidget {
  const _StatusDot({required this.selected});

  final bool selected;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final v = 0.55 + 0.45 * _c.value;
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: t.success,
            border: Border.all(
              color: t.canvasGradient.first.withValues(alpha: 0.9),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: t.success.withValues(alpha: 0.7 * v),
                blurRadius: 8 * v + 2,
              ),
            ],
          ),
        );
      },
    );
  }
}
