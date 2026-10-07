import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/user.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/icon_badge.dart';
import '../../shared/widgets/stagger.dart';
import 'onboarding_chrome.dart';

/// Screen 3 — whose device is this.
///
/// One question, asked of everyone: are you here to study, or to watch someone
/// else study? It is separate from the persona answer on purpose — a parent
/// who studies too, and a student whose phone was set up by a parent, are both
/// ordinary — and it is the answer that decides which half of Parent control
/// opens first.
///
/// The persona is only a hint at the default: choosing "Parent" preselects the
/// child's side, and tapping Continue without touching anything takes it.
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
    final suggested = user.persona == Persona.parent;
    final selected = _chosen ?? suggested;

    return StepScaffold(
      title: 'Whose device is this?',
      subtitle:
          'It decides what opens first. You can change it later in Profile → '
          'Parent control.',
      onPrimary: () async {
        if (selected != user.isGuardian) {
          await ref.read(userProvider.notifier).setGuardianMode(selected);
        }
        widget.onNext();
      },
      children: [
        Stagger(
          index: 2,
          child: Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: _DeviceCard(
              icon: Icons.person_rounded,
              color: const Color(0xFF7FA9FF),
              title: 'Mine',
              blurb: 'I am here to focus and track my own study.',
              selected: !selected,
              onTap: () => setState(() => _chosen = false),
            ),
          ),
        ),
        Stagger(
          index: 3,
          child: Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: _DeviceCard(
              icon: Icons.family_restroom_rounded,
              color: const Color(0xFF8FE39B),
              title: 'My child\'s',
              blurb:
                  'I set this up to see how their study is going, and to keep '
                  'their distractions closed.',
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
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.blurb,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String blurb;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(
          color: selected ? harmonize(color, cs.primary) : cs.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Row(
            children: [
              IconBadge(
                icon: icon,
                color: harmonize(color, cs.primary),
                size: 48,
                radius: Radii.item,
              ),
              const SizedBox(width: Gap.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      blurb,
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
                        color: harmonize(color, cs.primary),
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
      ),
    );
  }
}
