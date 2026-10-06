import 'package:flutter/material.dart';
import '../../app/theme/app_theme.dart';


/// Shimmering placeholder block.
///
/// Hand-rolled rather than taken from the `shimmer` package: the sweep is one
/// [ShaderMask] over a single animated gradient, which is less machinery than a
/// dependency and keeps the highlight inside the app's own token family instead
/// of importing a second set of greys.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height = 14, this.radius = 8});

  /// Null fills the incoming width, so a bare [Skeleton] inside a column or row
  /// spans the line it is standing in for.
  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Honour the platform "reduce motion" switch — a static tint still says
    // "content is coming" without the movement.
    if (MediaQuery.disableAnimationsOf(context)) {
      _sweep.stop();
    } else if (!_sweep.isAnimating) {
      _sweep.repeat();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(widget.radius);
    final base = cs.onSurface.withValues(alpha: 0.07);
    final highlight = Color.lerp(
      cs.onSurface,
      cs.primary,
      0.55,
    )!.withValues(alpha: 0.16);

    if (MediaQuery.disableAnimationsOf(context)) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(color: base, borderRadius: radius),
      );
    }

    return AnimatedBuilder(
      animation: _sweep,
      // The white child carries the shape; `srcIn` throws its colour away and
      // keeps only its alpha, so the gradient's own translucent colours survive
      // intact. `srcOver` would paint a rectangle over the background and
      // `srcATop` would blend the tint into the white and come out opaque.
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (rect) => LinearGradient(
          colors: [base, highlight, base],
          stops: const [0.35, 0.5, 0.65],
          transform: _SweepTransform(_sweep.value),
        ).createShader(rect),
        child: child,
      ),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(color: Colors.white, borderRadius: radius),
      ),
    );
  }
}

/// Slides the gradient across the box; the box itself never moves.
class _SweepTransform extends GradientTransform {
  const _SweepTransform(this.progress);

  final double progress;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (progress * 2 - 1), 0, 0);
}

/// Card-sized skeleton — stands in for a whole [AppSection].
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.height = 160, this.radius = Radii.card});

  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) =>
      Skeleton(height: height, radius: radius);
}

/// List placeholder: a leading tile and two lines per row, at the rhythm of the
/// real rows so the swap to content does not shift the page.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 3, this.itemHeight = 64});

  final int count;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    final avatar = (itemHeight - Gap.lg * 2).clamp(28.0, 44.0);

    return Column(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(height: Gap.md),
          SizedBox(
            height: itemHeight,
            child: Row(
              children: [
                Skeleton(width: avatar, height: avatar, radius: Radii.tile),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Skeleton(height: 12, radius: 6),
                      const SizedBox(height: Gap.sm),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: 0.55,
                        child: const Skeleton(height: 10, radius: 5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
