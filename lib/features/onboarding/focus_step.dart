import '../../core/localization/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/user.dart';
import '../../core/providers/app_providers.dart';
import 'onboarding_chrome.dart';
import 'setup_choice_card.dart';

/// "What brings you here?" — one question, three answers.
///
/// The answer only shapes the starting plan offered later in setup; it never
/// turns on blocking or changes a running timer.
class FocusStep extends ConsumerStatefulWidget {
  const FocusStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  ConsumerState<FocusStep> createState() => _FocusStepState();
}

class _FocusStepState extends ConsumerState<FocusStep> {
  /// Null until the user taps an answer, so a profile restored from a backup
  /// keeps showing its own answer rather than a stale local one.
  FocusIntention? _picked;

  Future<void> _save() async {
    // Saved even when unchanged: a profile restored from a backup while this
    // step was open exists only in memory until something writes it.
    final profile = ref.read(userProvider);
    await ref
        .read(userProvider.notifier)
        .save(
          profile.copyWith(focusIntention: _picked ?? profile.focusIntention),
        );
    if (mounted) widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final current =
        _picked ?? ref.watch(userProvider.select((u) => u.focusIntention));

    return StepScaffold(
      title: context.tr("What brings you here?"),
      subtitle: context.tr("Choose your focus. We’ll suggest a starting plan."),
      onPrimary: _save,
      children: [
        for (final intention in FocusIntention.values)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: SetupChoiceCard(
              title: context.tr(intention.label),
              description: context.tr(intention.description),
              icon: intention.icon,
              color: cs.primary,
              iconColor: switch (intention) {
                FocusIntention.consistency => const Color(0xFF3FA66B),
                FocusIntention.distractions => const Color(0xFFE5674F),
                FocusIntention.deepWork => const Color(0xFF6C6CE0),
              },
              selected: intention == current,
              onTap: () => setState(() => _picked = intention),
            ),
          ),
      ],
    );
  }
}
