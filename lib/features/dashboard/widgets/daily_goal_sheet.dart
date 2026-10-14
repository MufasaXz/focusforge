import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/models/focus_goal.dart';
import '../../../core/models/study.dart';
import '../../../core/providers/goal_planner_providers.dart';
import '../../../core/providers/study_providers.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/app_segmented_control.dart';
import '../../../shared/widgets/sheet_chrome.dart';

/// Saves a date-bound daily goal or a repeating weekly plan after its subject
/// allocations add up to the exact chosen total.
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
  late FocusGoalScope _scope;
  late int _total;
  late final FixedExtentScrollController _wheel;
  final _allocations = <String, int>{};
  bool _saving = false;
  String? _error;
  static const _step = 15;

  @override
  void initState() {
    super.initState();
    // A saved zero-hour rest plan intentionally hides the ring, but remains
    // the value to edit rather than reopening with an invented one-hour goal.
    final plan = ref
        .read(focusGoalPlannerProvider)
        .forDate(ref.read(focusCalendarDateProvider));
    _scope = plan?.scope ?? FocusGoalScope.day;
    _total = plan?.totalMinutes ?? 60;
    _allocations.addAll(plan?.subjectMinutes ?? const {});
    _wheel = FixedExtentScrollController(initialItem: (_total / _step).round());
  }

  @override
  void dispose() {
    _wheel.dispose();
    super.dispose();
  }

  void _chooseScope(FocusGoalScope scope) {
    final planner = ref.read(focusGoalPlannerProvider);
    final date = ref.read(focusCalendarDateProvider);
    final plan = scope == FocusGoalScope.day ? planner.day : planner.week;
    setState(() {
      _scope = scope;
      _error = null;
      if (plan != null && plan.appliesOn(date)) {
        _total = plan.totalMinutes;
        _allocations.clear();
        _allocations.addAll(plan.subjectMinutes);
      }
    });
    _wheel.jumpToItem((_total / _step).round());
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
      for (final subject in subjects) subject.id: _allocations[subject.id] ?? 0,
    };
    if (values.values.fold<int>(0, (a, b) => a + b) != _total) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(focusGoalPlannerProvider.notifier)
          .save(
            FocusGoalPlan(
              scope: _scope,
              date: ref.read(focusCalendarDateProvider),
              totalMinutes: _total,
              subjectMinutes: values,
            ),
          );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save your goal. Please try again.';
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
    final valid = difference == 0 && (_total == 0 || subjects.isNotEmpty);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final date = ref.watch(focusCalendarDateProvider);
    final weekStart = DateTime(
      date.year,
      date.month,
      date.day - date.weekday + 1,
    );
    final weekEnd = DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day + 6,
    );

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
              Text('Make time for what matters', style: tt.titleLarge),
              const SizedBox(height: Gap.sm),
              Text(
                'Choose your target, then give each subject its share.',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: Gap.lg),
              AppSegmentedControl<FocusGoalScope>(
                options: const {
                  FocusGoalScope.day: 'For one day',
                  FocusGoalScope.week: 'For a week',
                },
                selected: _scope,
                onChanged: _saving ? (_) {} : _chooseScope,
              ),
              const SizedBox(height: Gap.sm),
              Text(
                _scope == FocusGoalScope.day
                    ? 'Today only · ${formatDate(date)}. Resets at midnight.'
                    : '${formatDate(weekStart)} – ${formatDate(weekEnd)}. Repeats each week; progress resets Monday.',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: Gap.lg),
              Text('Your focus time', style: tt.labelLarge),
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
                      _total = item * _step;
                      for (final subject in subjects) {
                        _allocations[subject.id] =
                            (_allocations[subject.id] ?? 0).clamp(0, _total);
                      }
                      _error = null;
                    });
                  },
                  children: [
                    for (
                      var value = 0;
                      value <= FocusGoalPlan.maxMinutes;
                      value += _step
                    )
                      Center(
                        child: Text(
                          value == 0 ? '0h · No target' : formatMinutes(value),
                          style: tt.headlineSmall?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.md),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Time for each subject', style: tt.titleMedium),
                  TextButton(
                    onPressed: _saving || subjects.isEmpty
                        ? null
                        : () => _splitEvenly(subjects),
                    child: const Text('Split evenly'),
                  ),
                ],
              ),
              if (subjects.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.md),
                  child: Text(
                    'Add a subject from the Focus page to plan your time.',
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
              Container(
                padding: const EdgeInsets.all(Gap.md),
                decoration: BoxDecoration(
                  color: valid ? cs.primaryContainer : cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(Radii.item),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${formatMinutes(assigned)} assigned / ${formatMinutes(_total)} target',
                      style: tt.labelLarge,
                    ),
                    const SizedBox(height: Gap.xs),
                    Text(
                      _total == 0
                          ? 'Your progress stays saved. The goal ring is hidden for this period.'
                          : difference == 0
                          ? 'Every minute has a place. Your plan is ready.'
                          : difference > 0
                          ? 'Give your subjects the remaining ${formatMinutes(difference)}.'
                          : 'Reduce subject time by ${formatMinutes(-difference)} to match your target.',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
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
                      : Text(
                          _total == 0 ? 'Save without a target' : 'Save goal',
                        ),
                ),
              ),
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
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
