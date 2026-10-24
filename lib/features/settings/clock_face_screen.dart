import '../../core/localization/app_strings.dart';

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

    final remaining = timer.hidesDuration(preset)
        ? const Duration(minutes: 25)
        : timer.remaining;
    final progress =
        timer.hidesDuration(preset) ? 0.0 : timer.progressFor(preset);

    return AppPage(
      title: context.tr("Clock face"),
      subtitle: context.tr("How the timer draws its figures"),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The choice, shown large: the selected face at the size it will
          // actually be read, so the pick is made on the figure itself rather
          // than on a thumbnail that could be any of them.
          _FeaturedFace(
            face: selected,
            remaining: remaining,
            progress: progress,
          ),
          const SizedBox(height: Gap.xl),
          // The seven faces in a two-column grid — each one a live preview of
          // the same clock, not a sample number.
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - Gap.md) / 2;
              return Wrap(
                spacing: Gap.md,
                runSpacing: Gap.md,
                children: [
                  for (final face in ClockFace.values)
                    SizedBox(
                      width: width,
                      child: _FaceCard(
                        face: face,
                        remaining: remaining,
                        progress: progress,
                        selected: face == selected,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          ref.read(clockFaceProvider.notifier).set(face);
                        },
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: Gap.lg),
          Text(
            context.tr(
              "The face changes how the figures are drawn, not what they say. The timer, the ring and the full-screen clock all read the same value.",
            ),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// The selected face, shown at reading size in a tinted hero panel.
///
/// The grid below is for picking; this panel is for seeing. Showing the chosen
/// face large — with its name underneath — turns the screen into a preview
/// first and a list second, which is the order someone choosing a clock
/// thinks in.
class _FeaturedFace extends StatelessWidget {
  const _FeaturedFace({
    required this.face,
    required this.remaining,
    required this.progress,
  });

  final ClockFace face;
  final Duration remaining;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedContainer(
      duration:
          MediaQuery.disableAnimationsOf(context) ? Duration.zero : Motion.base,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.hero),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              cs.primary.withValues(alpha: dark ? 0.16 : 0.10),
              cs.surfaceContainerLow,
            ),
            cs.surfaceContainerLow,
          ],
        ),
        border: Border.all(color: cs.primary.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.symmetric(vertical: Gap.xl, horizontal: Gap.lg),
      child: Column(
        children: [
          SizedBox(
            height: face == ClockFace.retro ? 190 : 120,
            child: Center(
              child: AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : Motion.base,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
                    child: child,
                  ),
                ),
                // Keyed on the face so the preview crossfades between faces
                // rather than rebuilding the same widget in place.
                child: FittedBox(
                  key: ValueKey(face),
                  fit: BoxFit.scaleDown,
                  child: ClockDisplay(
                    remaining: remaining,
                    face: face,
                    accent: cs.primary,
                    height: face == ClockFace.retro ? 168 : 88,
                    progress: progress,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: Gap.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(face.icon, size: 16, color: cs.primary),
              const SizedBox(width: Gap.sm),
              Text(
                context.tr(face.label),
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            context.tr(face.blurb),
            textAlign: TextAlign.center,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// One face in the picker: a live thumbnail, its name, and whether it is on.
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
      label: context.tr("{0} clock, {1}", [
        context.tr(face.label),
        context.tr(face.blurb),
      ]),
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        key: ValueKey('clock-face-${face.name}'),
        onTap: onTap,
        scale: 0.97,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : Motion.base,
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(Gap.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.card),
            color: selected
                ? t.primary.withValues(alpha: 0.12)
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
                height: face == ClockFace.retro ? 92 : 62,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.tile),
                  color: t.surfaceContainerHighest.withValues(alpha: 0.55),
                ),
                padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: ClockDisplay(
                    remaining: remaining,
                    face: face,
                    accent: t.primary,
                    height: face == ClockFace.retro ? 84 : 36,
                    progress: progress,
                  ),
                ),
              ),
              const SizedBox(height: Gap.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.tr(face.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleSmall?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  AnimatedScale(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : Motion.base,
                    curve: Curves.easeOutBack,
                    scale: selected ? 1 : 0,
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 19,
                      color: t.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
