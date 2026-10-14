import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/study.dart';
import '../../core/models/user.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/study_providers.dart';
import '../../core/services/local_store.dart';
import 'onboarding_chrome.dart';
import 'setup_choice_card.dart';

/// Configures the same persisted timer used on Home.
class StartingPlanStep extends ConsumerStatefulWidget {
  const StartingPlanStep({super.key, required this.onNext});
  final VoidCallback onNext;

  @override
  ConsumerState<StartingPlanStep> createState() => _StartingPlanStepState();
}

class _StartingPlanStepState extends ConsumerState<StartingPlanStep> {
  String? _selectedKey;
  bool _explicitSelection = false;
  FocusIntention? _lastIntention;

  PomodoroPreset _recommend(
    List<PomodoroPreset> plans,
    FocusIntention intention,
  ) {
    return plans.reduce(
      (best, candidate) =>
          (candidate.focus - intention.blockMinutes).abs() <
              (best.focus - intention.blockMinutes).abs()
          ? candidate
          : best,
    );
  }

  Future<void> _save() async {
    final plans = ref.read(presetsProvider);
    final index = plans.indexWhere((plan) => plan.key == _selectedKey);
    if (index < 0) return;
    await ref.read(timerProvider.notifier).setPreset(index);
    if (mounted) widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final intention = ref.watch(userProvider).focusIntention;
    final plans = ref.watch(presetsProvider);
    final suggested = _recommend(plans, intention);
    // Resume an existing draft, including the user's own custom pace.
    if (_selectedKey == null) {
      final stored = ref
          .read(localStoreProvider)
          .getMap(StoreKeys.presets)?['presetKey'];
      final saved = plans.where((plan) => plan.key == stored).firstOrNull;
      _explicitSelection = saved != null;
      _selectedKey = saved?.key ?? suggested.key;
    } else if ((!_explicitSelection && _lastIntention != intention) ||
        !plans.any((plan) => plan.key == _selectedKey)) {
      _selectedKey = suggested.key;
      _explicitSelection = false;
    }
    _lastIntention = intention;
    final selected = plans.firstWhere((plan) => plan.key == _selectedKey);

    return StepScaffold(
      title: 'Find your starting pace',
      subtitle:
          'Based on your focus preference, we suggest a ${suggested.focus}-minute block. Choose what feels manageable today.',
      primaryLabel: 'Use this plan',
      onPrimary: _save,
      footnote: 'Change, rename or create plans in Focus. Blocking stays off until you choose it in Shield.',
      children: [
        Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.only(bottom: Gap.xl),
            child: Wrap(
              spacing: Gap.lg,
              runSpacing: Gap.sm,
              children: [
                Text(
                  '${selected.focus} min focus',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: cs.primary),
                ),
                Text(
                  '${selected.shortBreak} min break',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ),
        for (final plan in plans)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: SetupChoiceCard(
              title: plan.name,
              description:
                  '${plan.focus} minutes of focus · ${plan.shortBreak} minute breaks${plan.key == suggested.key ? ' · Suggested for you' : ''}',
              icon: plan.icon,
              color: cs.primary,
              selected: plan.key == _selectedKey,
              onTap: () => setState(() {
                _selectedKey = plan.key;
                _explicitSelection = true;
              }),
            ),
          ),
      ],
    );
  }
}
