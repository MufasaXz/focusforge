import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show clampDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/local_store.dart';
import '../../shared/widgets/icon_badge.dart';

/// One stop in the first-run sequence: a widget to point at, and the copy.
///
/// The target is a [GlobalKey] rather than a position. The hole is measured
/// from the live [RenderBox] every time the sequence is shown, so a tip cannot
/// drift away from the thing it describes — and a tip whose widget is not on
/// screen is dropped rather than drawn over empty space.
@immutable
class CoachSpot {
  const CoachSpot({
    required this.target,
    required this.icon,
    required this.title,
    required this.body,
    this.minRadius = 44,
    this.padding = 10,
  });

  final GlobalKey target;
  final IconData icon;
  final String title;
  final String body;

  /// The floor for the hole's radius, so a small target such as an icon still
  /// gets a spotlight big enough to read as one.
  final double minRadius;

  /// Breathing room added around the measured widget.
  final double padding;
}

/// First-run spotlight sequence for the dashboard.
///
/// It wraps its child rather than pushing a route, so the dashboard mounts it
/// once and never has to think about it again — the widget reads the
/// `coachmarks.seen` flag itself and renders nothing once the sequence has
/// been dismissed.
///
/// The spotlight is an [OverlayEntry] on the root overlay, not a stack inside
/// the dashboard. That is what lets a tip point at the navigation bar: the bar
/// is a sibling of the tab body, so a hole drawn inside the body could never
/// reach it, and the tip about the Focus tab used to land just off the bottom
/// edge of the screen as a result.
class CoachMarks extends ConsumerStatefulWidget {
  const CoachMarks({super.key, required this.child, required this.spots});

  final Widget child;

  /// The sequence, in order. Built by the caller, because only the dashboard
  /// knows which of its own sections are actually on screen.
  final List<CoachSpot> spots;

  @override
  ConsumerState<CoachMarks> createState() => _CoachMarksState();
}

class _CoachMarksState extends ConsumerState<CoachMarks>
    with SingleTickerProviderStateMixin {
  static const _seenKey = StoreKeys.coachSeen;

  /// Marks the overlay's own coordinate space, so a widget's global position
  /// can be converted into it. The root overlay usually starts at the window's
  /// origin, but "usually" is not a layout guarantee.
  final _overlayKey = GlobalKey(debugLabel: 'coach.overlay');

  late final AnimationController _move = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 1,
  );

  OverlayEntry? _entry;
  bool _checked = false;
  int _index = 0;

  /// The hole at the previous and next stop, so the spotlight glides between
  /// them instead of jumping.
  _Hole? _from;
  _Hole? _to;

  /// The stops that resolved to a real box this time round.
  List<_Step> _steps = const [];

  @override
  void dispose() {
    _removeEntry();
    _move.dispose();
    super.dispose();
  }

  /// Runs once, from the first build. The flag is read through the container
  /// rather than a [Consumer] so the dashboard can drop this in without making
  /// its own widget tree Riverpod-aware.
  void _checkFirstRun() {
    if (_checked) return;
    _checked = true;
    // Only the absence of the key counts. A stored `false` means the user has
    // already been through it — the flag is written once and never reset.
    if (ref.read(localStoreProvider).getBool(_seenKey) != null) return;
    if (widget.spots.isEmpty) return;

    // After the frame: the targets have to have been laid out before they can
    // be measured, and on the first build they have not.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _show();
    });
  }

  /// Inserts the overlay, then measures once it has been laid out.
  ///
  /// Two passes rather than one: the targets are measured in the overlay's own
  /// coordinate space, and until the entry has been built there is no space to
  /// measure them against.
  void _show() {
    _insertEntry();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measure();
    });
  }

  /// Resolves every spot to a real box and starts the sequence.
  void _measure() {
    final steps = <_Step>[];
    for (final spot in widget.spots) {
      final rect = _rectOf(spot.target);
      // A target that is not mounted, or that has no size yet, has nothing to
      // point at. Dropping the tip is the honest outcome: a spotlight over
      // empty space tells the user to look at something that is not there.
      if (rect == null || rect.isEmpty) continue;
      steps.add(
        _Step(
          spot: spot,
          hole: _Hole(
            center: rect.center,
            radius: math.max(
              spot.minRadius,
              rect.longestSide / 2 + spot.padding,
            ),
          ),
        ),
      );
    }

    if (steps.isEmpty) {
      _removeEntry();
      return;
    }

    setState(() {
      _steps = steps;
      _index = 0;
      _from = steps.first.hole;
      _to = steps.first.hole;
    });
    _entry?.markNeedsBuild();
  }

  /// The widget's box in the overlay's coordinate space.
  Rect? _rectOf(GlobalKey key) {
    final target = key.currentContext;
    final overlay = _overlayKey.currentContext;
    if (target == null || overlay == null) return null;

    final box = target.findRenderObject();
    final space = overlay.findRenderObject();
    if (box is! RenderBox || space is! RenderBox) return null;
    if (!box.hasSize || !box.attached) return null;

    final origin = box.localToGlobal(Offset.zero, ancestor: space);
    return origin & box.size;
  }

  void _insertEntry() {
    if (_entry != null) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final entry = OverlayEntry(builder: _buildOverlay);
    _entry = entry;
    overlay.insert(entry);
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
  }

  _Hole get _current {
    final from = _from;
    final to = _to;
    if (from == null || to == null) {
      return const _Hole(center: Offset.zero, radius: 0);
    }
    final t = Curves.easeOutCubic.transform(_move.value);
    return _Hole(
      center: Offset.lerp(from.center, to.center, t)!,
      radius: from.radius + (to.radius - from.radius) * t,
    );
  }

  void _go(int index) {
    if (index >= _steps.length) {
      _dismiss();
      return;
    }
    setState(() {
      _from = _current;
      _to = _steps[index].hole;
      _index = index;
    });
    if (MediaQuery.disableAnimationsOf(context)) {
      _move.value = 1;
    } else {
      _move.forward(from: 0);
    }
    _entry?.markNeedsBuild();
  }

  void _dismiss() {
    unawaited(ref.read(localStoreProvider).setBool(_seenKey, true));
    _removeEntry();
    if (mounted) setState(() => _steps = const []);
  }

  @override
  Widget build(BuildContext context) {
    _checkFirstRun();
    return widget.child;
  }

  Widget _buildOverlay(BuildContext context) {
    final step = _index < _steps.length ? _steps[_index] : null;

    // The stack is built even before the first measurement lands, because the
    // measurement needs it: the holes are expressed in the overlay's own
    // coordinate space, and that space does not exist until this subtree has
    // been laid out. `StackFit.expand` is what makes it fill the overlay
    // rather than shrink to nothing while it has no visible children.
    return Stack(
      key: _overlayKey,
      fit: StackFit.expand,
      children: [
        if (step != null)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _move,
              builder: (context, _) {
                final hole = _current;
                final padding = MediaQuery.paddingOf(context);
                final insets = EdgeInsets.fromLTRB(
                  math.max(Gap.xl, padding.left + Gap.sm),
                  math.max(Gap.lg, padding.top + Gap.sm),
                  math.max(Gap.xl, padding.right + Gap.sm),
                  math.max(Gap.lg, padding.bottom + Gap.sm),
                );
                return Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _go(_index + 1),
                        child: CustomPaint(
                          painter: _SpotlightPainter(
                            center: hole.center,
                            radius: hole.radius,
                            progress: (_index + 1) / _steps.length,
                            scrim: Colors.black.withValues(alpha: 0.68),
                            ring: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomSingleChildLayout(
                        delegate: _BubbleLayout(
                          center: hole.center,
                          radius: hole.radius,
                          gap: Gap.lg,
                          insets: insets,
                        ),
                        child: _Bubble(
                          spot: step.spot,
                          index: _index,
                          total: _steps.length,
                          onNext: () => _go(_index + 1),
                          onDismiss: _dismiss,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}

/// One resolved stop: the copy plus the measured hole.
@immutable
class _Step {
  const _Step({required this.spot, required this.hole});

  final CoachSpot spot;
  final _Hole hole;
}

@immutable
class _Hole {
  const _Hole({required this.center, required this.radius});

  final Offset center;
  final double radius;
}

/// Places the bubble on the far side of the spotlight hole and keeps it inside
/// the safe area.
///
/// The bubble's height is only known at layout time, so the position cannot be
/// expressed as a [Positioned] offset: a hole near the middle of the screen
/// would push a tall bubble past the bottom edge, and one near an edge would
/// push it off the opposite side. [CustomSingleChildLayout] measures the
/// bubble first and clamps it into the safe area; when the preferred side has
/// no room, the bubble flips to the other side before the clamp is applied.
class _BubbleLayout extends SingleChildLayoutDelegate {
  const _BubbleLayout({
    required this.center,
    required this.radius,
    required this.gap,
    required this.insets,
  });

  final Offset center;
  final double radius;
  final double gap;
  final EdgeInsets insets;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      maxWidth: math.max(0.0, constraints.maxWidth - insets.horizontal),
      maxHeight: math.max(0.0, constraints.maxHeight - insets.vertical),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final safe = Rect.fromLTRB(
      insets.left,
      insets.top,
      size.width - insets.right,
      size.height - insets.bottom,
    );

    final preferBelow = center.dy < size.height / 2;
    final below = center.dy + radius + gap;
    final above = center.dy - radius - gap - childSize.height;

    double y;
    if (preferBelow) {
      y = below + childSize.height <= safe.bottom ? below : above;
    } else {
      y = above >= safe.top ? above : below;
    }
    y = clampDouble(
      y,
      safe.top,
      math.max(safe.top, safe.bottom - childSize.height),
    );

    final x = clampDouble(
      (size.width - childSize.width) / 2,
      safe.left,
      math.max(safe.left, safe.right - childSize.width),
    );

    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_BubbleLayout old) =>
      old.center != center ||
      old.radius != radius ||
      old.gap != gap ||
      old.insets != insets;
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.spot,
    required this.index,
    required this.total,
    required this.onNext,
    required this.onDismiss,
  });

  final CoachSpot spot;
  final int index;
  final int total;
  final VoidCallback onNext;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final last = index == total - 1;

    return Material(
      // The overlay is outside the page's Material ancestor, so the card needs
      // its own — without it the text has no surface to be drawn on.
      color: Colors.transparent,
      child: Card.outlined(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: BorderSide(color: cs.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconBadge(
                    icon: spot.icon,
                    color: cs.primary,
                    size: 34,
                    radius: Radii.tile,
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Text(
                      spot.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: onDismiss,
                    tooltip: 'Dismiss tips',
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: Gap.md),
              Text(
                spot.body,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: Gap.lg),
              Row(
                children: [
                  for (var i = 0; i < total; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 5),
                      child: Container(
                        width: i == index ? 16 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == index
                              ? cs.primary
                              : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                      ),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: onNext,
                    child: Text(last ? 'Got it' : 'Next'),
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

/// Darkens the screen except for a circular hole, then draws the progress
/// ring around it. The scrim is a plain translucent black — the spotlight is
/// the focus, so no blur is layered behind it.
class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({
    required this.center,
    required this.radius,
    required this.progress,
    required this.scrim,
    required this.ring,
  });

  final Offset center;
  final double radius;
  final double progress;
  final Color scrim;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;

    // One layer, painted twice: the scrim, then a cleared circle punched
    // through it. Drawing four rectangles around the hole instead would leave
    // seams on fractional pixels.
    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(bounds, Paint()..color = scrim);
    canvas.drawCircle(center, radius, Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = ring.withValues(alpha: 0.45),
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius + 7),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = ring,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.center != center ||
      old.radius != radius ||
      old.progress != progress ||
      old.scrim != scrim ||
      old.ring != ring;
}
