import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/user.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/stagger.dart';
import 'onboarding_chrome.dart';
import 'setup_choice_card.dart';

/// Screen 2 — persona.
///
/// One choice that changes everything downstream: the subject list, the goal
/// suggestions and the copy. It is written straight to the profile so the very
/// next step can already be persona-aware.
class PersonaStep extends ConsumerWidget {
  const PersonaStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(userProvider).persona;

    return StepScaffold(
      title: 'I am a...',
      subtitle:
          'This tunes the subjects, goals and wording you see first. You can '
          'change it later in your profile.',
      onPrimary: onNext,
      children: [
        for (var i = 0; i < Persona.values.length; i++)
          Stagger(
            index: i + 2,
            child: Padding(
              padding: const EdgeInsets.only(bottom: Gap.md),
              child: SetupChoiceCard(
                title: Persona.values[i].label,
                description: Persona.values[i].blurb,
                icon: Persona.values[i].icon,
                color: Persona.values[i].color,
                selected: Persona.values[i] == selected,
                onTap: () => ref
                    .read(userProvider.notifier)
                    .setPersona(Persona.values[i]),
              ),
            ),
          ),
      ],
    );
  }
}
