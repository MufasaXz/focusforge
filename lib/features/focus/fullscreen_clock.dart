import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/study_providers.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/pressable.dart';
import 'widgets/clock_faces.dart';

/// Opens the clock full screen.
///
/// A pushed route rather than an overlay: the system back gesture has to close
/// it, and a route is what the navigator can pop.
Future<void> showFullscreenClock(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: true,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => const FullscreenClock(),
      transitionsBuilder: (context, animation, _, child) {
        final t = Curves.easeOutCubic.transform(animation.value);
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: Opacity(opacity: 0.4 + 0.6 * t, child: child),
          ),
        );
      },
    ),
  );
}

/// The timer, the whole screen, either way up.
///
/// The layout is built from the shorter side of the window, so the same page
/// is a tall column in portrait and a wide one in landscape without a second
/// arrangement — and because the app pins no orientation of its own, turning
/// the device simply rebuilds it. Nothing here counts: the clock reads the
/// engine, so it cannot drift from the timer behind it.
class FullscreenClock extends ConsumerStatefulWidget {
  const FullscreenClock({super.key});

  @override
  ConsumerState<FullscreenClock> createState() => _FullscreenClockState();
}

class _FullscreenClockState extends ConsumerState<FullscreenClock> {
  @override
  void initState() {
    super.initState();
    // A clock on a desk is the one screen where the status bar is in the way,
    // and the one screen the user may well be holding sideways.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // An empty list is "no preference", which is where the rest of the app
    // leaves orientation — not portrait, and not a lock the user did not ask
    // for.
    SystemChrome.setPreferredOrientations(const []);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timer = ref.watch(timerProvider);
    final face = ref.watch(clockFaceProvider);
    final preset = ref.watch(presetsProvider)[timer.presetIndex];
    final subject = ref
        .watch(subjectsProvider)
        .where((s) => s.id == timer.subjectId)
        .firstOrNull;

    final cs = Theme.of(context).colorScheme;
    final accent = switch (timer.phase) {
      TimerPhase.focus => cs.primary,
      TimerPhase.shortBreak => cs.tertiary,
      TimerPhase.longBreak => cs.secondary,
    };

    final size = MediaQuery.sizeOf(context);
    // Everything scales off the shorter side, so landscape is not a portrait
    // clock with the figures cropped off the top.
    final side = size.shortestSide;
    final landscape = size.width > size.height;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Stack(
        children: [
          // A wash of the phase colour rather than a flat fill: the phase is
          // readable from across the room without a label.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.1,
                  colors: [accent.withValues(alpha: 0.16), cs.surface],
                ),
              ),
            ),
          ),
          // Tap anywhere to leave, the way a full-screen clock on a phone
          // works — the close button is there for anyone who does not know
          // that.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: landscape ? side * 0.10 : Gap.xl,
                vertical: Gap.lg,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  // The figures get the room: everything else on this screen
                  // is a caption.
                  SizedBox(
                    width: size.width,
                    height: side * (landscape ? 0.42 : 0.34),
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: ClockDisplay(
                        remaining: timer.remaining,
                        face: face,
                        accent: accent,
                        height: side * 0.30,
                        progress: timer.progressFor(preset),
                      ),
                    ),
                  ),
                  SizedBox(height: side * 0.05),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent,
                        ),
                      ),
                      const SizedBox(width: Gap.sm),
                      Text(
                        timer.phase.label,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(color: accent, letterSpacing: 0.6),
                      ),
                      if (subject != null) ...[
                        Text(
                          '  ·  ',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        Flexible(
                          child: Text(
                            subject.name,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: Gap.sm),
                  Text(
                    timer.running
                        ? 'Focusing — ${formatClock(timer.remaining)} left'
                        : 'Paused at ${formatClock(timer.remaining)}',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Text(
                    'Tap anywhere to close',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Semantics(
                button: true,
                label: 'Close the full-screen clock',
                onTap: () => Navigator.of(context).pop(),
                child: ExcludeSemantics(
                  child: Pressable(
                    scale: 0.85,
                    onTap: () => Navigator.of(context).pop(),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: Center(
                        child: Icon(
                          Icons.close_fullscreen_rounded,
                          size: 22,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
