import 'package:flutter/material.dart';

/// Staggered entrance: fades up after a per-index delay.
///
/// Staggering is what makes a screen feel composed rather than dumped — the
/// eye is walked down the page instead of being hit with everything at once.
/// Kept short (≈55ms per item, 260ms travel) so it never blocks interaction.
class Stagger extends StatefulWidget {
  const Stagger({
    super.key,
    required this.index,
    required this.child,
    this.step = const Duration(milliseconds: 55),
    this.maxDelay = const Duration(milliseconds: 420),
    this.duration = const Duration(milliseconds: 460),
    this.offset = 18,
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

  @override
  void initState() {
    super.initState();
    final delay = widget.step * widget.index;
    final clamped = delay > widget.maxDelay ? widget.maxDelay : delay;
    Future<void>.delayed(clamped, () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: _shown ? Offset.zero : Offset(0, widget.offset / 100),
        duration: widget.duration,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
