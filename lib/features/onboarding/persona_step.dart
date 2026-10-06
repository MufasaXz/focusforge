import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/user.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/glass_surface.dart';
import '../../shared/widgets/stagger.dart';
import 'onboarding_chrome.dart';

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
              child: _PersonaCard(
                persona: Persona.values[i],
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

class _PersonaCard extends StatelessWidget {
  const _PersonaCard({
    required this.persona,
    required this.selected,
    required this.onTap,
  });

  final Persona persona;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GlassPanel(
      radius: Radii.card,
      accent: selected ? persona.color : null,
      glowStrength: selected ? 0.85 : 0,
      padding: const EdgeInsets.all(Gap.lg),
      child: Pressable(
        onTap: onTap,
        child: Row(
          children: [
            GlassIconBadge(
              icon: persona.icon,
              color: persona.color,
              size: 48,
              radius: Radii.item,
              glow: selected ? 0.6 : 0,
            ),
            const SizedBox(width: Gap.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(persona.label, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    persona.blurb,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Gap.md),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: selected
                  ? Icon(
                      Icons.check_circle_rounded,
                      key: const ValueKey('selected'),
                      color: persona.color,
                      size: 24,
                    )
                  : Icon(
                      Icons.radio_button_unchecked_rounded,
                      key: const ValueKey('unselected'),
                      color: cs.onSurfaceVariant,
                      size: 24,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
