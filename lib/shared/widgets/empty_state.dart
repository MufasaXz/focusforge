import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import 'glass_surface.dart';

/// Centred empty state: a haloed icon, a headline, a supporting line and an
/// optional call to action.
///
/// The halo is drawn instead of shipped as an asset so it inherits whatever
/// accent the active theme uses — a bitmap would need a second file for light
/// mode, and a stock illustration would be the only image in an otherwise
/// purely geometric interface.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = cs.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Gap.xl,
        vertical: Gap.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 168,
            height: 168,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: _HaloPainter(color: accent)),
                ),
                GlassIconBadge(
                  icon: icon,
                  color: accent,
                  size: 68,
                  radius: 22,
                  glow: 0.55,
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.xl),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Gap.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
          if (action != null) ...[const SizedBox(height: Gap.xl), action!],
        ],
      ),
    );
  }
}

/// Soft disc plus three fading rings. Deliberately quiet: an empty state should
/// explain the absence of content, not compete with it once it arrives.
class _HaloPainter extends CustomPainter {
  const _HaloPainter({required this.color});

  final Color color;

  static const _rings = [0.42, 0.62, 0.84];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: 0.16), color.withValues(alpha: 0)],
          stops: const [0, 0.9],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    for (var i = 0; i < _rings.length; i++) {
      canvas.drawCircle(
        center,
        radius * _rings[i],
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color.withValues(alpha: 0.16 - i * 0.045),
      );
    }
  }

  @override
  bool shouldRepaint(_HaloPainter old) => old.color != color;
}
