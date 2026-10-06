import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/app_shell.dart';
import '../../../app/theme/color_tokens.dart';
import '../../../app/theme/glass_theme.dart';
import '../../../core/models/study.dart';
import '../../../core/providers/study_providers.dart';
import '../../../shared/widgets/glass_surface.dart';
import 'glass_button.dart';

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
    final t = context.glass;
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
      child: GlassPanel(
        radius: Radii.hero,
        blur: 24,
        padding: const EdgeInsets.all(Gap.lg),
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
                    color: t.textTertiary,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                ),
              ),
              const SizedBox(height: Gap.lg),
              Row(
                children: [
                  GlassIconBadge(
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
                        Text(s.name, style: context.type.titleMedium),
                        const SizedBox(height: 1),
                        Text(
                          '${_hours(s.weekDone)} done · $percent% of target',
                          style: context.type.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.xl),
              Row(
                children: [
                  Text('Weekly target', style: context.type.bodyLarge),
                  const Spacer(),
                  Text(
                    _hours(_target),
                    style: context.type.titleSmall?.copyWith(color: s.color),
                  ),
                ],
              ),
              Slider(
                value: _target,
                min: _min,
                max: _max,
                divisions: ((_max - _min) / _step).round(),
                activeColor: s.color,
                inactiveColor: t.track,
                label: _hours(_target),
                onChanged: (v) => setState(() => _target = v),
              ),
              Row(
                children: [
                  Text('1h', style: context.type.labelSmall),
                  const Spacer(),
                  Text('20h', style: context.type.labelSmall),
                ],
              ),
              const SizedBox(height: Gap.md),
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                children: [
                  for (final hours in _quickTargets)
                    GlassPill(
                      selected: _target == hours,
                      accent: s.color,
                      padding: const EdgeInsets.symmetric(
                        horizontal: Gap.md,
                        vertical: 7,
                      ),
                      onTap: () => setState(() => _target = hours),
                      child: Text(_hours(hours)),
                    ),
                ],
              ),
              const SizedBox(height: Gap.lg),
              Text(
                met
                    ? 'You are already past this target for the week.'
                    : 'A target is a floor, not a ceiling — it only drives the '
                          'progress ring.',
                style: context.type.bodySmall?.copyWith(color: t.textTertiary),
              ),
              const SizedBox(height: Gap.lg),
              GlassButton(
                label: 'Save target',
                icon: Icons.check_rounded,
                accent: s.color,
                onTap: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
