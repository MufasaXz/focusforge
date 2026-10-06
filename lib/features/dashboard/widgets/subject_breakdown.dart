import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/data/seed.dart';
import '../../../core/utils/format.dart';

/// Horizontal stacked bar showing how today's focus split across subjects.
///
/// The bar itself is one spoken sentence — "Subject breakdown. Math 1 hour 5
/// minutes, Physics 52 minutes…" — so the chart is legible to a screen reader
/// without walking the legend item by item.
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
    final cs = Theme.of(context).colorScheme;

    if (widget.subjects.isEmpty) {
      return Row(
        children: [
          Icon(Icons.donut_large_rounded, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              'No subjects yet — add one from the Focus tab.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      );
    }

    final total = widget.subjects.fold<int>(0, (a, s) => a + s.minutes);
    final totalSafe = total == 0 ? 1 : total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: _summary(widget.subjects),
          child: ExcludeSemantics(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => ClipRRect(
                borderRadius: BorderRadius.circular(Radii.pill),
                child: SizedBox(
                  height: 14,
                  child: Row(
                    children: [
                      for (var i = 0; i < widget.subjects.length; i++)
                        Expanded(
                          flex:
                              (widget.subjects[i].minutes /
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
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
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
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(width: 5),
        Text(
          value,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

String _spokenMinutes(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  final parts = <String>[
    if (h > 0) '$h ${h == 1 ? 'hour' : 'hours'}',
    if (m > 0) '$m ${m == 1 ? 'minute' : 'minutes'}',
  ];
  return parts.isEmpty ? 'no time' : parts.join(' ');
}

String _summary(List<Subject> subjects) {
  final parts = [
    for (final s in subjects) '${s.name} ${_spokenMinutes(s.minutesToday)}',
  ];
  return 'Subject breakdown. ${parts.join(', ')}.';
}
