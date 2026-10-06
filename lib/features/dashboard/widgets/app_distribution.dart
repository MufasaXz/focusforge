import 'package:flutter/material.dart';

import '../../../app/theme/color_tokens.dart';
import '../../../app/theme/glass_theme.dart';
import '../../../core/data/mock_data.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/glass_surface.dart';
import '../../../shared/widgets/glass_toggle.dart';

/// Per-app usage rows with a shield toggle.
class AppDistribution extends StatefulWidget {
  const AppDistribution({super.key, required this.apps});

  final List<TrackedApp> apps;

  @override
  State<AppDistribution> createState() => _AppDistributionState();
}

class _AppDistributionState extends State<AppDistribution> {
  late final List<bool> _shielded =
      widget.apps.map((a) => a.shielded).toList();

  @override
  Widget build(BuildContext context) {
    final t = context.glass;

    return Column(
      children: [
        for (var i = 0; i < widget.apps.length; i++) ...[
          if (i > 0) Divider(color: t.hairline, height: Gap.xl),
          _Row(
            app: widget.apps[i],
            shielded: _shielded[i],
            onToggle: (v) => setState(() => _shielded[i] = v),
          ),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.app,
    required this.shielded,
    required this.onToggle,
  });

  final TrackedApp app;
  final bool shielded;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final over = app.minutes > app.limit;

    return Row(
      children: [
        GlassIconBadge(icon: app.icon, color: app.color, glow: shielded ? 0.6 : 0),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      app.name,
                      style: context.type.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (shielded) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: t.success,
                        boxShadow: [
                          BoxShadow(
                            color: t.success.withValues(alpha: 0.7),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    formatMinutes(app.minutes),
                    style: context.type.labelMedium?.copyWith(
                      color: over ? t.danger : t.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              GlassProgressBar(
                value: app.ratio,
                color: over ? t.danger : app.color,
              ),
              const SizedBox(height: 5),
              Text(
                over
                    ? '${formatMinutes(app.minutes - app.limit)} over limit'
                    : 'Limit ${formatMinutes(app.limit)}',
                style: context.type.labelSmall?.copyWith(
                  color: over ? t.danger : t.textTertiary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: Gap.md),
        GlassToggle(value: shielded, onChanged: onToggle, accent: app.color),
      ],
    );
  }
}
