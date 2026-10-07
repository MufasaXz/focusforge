import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/app_shell.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/data/seed.dart';
import '../../../core/providers/study_providers.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/form_controls.dart';
import '../../../shared/widgets/sheet_chrome.dart';

/// Opens the editor for the daily focus goal.
///
/// One row per weekday, because the days are the thing that differs: a Sunday
/// with nothing on it and a Monday with school in it are not the same target,
/// and a single number would make the user choose which of the two to be wrong
/// about. Every change is written as the slider is released, so dismissing the
/// sheet can never discard a target.
Future<void> showDailyGoalSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _DailyGoalSheet(),
  );
}

class _DailyGoalSheet extends ConsumerStatefulWidget {
  const _DailyGoalSheet();

  @override
  ConsumerState<_DailyGoalSheet> createState() => _DailyGoalSheetState();
}

class _DailyGoalSheetState extends ConsumerState<_DailyGoalSheet> {
  static const _shortDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static const _spokenDays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  /// Every day's target, held locally and written on release so a drag across
  /// a slider is one store write rather than sixty.
  late final Map<int, int> _minutes = {
    for (var day = DateTime.monday; day <= DateTime.sunday; day++)
      day: ref.read(dailyGoalProvider).forWeekday(day),
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final today = DateTime.now().weekday;

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
              Text('Daily goal', style: tt.titleLarge),
              const SizedBox(height: Gap.xs),
              Text(
                'Every day can have its own target — a school day is not a '
                'Sunday.',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: Gap.md),
              for (var day = DateTime.monday; day <= DateTime.sunday; day++)
                _DayRow(
                  label: _shortDays[day - 1],
                  spokenLabel: _spokenDays[day - 1],
                  isToday: day == today,
                  minutes: _minutes[day] ?? DailyGoals.minMinutes,
                  onChanged: (v) => setState(() => _minutes[day] = v),
                  onChangeEnd: (v) =>
                      ref.read(dailyGoalProvider.notifier).setDay(day, v),
                ),
              const SizedBox(height: Gap.lg),
              PrimaryAction(
                label: 'Done',
                icon: Icons.check_rounded,
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One weekday's target: the day, the slider, and the value it currently
/// stands at.
class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.label,
    required this.spokenLabel,
    required this.isToday,
    required this.minutes,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final String spokenLabel;
  final bool isToday;
  final int minutes;
  final ValueChanged<int> onChanged;
  final ValueChanged<int> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(
            label,
            style: tt.labelLarge?.copyWith(
              // Today is the row the sheet was opened for, so it is the one
              // that says which number is in force right now.
              color: isToday ? cs.primary : cs.onSurface,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: minutes.toDouble(),
            min: DailyGoals.minMinutes.toDouble(),
            max: DailyGoals.maxMinutes.toDouble(),
            divisions: (DailyGoals.maxMinutes - DailyGoals.minMinutes) ~/ 15,
            label: formatMinutes(minutes),
            semanticFormatterCallback: (v) =>
                '$spokenLabel goal, ${formatMinutes(v.round())}',
            onChanged: (v) => onChanged(v.round()),
            onChangeEnd: (v) => onChangeEnd(v.round()),
          ),
        ),
        SizedBox(
          width: 58,
          child: Text(
            formatMinutes(minutes),
            textAlign: TextAlign.end,
            style: tt.labelMedium?.copyWith(
              color: isToday ? cs.primary : cs.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
