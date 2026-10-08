import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/user.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/stagger.dart';
import 'onboarding_chrome.dart';
import 'setup_choice_card.dart';

/// The parent's choice between studying here and managing a child's device.
///
/// Only a parent's setup reaches this page: a student setting up their own
/// phone has answered it by being there, and the flow skips straight past. It
/// is separate from the persona answer on purpose — a parent who studies too
/// is ordinary — and it is the answer that decides which half of Parent
/// control opens first.
///
/// The parent persona suggests management; the labels describe what this
/// device will do, so the guardian setting cannot be mistaken for a child mode.
class DeviceStep extends ConsumerStatefulWidget {
  const DeviceStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  ConsumerState<DeviceStep> createState() => _DeviceStepState();
}

class _DeviceStepState extends ConsumerState<DeviceStep> {
  /// Null until the user picks for themselves, so the persona's suggestion can
  /// stand in without having been written to the profile yet.
  bool? _chosen;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProvider);
    final cs = Theme.of(context).colorScheme;
    final suggested = user.persona == Persona.parent;
    final selected = _chosen ?? suggested;

    return StepScaffold(
      title: 'How will you use this phone?',
      subtitle:
          'Choose whether you will study here or manage your child’s phone. '
          'You can change this later in Parent control.',
      onPrimary: () async {
        if (selected != user.isGuardian) {
          await ref.read(userProvider.notifier).setGuardianMode(selected);
        }
        if (mounted) widget.onNext();
      },
      children: [
        Stagger(
          index: 2,
          child: Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: SetupChoiceCard(
              icon: Icons.person_rounded,
              color: cs.secondary,
              title: 'Focus on this phone',
              description:
                  'Track my study and protect my focus on this device.',
              selected: !selected,
              onTap: () => setState(() => _chosen = false),
            ),
          ),
        ),
        Stagger(
          index: 3,
          child: Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: SetupChoiceCard(
              icon: Icons.family_restroom_rounded,
              color: cs.tertiary,
              title: 'Manage my child’s phone',
              description:
                  'See their progress and manage distractions from my phone.',
              selected: selected,
              onTap: () => setState(() => _chosen = true),
            ),
          ),
        ),
        if (selected) ...[
          const SizedBox(height: Gap.sm),
          Stagger(index: 4, child: const _PairingHint()),
        ],
      ],
    );
  }
}

/// What happens next on the parent's side. Said here rather than after setup,
/// because it is the step where the user is deciding whether they need the
/// child's phone in their hand.
class _PairingHint extends StatelessWidget {
  const _PairingHint();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card.outlined(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.qr_code_2_rounded, size: 18, color: cs.primary),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(
                'You will need your child\'s phone once. Install FocusForge '
                'there too, open Parent control on it, and type its six-digit '
                'code into this device.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
