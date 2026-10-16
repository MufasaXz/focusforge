import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/user.dart';
import '../../core/providers/app_providers.dart';
import 'onboarding_chrome.dart';
import 'setup_choice_card.dart';

/// Saves the subject context and starting focus preference together.
class PersonaStep extends ConsumerStatefulWidget {
  const PersonaStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  ConsumerState<PersonaStep> createState() => _PersonaStepState();
}

class _PersonaStepState extends ConsumerState<PersonaStep> {
  late Persona _persona;
  late FocusIntention _intention;
  bool _personaEdited = false;
  bool _intentionEdited = false;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(userProvider);
    _persona = profile.persona;
    _intention = profile.focusIntention;
  }

  Future<void> _save() async {
    await ref
        .read(userProvider.notifier)
        .save(
          ref
              .read(userProvider)
              .copyWith(
                persona: _personaEdited
                    ? _persona
                    : ref.read(userProvider).persona,
                focusIntention: _intentionEdited
                    ? _intention
                    : ref.read(userProvider).focusIntention,
              ),
        );
    if (mounted) widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final profile = ref.watch(userProvider);
    if (!_personaEdited) _persona = profile.persona;
    if (!_intentionEdited) _intention = profile.focusIntention;

    return StepScaffold(
      title: 'What brings you here?',
      eyebrow: 'YOUR FOCUS',
      subtitle: 'Choose your focus. We’ll suggest a starting plan.',
      onPrimary: _save,
      children: [
        Text('I am here for', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: Gap.md),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            for (final persona in Persona.values)
              ChoiceChip(
                avatar: Icon(persona.icon, size: 18),
                label: Text(persona.label),
                selected: persona == _persona,
                onSelected: (_) => setState(() {
                  _persona = persona;
                  _personaEdited = true;
                }),
              ),
          ],
        ),
        const SizedBox(height: Gap.xl),
        Text(
          'What would help most?',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: Gap.md),
        for (final intention in FocusIntention.values)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: SetupChoiceCard(
              title: intention.label,
              description: intention.description,
              icon: intention.icon,
              color: cs.primary,
              selected: intention == _intention,
              onTap: () => setState(() {
                _intention = intention;
                _intentionEdited = true;
              }),
            ),
          ),
      ],
    );
  }
}
