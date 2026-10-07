import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell/app_shell.dart';
import '../../app/theme/app_theme.dart';
import '../../core/models/study.dart';
import '../../core/providers/study_providers.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/form_controls.dart';
import '../../shared/widgets/sheet_chrome.dart';

/// Opens the sheet that sets a study goal and a focus-block length.
///
/// Returns the plan the user settled on, or null if they backed out. The
/// caller applies it — this sheet only decides the numbers.
///
/// Two sliders and a running summary, rather than five fields: the breaks and
/// the number of blocks are consequences of the two numbers that are actually
/// a matter of preference, and showing the consequence while the slider moves
/// is what lets the user see that a 4-hour goal at 50 minutes is five blocks,
/// not four and a bit.
Future<CustomPlan?> showCustomPlanSheet(BuildContext context) {
  return showModalBottomSheet<CustomPlan>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _CustomPlanSheet(),
  );
}

class _CustomPlanSheet extends ConsumerStatefulWidget {
  const _CustomPlanSheet();

  @override
  ConsumerState<_CustomPlanSheet> createState() => _CustomPlanSheetState();
}

class _CustomPlanSheetState extends ConsumerState<_CustomPlanSheet> {
  /// Seeded from the plan already in use, so opening the sheet to adjust one
  /// number does not silently reset the other.
  late int _goal =
      ref.read(customPlanProvider)?.goalMinutes ?? 4 * 60;
  late int _focus = ref.read(customPlanProvider)?.focusMinutes ?? 50;

  CustomPlan get _plan =>
      CustomPlan(goalMinutes: _goal, focusMinutes: _focus);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final plan = _plan;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Gap.lg,
        Gap.lg,
        Gap.lg,
        kNavBarClearance + MediaQuery.paddingOf(context).bottom,
      ),
      child: SheetSurface(
        borderRadius: BorderRadius.circular(Radii.hero),
        padding: const EdgeInsets.all(Gap.lg),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              const SizedBox(height: Gap.lg),
              Text(
                'Your own plan',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: Gap.xs),
              Text(
                'Set how long you mean to study and how long a block runs. '
                'The breaks and the number of blocks follow from those two.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: Gap.lg),
              _NumberSlider(
                label: 'Study goal',
                value: _goal,
                min: CustomPlan.minGoal,
                max: CustomPlan.maxGoal,
                step: 15,
                readout: formatMinutes(_goal),
                onChanged: (v) => setState(() => _goal = v),
              ),
              const SizedBox(height: Gap.md),
              _NumberSlider(
                label: 'Focus block',
                value: _focus,
                min: CustomPlan.minFocus,
                max: CustomPlan.maxFocus,
                step: 5,
                readout: '${_focus}m',
                onChanged: (v) => setState(() => _focus = v),
              ),
              const SizedBox(height: Gap.lg),
              _PlanSummary(plan: plan),
              const SizedBox(height: Gap.lg),
              PrimaryAction(
                label: 'Use this plan',
                icon: Icons.check_rounded,
                onTap: () => Navigator.of(context).pop(plan),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One labelled slider with its value at the end of the label row.
///
/// The value is written out rather than left to the slider's own bubble: the
/// two sliders move together — a block length changes how many blocks the goal
/// takes — and a readout that only appears under the thumb makes the user
/// chase it to see the effect.
class _NumberSlider extends StatelessWidget {
  const _NumberSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.readout,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final String readout;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final divisions = (max - min) ~/ step;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: theme.textTheme.titleSmall),
            ),
            Text(
              readout,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: divisions,
          label: readout,
          onChanged: (v) => onChanged(v.round()),
        ),
      ],
    );
  }
}

/// What the two numbers add up to, spelled out.
class _PlanSummary extends StatelessWidget {
  const _PlanSummary({required this.plan});

  final CustomPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final lines = <(IconData, String)>[
      (
        Icons.timer_outlined,
        '${plan.blocks} focus ${plan.blocks == 1 ? 'block' : 'blocks'} of '
            '${plan.focusMinutes}m',
      ),
      (Icons.coffee_outlined, '${plan.shortBreak}m break between them'),
      (
        Icons.self_improvement_rounded,
        '${plan.longBreak}m long break every ${plan.cadence} blocks',
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Radii.item),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) const SizedBox(height: Gap.sm),
            Row(
              children: [
                Icon(lines[i].$1, size: 15, color: cs.onSurfaceVariant),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    lines[i].$2,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: Gap.md),
          // The goal is rounded up to whole blocks, so the plan usually runs a
          // few minutes past it. Saying so is the difference between a plan
          // the user can trust and one that looks like it cannot add up.
          Text(
            '${formatMinutes(plan.plannedMinutes)} of focus in total',
            style: theme.textTheme.titleSmall?.copyWith(color: cs.primary),
          ),
        ],
      ),
    );
  }
}
