import '../../../core/localization/app_strings.dart';

import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/models/focus_goal.dart';
import '../../../core/models/study.dart';
import '../../../core/providers/goal_planner_providers.dart';
import '../../../core/providers/study_providers.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/sheet_chrome.dart';

/// Saves a daily goal, optionally split across subjects and repeated this week.
Future<void> showDailyGoalSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _FocusGoalSheet(),
    );

class _FocusGoalSheet extends ConsumerStatefulWidget {
  const _FocusGoalSheet();
  @override
  ConsumerState<_FocusGoalSheet> createState() => _FocusGoalSheetState();
}

class _FocusGoalSheetState extends ConsumerState<_FocusGoalSheet> {
  late int _total;
  late final FixedExtentScrollController _wheel;
  final _allocations = <String, int>{};
  bool _saving = false;
  bool _repeatThisWeek = false;
  String? _error;
  static const _step = 15;

  @override
  void initState() {
    super.initState();
    final plan = ref
        .read(focusGoalPlannerProvider)
        .forDate(ref.read(focusCalendarDateProvider));
    // Every value on the wheel can be saved, so it starts at one step. A
    // zero-hour plan saved by an older build opens on that first step.
    _total = math.max(
      _step,
      plan?.totalMinutes ??
          ref.read(focusGoalPlannerProvider).day?.totalMinutes ??
          60,
    );
    _repeatThisWeek = plan?.repeatThisWeek ?? false;
    _allocations.addAll(plan?.subjectMinutes ?? const {});
    _wheel = FixedExtentScrollController(initialItem: _itemOf(_total));
  }

  /// The wheel row showing [minutes]: row 0 is one [_step].
  static int _itemOf(int minutes) => (minutes / _step).round() - 1;

  @override
  void dispose() {
    _wheel.dispose();
    super.dispose();
  }

  void _splitEvenly(List<Subject> subjects) {
    if (subjects.isEmpty) return;
    final perSubject = _total ~/ subjects.length;
    var remainder = _total % subjects.length;
    setState(() {
      _allocations.clear();
      for (final subject in subjects) {
        _allocations[subject.id] = perSubject + (remainder-- > 0 ? 1 : 0);
      }
      _error = null;
    });
  }

  Future<void> _save(List<Subject> subjects) async {
    if (_saving) return;
    final values = {
      for (final subject in subjects)
        if ((_allocations[subject.id] ?? 0) > 0)
          subject.id: _allocations[subject.id]!,
    };
    if (_total <= 0 ||
        (values.isNotEmpty &&
            values.values.fold<int>(0, (a, b) => a + b) != _total)) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(focusGoalPlannerProvider.notifier)
          .save(
            FocusGoalPlan(
              scope: FocusGoalScope.day,
              date: ref.read(focusCalendarDateProvider),
              totalMinutes: _total,
              subjectMinutes: values,
              repeatThisWeek: _repeatThisWeek,
            ),
          );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = tr("Could not save your goal. Please try again.");
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final subjects = ref.watch(subjectsProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final assigned = subjects.fold<int>(
      0,
      (sum, s) => sum + (_allocations[s.id] ?? 0),
    );
    final difference = _total - assigned;
    final valid = _total > 0 && (assigned == 0 || difference == 0);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .92,
      ),
      child: SheetSurface(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Radii.hero),
        ),
        padding: EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.lg + bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              const SizedBox(height: Gap.lg),
              Text(context.tr("Set your daily goal"), style: tt.titleLarge),
              const SizedBox(height: Gap.xs),
              SizedBox(
                height: 140,
                child: CupertinoPicker(
                  scrollController: _wheel,
                  itemExtent: 42,
                  magnification: 1.08,
                  useMagnifier: true,
                  onSelectedItemChanged: (item) {
                    if (_saving) return;
                    setState(() {
                      _total = (item + 1) * _step;
                      for (final subject in subjects) {
                        _allocations[subject.id] =
                            (_allocations[subject.id] ?? 0).clamp(0, _total);
                      }
                      _error = null;
                    });
                  },
                  children: [
                    for (
                      var value = _step;
                      value <= FocusGoalPlan.maxMinutes;
                      value += _step
                    )
                      Center(
                        child: Text(
                          formatMinutes(value),
                          style: tt.headlineSmall?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.md),
              Material(
                color: Colors.transparent,
                child: SwitchListTile.adaptive(
                  key: const ValueKey('repeat-daily-goal'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.tr("Repeat through Sunday")),
                  value: _repeatThisWeek,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _repeatThisWeek = value),
                ),
              ),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    context.tr("Subjects · optional"),
                    style: tt.titleMedium,
                  ),
                  TextButton(
                    onPressed: _saving || subjects.isEmpty
                        ? null
                        : () => _splitEvenly(subjects),
                    child: Text(context.tr("Split evenly")),
                  ),
                ],
              ),
              if (subjects.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.md),
                  child: Text(
                    context.tr(
                      "Add a subject from the Focus page to plan your time.",
                    ),
                    style: tt.bodyMedium,
                  ),
                ),
              for (final subject in subjects) ...[
                _AllocationRow(
                  subject: subject,
                  total: _total,
                  minutes: (_allocations[subject.id] ?? 0).clamp(0, _total),
                  onChanged: _saving || _total == 0
                      ? null
                      : (value) => setState(() {
                          _allocations[subject.id] = value;
                          _error = null;
                        }),
                ),
                const SizedBox(height: Gap.sm),
              ],
              const SizedBox(height: Gap.sm),
              if (assigned > 0)
                Container(
                  padding: const EdgeInsets.all(Gap.md),
                  decoration: BoxDecoration(
                    color: valid
                        ? cs.primaryContainer
                        : cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(Radii.item),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr("{0} assigned / {1} target", [
                          formatMinutes(assigned),
                          formatMinutes(_total),
                        ]),
                        style: tt.labelLarge,
                      ),
                      const SizedBox(height: Gap.xs),
                      Text(
                        difference == 0
                            ? context.tr(
                                "Every minute has a place. Your plan is ready.",
                              )
                            : difference > 0
                            ? context.tr(
                                "Give your subjects the remaining {0}.",
                                [formatMinutes(difference)],
                              )
                            : context.tr(
                                "Reduce subject time by {0} to match your target.",
                                [formatMinutes(-difference)],
                              ),
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.sm),
                  child: Text(
                    _error!,
                    style: tt.bodySmall?.copyWith(color: cs.error),
                  ),
                ),
              const SizedBox(height: Gap.lg),
              FilledButton(
                key: const ValueKey('save-focus-goal'),
                onPressed: valid && !_saving ? () => _save(subjects) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.sm),
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(context.tr("Save goal")),
                ),
              ),
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: Text(context.tr("Cancel")),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AllocationRow extends StatelessWidget {
  const _AllocationRow({
    required this.subject,
    required this.total,
    required this.minutes,
    required this.onChanged,
  });
  final Subject subject;
  final int total;
  final int minutes;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.xs),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                subject.icon,
                color: harmonize(subject.color, cs.primary),
                size: 21,
              ),
              const SizedBox(width: Gap.sm),
              Expanded(child: Text(subject.name, style: tt.bodyLarge)),
              const SizedBox(width: Gap.sm),
              Text(
                formatMinutes(minutes),
                style: tt.labelLarge?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Slider(
            key: ValueKey('goal-subject-${subject.id}'),
            value: minutes.toDouble(),
            min: 0,
            max: total > 0 ? total.toDouble() : 1,
            label: formatMinutes(minutes),
            semanticFormatterCallback: (value) =>
                '${subject.name}: ${formatMinutes(value.round())}',
            onChanged: onChanged == null
                ? null
                : (value) => onChanged!(value.round()),
          ),
        ],
      ),
    );
  }
}
