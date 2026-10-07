import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/models/parent.dart';
import '../../../core/providers/parent_providers.dart';

/// The children a parent can look at, as a row of chips.
///
/// Rendered only when there is a choice to make: with one child there is
/// nothing to switch to, and a single selected chip reads as a filter that
/// does nothing. Callers that have exactly one child show their name instead.
///
/// Selection is held by id in `selectedChildProvider`, so a stream that
/// reorders — a child added, a link removed — cannot silently move the choice
/// to somebody else.
class ChildChips extends ConsumerWidget {
  const ChildChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children =
        ref.watch(childrenProvider).valueOrNull ?? const <ChildLink>[];
    if (children.length < 2) return const SizedBox.shrink();

    final active = ref.watch(activeChildProvider);
    final cs = Theme.of(context).colorScheme;

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(width: Gap.sm),
      itemBuilder: (context, index) {
        final child = children[index];
        final selected = child.uid == active?.uid;
        return ChoiceChip(
          label: Text(child.name),
          selected: selected,
          showCheckmark: false,
          // The chip is a mode switch, not a form field: it says which child
          // everything below is about.
          labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
          ),
          onSelected: (_) =>
              ref.read(selectedChildProvider.notifier).select(child.uid),
        );
      },
    );
  }
}
