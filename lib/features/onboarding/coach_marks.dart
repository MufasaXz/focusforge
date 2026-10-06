import '../../app/theme/app_theme.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../shared/widgets/glass_surface.dart';

/// First-run spotlight sequence for the dashboard.
///
/// Three hints, in the order a new user needs them: what the progress ring is,
/// how to start a session, and what the streak badge rewards. It wraps its
/// child rather than pushing a route, so the dashboard mounts it once and
/// never has to think about it again — the widget reads the `coachmarks.seen`
/// flag itself and renders nothing once the sequence has been dismissed.
///
/// The spotlight positions are expressed as alignments, not measured from
/// widget keys. That is a deliberate trade: it costs a little precision on
/// unusual viewports, and it buys a dashboard that needs no instrumentation
/// and no rebuild when its layout changes.
///
/// Mount it around the dashboard body, inside a widget that gives it bounded
/// constraints — a `Scaffold` body or a `Stack`, not a scroll view.
class CoachMarks extends StatefulWidget {
  const CoachMarks({super.key, required this.child});

  final Widget child;

  @override
  State<CoachMarks> createState() => _CoachMarksState();
}

class _CoachMarksState extends State<CoachMarks>
    with SingleTickerProviderStateMixin {
  static const _seenKey = 'coachmarks.seen';

  static const _spots = <_Spot>[
    _Spot(
      alignment: Alignment(-0.05, -0.32),
      radius: 118,
      icon: Icons.donut_large_rounded,
      title: 'Your daily progress',
      body:
          'This ring fills as you focus. Start a session and it starts '
          'moving.',
    ),
    _Spot(
      alignment: Alignment(0.25, 0.94),
      radius: 46,
      icon: Icons.timer_rounded,
      title: 'Start a session',
      body: 'Tap the Focus tab to begin your first Pomodoro.',
    ),
    _Spot(
      alignment: Alignment(0.72, -0.87),
      radius: 46,
      icon: Icons.local_fire_department_rounded,
      title: 'Build your streak',
      body: 'Study every day and the flame keeps growing.',
    ),
  ];

  late final AnimationController _move = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 1,
  );

  bool _visible = false;
  bool _checked = false;
  int _index = 0;
  _Spot _from = _spots.first;
  _Spot _to = _spots.first;

  /// Runs once, from the first build. The flag is read through a [Consumer]
  /// rather than a container lookup so this stays a plain [StatefulWidget] —
  /// the dashboard can drop it in without making its own widget tree
  /// Riverpod-aware.
  void _checkFirstRun(WidgetRef ref) {
    if (_checked) return;
    _checked = true;
    // Only the absence of the key counts. A stored `false` means the user has
    // already been through it — the flag is written once and never reset.
    if (ref.read(localStoreProvider).getBool(_seenKey) != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _move.dispose();
    super.dispose();
  }

  /// The spot currently on screen, interpolated between the last two stops so
  /// the hole glides instead of jumping.
  _Spot get _current {
    final t = Curves.easeOutCubic.transform(_move.value);
    return _Spot(
      alignment: Alignment(
        lerpDouble(_from.alignment.x, _to.alignment.x, t)!,
        lerpDouble(_from.alignment.y, _to.alignment.y, t)!,
      ),
      radius: lerpDouble(_from.radius, _to.radius, t)!,
      icon: _to.icon,
      title: _to.title,
      body: _to.body,
    );
  }

  void _go(WidgetRef ref, int index) {
    if (index >= _spots.length) {
      _dismiss(ref);
      return;
    }
    setState(() {
      _from = _current;
      _to = _spots[index];
      _index = index;
    });
    if (MediaQuery.disableAnimationsOf(context)) {
      _move.value = 1;
    } else {
      _move.forward(from: 0);
    }
  }

  void _dismiss(WidgetRef ref) {
    unawaited(ref.read(localStoreProvider).setBool(_seenKey, true));
    setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        _checkFirstRun(ref);
        return Stack(
          children: [
            widget.child,
            if (_visible)
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    return AnimatedBuilder(
                      animation: _move,
                      builder: (context, _) {
                        final spot = _current;
                        final center = spot.alignment.alongSize(size);
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _go(ref, _index + 1),
                                child: CustomPaint(
                                  painter: _SpotlightPainter(
                                    center: center,
                                    radius: spot.radius,
                                    progress: (_index + 1) / _spots.length,
                                    scrim: Colors.black.withValues(alpha: 0.68),
                                    ring: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: Gap.xl,
                              right: Gap.xl,
                              top: center.dy < size.height / 2
                                  ? center.dy + spot.radius + Gap.lg
                                  : null,
                              bottom: center.dy < size.height / 2
                                  ? null
                                  : size.height -
                                        center.dy +
                                        spot.radius +
                                        Gap.lg,
                              child: _Bubble(
                                spot: spot,
                                index: _index,
                                total: _spots.length,
                                onNext: () => _go(ref, _index + 1),
                                onDismiss: () => _dismiss(ref),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One stop in the sequence. [alignment] and [radius] describe the hole;
/// everything else is the bubble's copy.
class _Spot {
  const _Spot({
    required this.alignment,
    required this.radius,
    required this.icon,
    required this.title,
    required this.body,
  });

  final Alignment alignment;
  final double radius;
  final IconData icon;
  final String title;
  final String body;
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.spot,
    required this.index,
    required this.total,
    required this.onNext,
    required this.onDismiss,
  });

  final _Spot spot;
  final int index;
  final int total;
  final VoidCallback onNext;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final last = index == total - 1;

    return GlassPanel(
      level: 2,
      radius: Radii.card,
      blur: 20.0,
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              GlassIconBadge(
                icon: spot.icon,
                color: cs.primary,
                size: 34,
                radius: Radii.tile,
                glow: 0.5,
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Text(spot.title, style: Theme.of(context).textTheme.titleMedium),
              ),
              Pressable(
                onTap: onDismiss,
                child: Semantics(
                  button: true,
                  label: 'Dismiss tips',
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          Text(
            spot.body,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
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
                      color: i == index ? cs.primary : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                  ),
                ),
              const Spacer(),
              GlassPill(
                accent: cs.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.lg,
                  vertical: Gap.sm,
                ),
                onTap: onNext,
                child: Text(
                  last ? 'Got it' : 'Next',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: cs.primary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Darkens the screen except for a circular hole, then draws the progress
/// ring around it.
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
