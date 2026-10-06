import 'package:flutter/material.dart';

import '../../../app/theme/color_tokens.dart';
import '../../../app/theme/glass_theme.dart';
import '../../../core/data/mock_data.dart';
import '../../../core/utils/format.dart';

/// Horizontal stacked bar showing how today's focus split across subjects.
class SubjectBreakdown extends StatefulWidget {
  const SubjectBreakdown({super.key, required this.subjects});

  final List<Subject> subjects;

  @override
  State<SubjectBreakdown> createState() => _SubjectBreakdownState();
}

class _SubjectBreakdownState extends State<SubjectBreakdown>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.subjects.fold<int>(0, (a, s) => a + s.minutes);
    final totalSafe = total == 0 ? 1 : total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) => ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  for (var i = 0; i < widget.subjects.length; i++)
                    Expanded(
                      flex: (widget.subjects[i].minutes /
                              totalSafe *
                              1000 *
                              Curves.easeOutCubic.transform(
                                (_c.value - i * 0.08).clamp(0.0, 1.0) /
                                    (1 - i * 0.08),
                              ))
                          .round()
                          .clamp(1, 1000),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: widget.subjects[i].color,
                            boxShadow: [
                              BoxShadow(
                                color: widget.subjects[i]
                                    .color
                                    .withValues(alpha: 0.45),
                                blurRadius: 10,
                                spreadRadius: -3,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: Gap.lg),
        Wrap(
          spacing: Gap.lg,
          runSpacing: Gap.md,
          children: [
            for (final s in widget.subjects)
              _Legend(
                color: s.color,
                icon: s.icon,
                label: s.name,
                value: formatMinutes(s.minutes),
                percent: s.minutes / totalSafe,
              ),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.color,
    required this.icon,
    required this.label,
    required this.value,
    required this.percent,
  });

  final Color color;
  final IconData icon;
  final String label;
  final String value;
  final double percent;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: context.type.labelMedium?.copyWith(color: t.textSecondary),
        ),
        const SizedBox(width: 5),
        Text(
          value,
          style: context.type.labelMedium?.copyWith(
            color: t.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
