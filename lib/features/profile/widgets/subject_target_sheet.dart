import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/app_shell.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/models/study.dart';
import '../../../core/providers/study_providers.dart';
import '../../../shared/widgets/icon_badge.dart';

/// Opens the sheet that edits one subject's weekly target.
Future<void> showSubjectTargetSheet(BuildContext context, Subject subject) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    // The sheet is taller than the default 9/16 cap, and it must be able to
    // scroll rather than overflow on a short viewport.
    isScrollControlled: true,
    builder: (_) => _SubjectTargetSheet(subject: subject),
  );
}

/// `5h` for whole hours, `5.5h` otherwise — a raw double would render `5.0h`.
String _hours(double h) =>
    h == h.roundToDouble() ? '${h.round()}h' : '${h.toStringAsFixed(1)}h';

class _SubjectTargetSheet extends ConsumerStatefulWidget {
  const _SubjectTargetSheet({required this.subject});

  final Subject subject;

  @override
  ConsumerState<_SubjectTargetSheet> createState() =>
      _SubjectTargetSheetState();
}

class _SubjectTargetSheetState extends ConsumerState<_SubjectTargetSheet> {
  /// Half-hour steps between one and twenty hours a week.
  static const _min = 1.0;
  static const _max = 20.0;
  static const _step = 0.5;
  static const _quickTargets = [3.0, 5.0, 8.0, 10.0, 15.0];

  late double _target = widget.subject.weekTarget.clamp(_min, _max).toDouble();

  Future<void> _save() async {
    await ref
        .read(subjectsProvider.notifier)
        .setWeeklyTarget(widget.subject.id, _target);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = widget.subject;
    final met = _target > 0 && s.weekDone >= _target;
    // Measured against the pending target, not the saved one, so the number
    // tracks the slider instead of jumping only after a save.
    final percent = ((s.weekDone / _target).clamp(0.0, 1.0) * 100).round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Gap.lg,
        Gap.lg,
        Gap.lg,
        // Clear the floating nav bar, which sits above this sheet.
        kNavBarClearance,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.hero),
        // One of the three sanctioned blur sites: a modal sheet floats over
        // the page it was opened from.
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: const EdgeInsets.all(Gap.lg),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(Radii.hero),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant,
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                    ),
                  ),
                  const SizedBox(height: Gap.lg),
                  Row(
                    children: [
                      IconBadge(
                        icon: s.icon,
                        color: s.color,
                        size: 42,
                        radius: 13,
                      ),
                      const SizedBox(width: Gap.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              s.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              '${_hours(s.weekDone)} done · $percent% of target',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Gap.xl),
                  Row(
                    children: [
                      Text(
                        'Weekly target',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const Spacer(),
                      Text(
                        _hours(_target),
                        style: Theme.of(
                          context,
                        ).textTheme.titleSmall?.copyWith(color: s.color),
                      ),
                    ],
                  ),
                  Slider(
                    value: _target,
                    min: _min,
                    max: _max,
                    divisions: ((_max - _min) / _step).round(),
                    activeColor: s.color,
                    inactiveColor: cs.surfaceContainerHighest,
                    label: _hours(_target),
                    onChanged: (v) => setState(() => _target = v),
                  ),
                  Row(
                    children: [
                      Text('1h', style: Theme.of(context).textTheme.labelSmall),
                      const Spacer(),
                      Text(
                        '20h',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: Gap.md),
                  Wrap(
                    spacing: Gap.sm,
                    runSpacing: Gap.sm,
                    children: [
                      for (final hours in _quickTargets)
                        FilterChip(
                          selected: _target == hours,
                          onSelected: (_) => setState(() => _target = hours),
                          label: Text(_hours(hours)),
                        ),
                    ],
                  ),
                  const SizedBox(height: Gap.lg),
                  Text(
                    met
                        ? 'You are already past this target for the week.'
                        : 'A target is a floor, not a ceiling — it only drives the '
                              'progress ring.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: Gap.lg),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Save target'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
