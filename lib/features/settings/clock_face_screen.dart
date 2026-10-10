import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/user.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/study_providers.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/pressable.dart';
import '../focus/widgets/clock_faces.dart';

/// How the timer draws its figures.
///
/// A page rather than a row of tiles on the profile: seven faces need the width
/// to be seen at all — a flip card at 40dp is a grey smudge, and the whole
/// point of the choice is what the face looks like — and a page is where the
/// rest of the app's settings already live.
///
/// Every preview draws the timer's own remaining time and its own progress.
/// Nothing here is a sample: a face that looks right at a made-up 24:51 is no
/// guarantee it looks right at the number on the clock, and there is exactly
/// one real number available.
class ClockFaceScreen extends ConsumerWidget {
  const ClockFaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final selected = ref.watch(clockFaceProvider);
    final timer = ref.watch(timerProvider);
    final preset = ref.watch(presetsProvider)[timer.presetIndex];

    return AppPage(
      title: 'Clock face',
      subtitle: 'How the timer draws its figures',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final face in ClockFace.values) ...[
            _FaceCard(
              face: face,
              remaining: timer.remaining,
              progress: timer.progressFor(preset),
              selected: face == selected,
              onTap: () {
                HapticFeedback.selectionClick();
                ref.read(clockFaceProvider.notifier).set(face);
              },
            ),
            const SizedBox(height: Gap.md),
          ],
          const SizedBox(height: Gap.xs),
          Text(
            'The face changes how the figures are drawn, not what they say. '
            'The timer, the ring and the full-screen clock all read the same '
            'value.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// One face: what it looks like, what it is called, and whether it is on.
class _FaceCard extends StatelessWidget {
  const _FaceCard({
    required this.face,
    required this.remaining,
    required this.progress,
    required this.selected,
    required this.onTap,
  });

  final ClockFace face;
  final Duration remaining;
  final double progress;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      selected: selected,
      label: '${face.label} clock, ${face.blurb}',
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        scale: 0.98,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : Motion.base,
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(Gap.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.card),
            color: selected
                ? t.primary.withValues(alpha: 0.10)
                : t.surfaceContainerLow,
            border: Border.all(
              color: selected ? t.primary : t.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The preview sits on its own surface so a face that paints a
              // card of its own — the flip board — is still visible as a shape
              // rather than dissolving into the row behind it.
              Container(
                height: face == ClockFace.retro ? 170 : 78,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.tile),
                  color: t.surfaceContainerHighest.withValues(alpha: 0.55),
                ),
                padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: ClockDisplay(
                    remaining: remaining,
                    face: face,
                    accent: t.primary,
                    height: face == ClockFace.retro ? 156 : 46,
                    progress: progress,
                  ),
                ),
              ),
              const SizedBox(height: Gap.md),
              Row(
                children: [
                  Icon(face.icon, size: 17, color: t.onSurfaceVariant),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(
                      face.label,
                      style: tt.titleSmall?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  // A check rather than a switch: the choice is one of seven,
                  // and a switch beside each of seven rows says six of them are
                  // off rather than that one of them is on.
                  AnimatedScale(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : Motion.base,
                    curve: Curves.easeOutBack,
                    scale: selected ? 1 : 0,
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 20,
                      color: t.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                face.blurb,
                style: tt.bodySmall?.copyWith(color: t.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
