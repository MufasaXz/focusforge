import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/study.dart';
import '../../core/models/user.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/study_providers.dart';
import '../../core/services/local_store.dart';
import '../focus/custom_plan_sheet.dart';
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
  String? _selectionOwner;

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
    final store = ref.read(localStoreProvider);
    final owner = ref.read(userProvider).uid;
    final key = plans[index].key;
    await ref.read(timerProvider.notifier).setPreset(index);
    await store.setMap(StoreKeys.startingPlan, {'uid': owner, 'key': key});
    if (mounted && ref.read(userProvider).uid == owner) widget.onNext();
  }

  Future<void> _createPlan() async {
    final plan = await showCustomPlanSheet(context);
    if (plan == null || !mounted) return;
    await ref.read(customPlanProvider.notifier).set(plan);
    if (!mounted) return;
    setState(() {
      _selectedKey = plan.toPreset().key;
      _explicitSelection = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final profile = ref.watch(userProvider);
    final intention = profile.focusIntention;
    if (_selectionOwner != profile.uid) {
      _selectionOwner = profile.uid;
      _selectedKey = null;
      _explicitSelection = false;
    }
    final plans = ref.watch(presetsProvider);
    final suggested = _recommend(plans, intention);
    // Resume an existing draft, including the user's own custom pace.
    if (_selectedKey == null) {
      final store = ref.read(localStoreProvider);
      final draft = store.getMap(StoreKeys.startingPlan);
      final timerKey = store.getMap(StoreKeys.presets)?['presetKey'];
      final stored = draft?['uid'] == profile.uid
          ? (draft?['key'])
          : (profile.onboardingComplete ? timerKey : null);
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
      title: 'Choose your pace',
      eyebrow: 'YOUR FIRST SESSION',
      subtitle:
          'We suggest ${suggested.focus} minutes. Pick what works for you.',
      primaryLabel: 'Use this plan',
      onPrimary: _save,
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
                  '${plan.focus} min focus · ${plan.shortBreak} min break',
              badge: plan.key == suggested.key ? 'Suggested' : null,
              icon: plan.icon,
              color: cs.primary,
              selected: plan.key == _selectedKey,
              onTap: () => setState(() {
                _selectedKey = plan.key;
                _explicitSelection = true;
              }),
            ),
          ),
        const SizedBox(height: Gap.sm),
        OutlinedButton.icon(
          onPressed: _createPlan,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Create your own plan'),
        ),
      ],
    );
  }
}
