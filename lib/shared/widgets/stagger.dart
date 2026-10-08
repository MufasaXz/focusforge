import 'dart:async';

import 'package:flutter/material.dart';

/// Staggered entrance: fades up after a per-index delay.
///
/// Runs once when visible, with a fixed travel distance for every item.
/// Reduced motion reveals content immediately, including during a delay.
class Stagger extends StatefulWidget {
  const Stagger({
    super.key,
    required this.index,
    required this.child,
    this.step = const Duration(milliseconds: 40),
    this.maxDelay = const Duration(milliseconds: 240),
    this.duration = const Duration(milliseconds: 320),
    this.offset = 12,
  });

  final int index;
  final Widget child;
  final Duration step;
  final Duration maxDelay;
  final Duration duration;
  final double offset;

  @override
  State<Stagger> createState() => _StaggerState();
}

class _StaggerState extends State<Stagger> {
  bool _shown = false;
  Timer? _delay;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_shown) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _delay?.cancel();
      _shown = true;
      return;
    }
    // Offstage branches must not spend their entrance delay before the tab
    // is visible. Cancelling also makes disposal safe during navigation.
    if (!TickerMode.valuesOf(context).enabled) {
      _delay?.cancel();
      _delay = null;
      return;
    }
    if (_delay != null) return;
    final delay = widget.step * widget.index;
    final clamped = delay > widget.maxDelay ? widget.maxDelay : delay;
    _delay = Timer(clamped, () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : widget.duration;
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: duration,
      curve: Curves.easeOutCubic,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: _shown ? 0 : widget.offset),
        duration: duration,
        curve: Curves.easeOutCubic,
        child: widget.child,
        builder: (context, offset, child) =>
            Transform.translate(offset: Offset(0, offset), child: child),
      ),
    );
  }
}
