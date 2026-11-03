import '../../core/localization/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/user.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/stagger.dart';
import 'onboarding_chrome.dart';

/// "What brings you here?" — one question, three answers.
///
/// Each answer is a card with its own colour, the block length it starts you
/// on, and a line underneath that says what the choice will set up. The answer
/// only shapes the starting plan offered later in setup; it never turns on
/// blocking or changes a running timer.
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final FocusIntention current =
        _picked ??
        ref.watch(userProvider.select((u) => u.focusIntention)) ??
        FocusIntention.consistency;

    return StepScaffold(
      title: context.tr("What brings you here?"),
      subtitle: context.tr("Choose your focus. We’ll suggest a starting plan."),
      onPrimary: _save,
      children: [
        for (final (index, intention) in FocusIntention.values.indexed)
          Stagger(
            index: index + 2,
            child: Padding(
              padding: const EdgeInsets.only(bottom: Gap.md),
              child: _IntentionCard(
                intention: intention,
                selected: intention == current,
                onTap: () {
                  if (intention != current) HapticFeedback.selectionClick();
                  setState(() => _picked = intention);
                },
              ),
            ),
          ),
        const SizedBox(height: Gap.sm),
        AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : Motion.base,
          child: Row(
            key: ValueKey(current),
            children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: cs.primary),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  context.tr("You’ll start with {0}-minute focus blocks.", [
                    current.blockMinutes,
                  ]),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Each answer's own colour, pulled toward the theme so the three sit
/// together.
Color _tint(FocusIntention intention, Color primary) =>
    harmonize(switch (intention) {
      FocusIntention.consistency => const Color(0xFF3FA66B),
      FocusIntention.distractions => const Color(0xFFE5674F),
      FocusIntention.deepWork => const Color(0xFF6C6CE0),
    }, primary);

class _IntentionCard extends StatelessWidget {
  const _IntentionCard({
    required this.intention,
    required this.selected,
    required this.onTap,
  });

  final FocusIntention intention;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tint = _tint(intention, cs.primary);
    final dark = theme.brightness == Brightness.dark;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.base;
    final title = context.tr(intention.label);
    final body = context.tr(intention.description);
    final tag = context.tr("{0}-min blocks", [intention.blockMinutes]);

    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: '$title. $body. $tag',
      onTap: onTap,
      excludeSemantics: true,
      child: AnimatedScale(
        duration: duration,
        curve: Motion.emphasized,
        scale: selected ? 1 : .985,
        child: AnimatedContainer(
          duration: duration,
          curve: Motion.decelerate,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.card + 4),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: selected
                  ? [
                      Color.alphaBlend(
                        tint.withValues(alpha: dark ? .30 : .18),
                        cs.surface,
                      ),
                      Color.alphaBlend(
                        tint.withValues(alpha: dark ? .12 : .06),
                        cs.surface,
                      ),
                    ]
                  : [cs.surfaceContainerLow, cs.surfaceContainerLow],
            ),
            border: Border.all(
              color: selected ? tint : cs.outlineVariant.withValues(alpha: .6),
              width: selected ? 2 : 1,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            borderRadius: BorderRadius.circular(Radii.card + 4),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(Gap.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: duration,
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: selected
                              ? [tint, Color.lerp(tint, Colors.black, .25)!]
                              : [
                                  tint.withValues(alpha: .16),
                                  tint.withValues(alpha: .10),
                                ],
                        ),
                      ),
                      child: Icon(
                        intention.icon,
                        size: 28,
                        color: selected ? Colors.white : tint,
                      ),
                    ),
                    const SizedBox(width: Gap.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              AnimatedSwitcher(
                                duration: duration,
                                transitionBuilder: (child, animation) =>
                                    ScaleTransition(
                                      scale: animation,
                                      child: child,
                                    ),
                                child: selected
                                    ? Container(
                                        key: const ValueKey('on'),
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: tint,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.check_rounded,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const SizedBox(
                                        key: ValueKey('off'),
                                        width: 24,
                                        height: 24,
                                      ),
                              ),
                            ],
                          ),
                          const SizedBox(height: Gap.xs),
                          Text(
                            body,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: Gap.md),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Gap.sm + 2,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: tint.withValues(alpha: .14),
                              borderRadius: BorderRadius.circular(Radii.pill),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.timer_outlined,
                                  size: 14,
                                  color: tint,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    tag,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: tint,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
