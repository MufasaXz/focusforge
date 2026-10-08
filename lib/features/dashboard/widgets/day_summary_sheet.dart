import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/models/study.dart';
import '../../../core/providers/study_providers.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../../../shared/widgets/sheet_chrome.dart';

/// What one day actually consisted of.
///
/// Opened by tapping a bar in the tracker. The chart can say a day held three
/// hours; only this can say the three hours were chemistry and nothing else,
/// which is the fact a study log is kept for.
Future<void> showDaySummarySheet(BuildContext context, DateTime day) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => DaySummarySheet(day: day),
  );
}

class DaySummarySheet extends ConsumerWidget {
  const DaySummarySheet({super.key, required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final summary = ref.watch(daySummaryProvider(day));
    final sessions = ref.watch(daySessionsProvider(day));
    final subjects = {for (final s in ref.watch(subjectsProvider)) s.id: s};
    final isToday = _isToday(day);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SheetSurface(
        padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.md, Gap.xl, 0),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SheetHandle(),
                const SizedBox(height: Gap.xl),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isToday
                                ? 'Today'
                                : formatDate(day).split(',').first,
                            style: tt.titleLarge,
                          ),
                          const SizedBox(height: Gap.xs),
                          Text(
                            formatDate(day),
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Gap.sm),
                    SheetCloseButton(onTap: () => Navigator.of(context).pop()),
                  ],
                ),
                const SizedBox(height: Gap.xl),
                if (summary.isEmpty)
                  _NothingStudied(day: day)
                else ...[
                  Wrap(
                    spacing: Gap.md,
                    runSpacing: Gap.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        formatMinutes(summary.totalMinutes),
                        style: tt.headlineMedium?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        summary.sessions == 1
                            ? '1 completed session'
                            : '${summary.sessions} completed sessions',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Gap.xl),
                  for (final slice in summary.slices) ...[
                    _SliceRow(slice: slice, total: summary.totalMinutes),
                    const SizedBox(height: Gap.lg),
                  ],
                  const SizedBox(height: Gap.sm),
                  const Divider(),
                  const SizedBox(height: Gap.lg),
                  Semantics(
                    header: true,
                    child: Text('Sessions', style: tt.titleSmall),
                  ),
                  const SizedBox(height: Gap.sm),
                  for (var i = 0; i < sessions.length; i++)
                    _SessionRow(
                      session: sessions[i],
                      subject: subjects[sessions[i].subjectId],
                    ),
                ],
                const SizedBox(height: Gap.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Start times and durations from the log. End times are not inferred because
/// a paused block may span much longer than its focused minutes.
class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, required this.subject});

  final FocusSession session;
  final Subject? subject;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final name =
        subject?.name ?? (session.label.isEmpty ? 'Unassigned' : session.label);
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(session.startedAt),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final color = subject == null
        ? cs.primary
        : harmonize(subject!.color, cs.primary);

    return Semantics(
      label:
          '$name, started at $time, ${formatMinutes(session.minutes)} focused',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.md),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 18, color: color),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: tt.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: Gap.xs),
                  Text(
                    time,
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Gap.md),
            Text(
              formatMinutes(session.minutes),
              style: tt.titleSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One subject's share of the day.
class _SliceRow extends StatelessWidget {
  const _SliceRow({required this.slice, required this.total});

  final DaySubjectSlice slice;
  final int total;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final accent = harmonize(slice.color, cs.primary);
    final share = total <= 0 ? 0.0 : (slice.minutes / total).clamp(0.0, 1.0);

    return Semantics(
      label:
          '${slice.name}, ${formatMinutes(slice.minutes)}, '
          '${(share * 100).round()} percent of the day',
      child: ExcludeSemantics(
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          slice.name,
                          style: tt.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: Gap.sm),
                      Text(
                        formatMinutes(slice.minutes),
                        style: tt.labelMedium?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: Gap.sm),
                      Text(
                        '${(share * 100).round()}%',
                        textAlign: TextAlign.end,
                        style: tt.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Gap.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.pill),
                    child: LinearProgressIndicator(
                      value: share,
                      color: accent,
                      backgroundColor: cs.surfaceContainerHighest,
                      minHeight: 5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A day with nothing on it.
///
/// Worded as an observation rather than a reproach: an empty day in the log is
/// a rest day or a day the app was not used, and neither is a failure the
/// screen should be commenting on.
class _NothingStudied extends StatelessWidget {
  const _NothingStudied({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      children: [
        IconBadge(
          icon: Icons.event_busy_rounded,
          color: cs.onSurfaceVariant,
          size: 52,
          radius: 17,
        ),
        const SizedBox(height: Gap.lg),
        Text('No focus logged', style: tt.titleSmall),
        const SizedBox(height: Gap.sm),
        Text(
          'Nothing was finished on this day. Sessions count towards a day '
          'when the block they belong to runs to the end.',
          textAlign: TextAlign.center,
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: Gap.sm),
      ],
    );
  }
}

bool _isToday(DateTime day) {
  final now = DateTime.now();
  return day.year == now.year && day.month == now.month && day.day == now.day;
}
