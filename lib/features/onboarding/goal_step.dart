import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/data/seed.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/study_providers.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/stagger.dart';
import 'onboarding_chrome.dart';

/// Screen 6 — the daily focus goal.
///
/// One number, and the slider is the only control: the goal has to be
/// something the user believes they can hit on a bad day, so the screen shows
/// the honest advice next to it rather than a fake statistic. The persona's
/// recommended value is the starting point.
class GoalStep extends ConsumerStatefulWidget {
  const GoalStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  ConsumerState<GoalStep> createState() => _GoalStepState();
}

class _GoalStepState extends ConsumerState<GoalStep> {
  static const _min = 30.0;
  static const _max = 360.0;

  late final Persona _persona = ref.read(userProvider).persona;

  /// The persona's recommendation, unless the user already has a goal of their
  /// own. The seed value is the one number that cannot be told apart from a
  /// deliberate choice, so it is treated as "not chosen yet".
  late double _minutes = () {
    final stored = ref.read(dailyGoalProvider);
    final base = stored == SeedData.focusGoalMinutes
        ? SeedData.goalSuggestions(_persona)[1]
        : stored;
    return base.toDouble().clamp(_min, _max);
  }();

  /// Writes on drag end as well as on continue, so stepping back to check
  /// another screen does not silently discard the number.
  Future<void> _commit() async {
    await ref.read(dailyGoalProvider.notifier).set(_minutes.round());
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final suggestions = SeedData.goalSuggestions(_persona);

    return StepScaffold(
      title: 'Set your daily goal',
      subtitle:
          'A target you can hit most days is worth more than a heroic '
          'one you abandon.',
      onPrimary: _commit,
      children: [
        Stagger(
          index: 2,
          child: Center(
            child: ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (rect) =>
                  LinearGradient(colors: [cs.primary, cs.secondary])
                      .createShader(rect),
              child: Text(
                formatMinutes(_minutes.round()),
                style: Theme.of(context).textTheme.displayLarge
                    ?.copyWith(fontSize: 68, height: 1.05, letterSpacing: -2),
              ),
            ),
          ),
        ),
        Stagger(
          index: 3,
          child: Center(
            child: Text(
              'of focus per day',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ),
        const SizedBox(height: Gap.xl),
        Stagger(
          index: 4,
          child: Slider(
            value: _minutes,
            min: _min,
            max: _max,
            divisions: ((_max - _min) / 15).round(),
            label: formatMinutes(_minutes.round()),
            onChanged: (v) => setState(() => _minutes = v),
            onChangeEnd: (v) =>
                ref.read(dailyGoalProvider.notifier).set(v.round()),
          ),
        ),
        Stagger(
          index: 5,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
            child: Row(
              children: [
                Text('30m', style: Theme.of(context).textTheme.labelSmall),
                const Spacer(),
                Text('6h', style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
        ),
        const SizedBox(height: Gap.xl),
        const Stagger(
          index: 6,
          child: SectionHeader(title: 'Suggested for you'),
        ),
        Stagger(
          index: 7,
          child: Row(
            children: [
              for (var i = 0; i < suggestions.length; i++) ...[
                if (i > 0) const SizedBox(width: Gap.sm),
                Expanded(
                  child: FilterChip(
                    selected: _minutes.round() == suggestions[i],
                    onSelected: (_) =>
                        setState(() => _minutes = suggestions[i].toDouble()),
                    // A two-line label; a checkmark would crowd it out.
                    showCheckmark: false,
                    padding: const EdgeInsets.symmetric(vertical: Gap.sm),
                    // The chip is stretched by its [Expanded] parent; a chip
                    // lays its label out from the start edge, so the label
                    // itself has to claim the full width for the two lines to
                    // stay centred.
                    label: SizedBox(
                      width: double.infinity,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_label(i), textAlign: TextAlign.center),
                          const SizedBox(height: 2),
                          Text(
                            formatMinutes(suggestions[i]),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: _minutes.round() == suggestions[i]
                                      ? cs.onSecondaryContainer
                                      : cs.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Gap.xl),
        Stagger(
          index: 8,
          child: Card.outlined(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.item),
              side: BorderSide(color: cs.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.psychology_alt_rounded,
                    size: 18,
                    color: cs.secondary,
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Text(
                      _insight,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _label(int i) => const ['Light', 'Recommended', 'Intense'][i];

  String get _insight => switch (_persona) {
    Persona.student =>
      'Short daily blocks beat one long cram session — your memory '
          'consolidates between sessions, not during them.',
    Persona.professional =>
      'A protected block beats a busy day. Deep work is what compounds, '
          'so defend the same window every day.',
    Persona.parent =>
      'A small goal your child can hit every day beats a big one they '
          'give up on in a week.',
  };
}
