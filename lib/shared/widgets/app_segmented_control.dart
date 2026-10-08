import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

/// Equal-width choices with one moving tonal selection surface.
class AppSegmentedControl<T> extends StatelessWidget {
  const AppSegmentedControl({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  }) : assert(options.length > 1);

  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    assert(options.containsKey(selected));
    final cs = Theme.of(context).colorScheme;
    final entries = options.entries.toList(growable: false);
    final index = entries.indexWhere((entry) => entry.key == selected);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Radii.item),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Gap.xs),
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedAlign(
                alignment: AlignmentDirectional(
                  -1 + 2 * index / (entries.length - 1),
                  0,
                ),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : Motion.base,
                curve: Motion.emphasized,
                child: FractionallySizedBox(
                  widthFactor: 1 / entries.length,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(Radii.tile),
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (final entry in entries)
                  Expanded(
                    child: MergeSemantics(
                      child: Semantics(
                        selected: entry.key == selected,
                        inMutuallyExclusiveGroup: true,
                        child: TextButton(
                          onPressed: () => onChanged(entry.key),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            padding: const EdgeInsets.symmetric(
                              horizontal: Gap.sm,
                              vertical: Gap.sm,
                            ),
                            foregroundColor: entry.key == selected
                                ? cs.onSecondaryContainer
                                : cs.onSurfaceVariant,
                            textStyle: Theme.of(context).textTheme.labelLarge,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(Radii.tile),
                            ),
                          ),
                          child: Text(entry.value, textAlign: TextAlign.center),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
