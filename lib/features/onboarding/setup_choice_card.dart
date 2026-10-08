import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/widgets/icon_badge.dart';

/// One selectable setup answer, with the same feedback in every step.
class SetupChoiceCard extends StatelessWidget {
  const SetupChoiceCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final accent = harmonize(color, cs.primary);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.base;

    void select() {
      if (!selected) HapticFeedback.selectionClick();
      onTap();
    }

    final radius = selected ? Radii.item : Radii.hero;
    return Semantics(
      label: '$title. $description',
      checked: selected,
      inMutuallyExclusiveGroup: true,
      onTap: select,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: duration,
        curve: Motion.decelerate,
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.10)
              : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: selected ? accent : cs.outlineVariant,
            width: 1,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: select,
            child: Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: Row(
                children: [
                  IconBadge(
                    icon: icon,
                    color: accent,
                    size: 48,
                    radius: selected ? Radii.tile : 20,
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: tt.titleMedium),
                        const SizedBox(height: Gap.xs),
                        Text(description, style: tt.bodyMedium),
                      ],
                    ),
                  ),
                  const SizedBox(width: Gap.md),
                  AnimatedSwitcher(
                    duration: duration,
                    switchInCurve: Motion.decelerate,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.8,
                          end: 1,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      key: ValueKey(selected),
                      color: selected ? accent : cs.onSurfaceVariant,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
