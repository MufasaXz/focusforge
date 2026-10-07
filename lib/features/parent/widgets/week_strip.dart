import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/models/parent.dart';
import '../../../core/utils/format.dart';

/// The child's week, as seven bars.
///
/// The bars are the child's own week — the same seven days their dashboard
/// draws — so a parent reads the shape of the week rather than one number that
/// happens to be today's. When the child's build has not published the bars (a
/// summary written by an older version), nothing is drawn: seven empty bars
/// would read as a week of nothing, which is a different claim.
class WeekStrip extends StatelessWidget {
  const WeekStrip({super.key, required this.progress, this.height = 44});

  final ChildProgress progress;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final days = progress.weekDays;
    if (days.length < 7) return const SizedBox.shrink();

    final peak = days.fold<int>(0, (max, m) => m > max ? m : max);
    final labels = _weekdayLetters();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'This week',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            Text(
              progress.weekMinutes <= 0
                  ? 'Nothing yet'
                  : '${formatHoursShort(progress.weekMinutes / 60)} · '
                        '${progress.weekSessions == 1 ? '1 session' : '${progress.weekSessions} sessions'}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.sm),
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 7; i++) ...[
                if (i > 0) const SizedBox(width: Gap.sm),
                Expanded(
                  child: Semantics(
                    label: '${_weekdayNames[i]}, ${formatMinutes(days[i])}',
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: FractionallySizedBox(
                            alignment: Alignment.bottomCenter,
                            // A day with time on it keeps a visible stub even
                            // against a much taller day, so "a little" never
                            // reads as "none".
                            heightFactor: days[i] <= 0 || peak <= 0
                                ? 0.06
                                : (0.18 + 0.82 * (days[i] / peak)).clamp(
                                    0.18,
                                    1.0,
                                  ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: days[i] <= 0
                                    ? cs.surfaceContainerHighest
                                    : cs.tertiary,
                                borderRadius: BorderRadius.circular(Radii.pill),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          labels[i],
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 9.5,
                            color: i == 6 ? cs.onSurface : cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// The last seven weekday initials, oldest first, ending on today.
List<String> _weekdayLetters() {
  const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  final today = DateTime.now();
  return [
    for (var i = 6; i >= 0; i--)
      letters[DateTime(today.year, today.month, today.day - i).weekday - 1],
  ];
}
