import '../../core/localization/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/providers/app_providers.dart';
import '../../core/models/user.dart';
import '../../core/providers/study_providers.dart';
import '../../shared/widgets/pressable.dart';
import 'widgets/clock_faces.dart';

/// Opens the clock full screen.
///
/// A pushed route rather than an overlay: the system back gesture has to close
/// it, and a route is what the navigator can pop.
Future<void> showFullscreenClock(BuildContext context) {
  final reduce = MediaQuery.disableAnimationsOf(context);
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: true,
      barrierColor: Colors.black,
      transitionDuration: reduce
          ? Duration.zero
          : const Duration(milliseconds: 320),
      reverseTransitionDuration: reduce
          ? Duration.zero
          : const Duration(milliseconds: 240),
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
///
/// The whole screen is the play/pause control, because a clock propped on a
/// desk is reached for with a fingertip, not aimed at. Leaving takes the close
/// button in the corner (or the system back gesture), so a tap meant to pause
/// can never throw the user out of the screen.
class FullscreenClock extends ConsumerStatefulWidget {
  const FullscreenClock({super.key});

  @override
  ConsumerState<FullscreenClock> createState() => _FullscreenClockState();
}

class _FullscreenClockState extends ConsumerState<FullscreenClock>
    with SingleTickerProviderStateMixin {
  /// The glyph that answers a tap: it grows out of the centre and fades.
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  bool _flashPlaying = false;

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
    _flash.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // An empty list is "no preference", which is where the rest of the app
    // leaves orientation — not portrait, and not a lock the user did not ask
    // for.
    SystemChrome.setPreferredOrientations(const []);
    super.dispose();
  }

  void _toggle() {
    final timer = ref.read(timerProvider.notifier);
    final willRun = !ref.read(timerProvider).running;
    timer.toggle();
    HapticFeedback.selectionClick();
    if (MediaQuery.disableAnimationsOf(context)) return;
    setState(() => _flashPlaying = willRun);
    _flash.forward(from: 0);
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final timer = ref.watch(timerProvider);
    final face = ref.watch(clockFaceProvider);
    final presets = ref.watch(presetsProvider);
    final preset = presets[timer.presetIndex.clamp(0, presets.length - 1)];
    final subject = ref
        .watch(subjectsProvider)
        .where((s) => s.id == timer.subjectId)
        .firstOrNull;

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = switch (timer.phase) {
      TimerPhase.focus => cs.primary,
      TimerPhase.shortBreak => cs.tertiary,
      TimerPhase.longBreak => cs.secondary,
    };
    // Pure black means pure black here too: this is the one screen that is
    // left on for an hour, and a tint over black is exactly what the setting
    // exists to avoid.
    final amoled =
        theme.brightness == Brightness.dark &&
        ref.watch(themeSettingsProvider).amoled;
    final reduce = MediaQuery.disableAnimationsOf(context);

    final size = MediaQuery.sizeOf(context);
    // Everything scales off the shorter side, so landscape is not a portrait
    // clock with the figures cropped off the top.
    final side = size.shortestSide;
    final landscape = size.width > size.height;

    // The session, drawn around the edge of the window: a line that starts at
    // the middle of the top edge and walks the boundary as the segment runs.
    // A focus fills it — by the end it has closed the loop — while a break
    // starts with the whole boundary lit and drains back into the start.
    final hiddenTime = timer.hidesDuration(preset);
    final boundary = hiddenTime
        ? 0.0
        : timer.phase.isBreak
        ? 1 - timer.progressFor(preset)
        : timer.progressFor(preset);
    final retro = face == ClockFace.retro;
    // A paused segment that has already begun resumes; one that has not
    // begun starts.
    final begun = timer.remaining < timer.plannedDuration(preset);
    final hint = timer.running
        ? context.tr("Tap anywhere to pause")
        : begun
        ? context.tr("Tap anywhere to resume")
        : context.tr("Tap anywhere to start");

    return Scaffold(
      backgroundColor: amoled ? const Color(0xFF000000) : cs.surface,
      body: Stack(
        children: [
          // A wash of the phase colour rather than a flat fill: the phase is
          // readable from across the room without a label. Skipped on a black
          // screen, where the wash is the thing the setting is about.
          if (!amoled)
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
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _BoundaryProgress(
                  progress: boundary,
                  color: accent,
                  track: cs.onSurface.withValues(alpha: 0.10),
                ),
              ),
            ),
          ),
          // The whole screen starts and pauses the clock.
          Positioned.fill(
            child: Semantics(
              button: true,
              label: hint,
              onTap: _toggle,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggle,
              ),
            ),
          ),
          SafeArea(
            child: IgnorePointer(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: landscape ? side * 0.08 : Gap.md,
                  vertical: Gap.lg,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    // The figures get the room: everything else on this
                    // screen is a caption. A paused clock dims, so the state
                    // reads from across the room too.
                    AnimatedOpacity(
                      opacity: !timer.running && begun && !hiddenTime ? 0.62 : 1,
                      duration: reduce ? Duration.zero : Motion.base,
                      child: SizedBox(
                        width: size.width,
                        height: retro
                            ? side * (landscape ? 0.80 : 0.96)
                            : side * (landscape ? 0.50 : 0.42),
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: hiddenTime
                              ? Text(
                                  context.tr("Time stays hidden"),
                                  style: theme.textTheme.headlineMedium
                                      ?.copyWith(color: accent),
                                )
                              : ClockDisplay(
                                  remaining: timer.remaining,
                                  face: face,
                                  accent: accent,
                                  height: side * 0.30,
                                  progress: timer.progressFor(preset),
                                  phaseLabel: timer.phase == TimerPhase.focus
                                      ? context.tr("FOCUS")
                                      : context.tr("BREAK"),
                                ),
                        ),
                      ),
                    ),
                    SizedBox(height: side * 0.05),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (timer.running || !begun)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accent,
                            ),
                          )
                        else
                          Icon(Icons.pause_rounded, size: 16, color: accent),
                        const SizedBox(width: Gap.sm),
                        Text(
                          context.tr(timer.phase.label),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: accent,
                            letterSpacing: 0.6,
                          ),
                        ),
                        // The subject when the block has one, and nothing
                        // when it does not.
                        if (subject != null) ...[
                          Text(
                            '  ·  ',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          Flexible(
                            child: Text(
                              subject.name,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (hiddenTime) ...[
                      const SizedBox(height: Gap.sm),
                      Text(
                        timer.running
                            ? context.tr("Stay with your subject")
                            : context.tr("Ready when you are"),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      hint,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // The answer to a tap: a play or pause glyph that grows out of the
          // centre and fades, so the tap is felt even before the dial moves.
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: AnimatedBuilder(
                  animation: _flash,
                  builder: (context, _) {
                    final t = _flash.value;
                    if (!_flash.isAnimating || t <= 0) {
                      return const SizedBox.shrink();
                    }
                    return Opacity(
                      opacity: (1 - Curves.easeInCubic.transform(t)) * .92,
                      child: Transform.scale(
                        scale: 0.86 + 0.34 * Curves.easeOutCubic.transform(t),
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: cs.surfaceContainerHighest.withValues(
                              alpha: .86,
                            ),
                          ),
                          child: Icon(
                            _flashPlaying
                                ? Icons.play_arrow_rounded
                                : Icons.pause_rounded,
                            size: 48,
                            color: accent,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: AlignmentDirectional.topEnd,
              child: Padding(
                padding: const EdgeInsets.all(Gap.sm),
                child: Semantics(
                  button: true,
                  label: context.tr("Close the full-screen clock"),
                  onTap: _close,
                  child: ExcludeSemantics(
                    child: Pressable(
                      scale: 0.88,
                      onTap: _close,
                      child: SizedBox.square(
                        dimension: 48,
                        child: Center(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cs.surfaceContainerHigh.withValues(
                                alpha: .9,
                              ),
                              border: Border.all(
                                color: cs.outlineVariant.withValues(alpha: .6),
                              ),
                            ),
                            child: SizedBox.square(
                              dimension: 40,
                              child: Icon(
                                Icons.close_fullscreen_rounded,
                                size: 20,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
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

/// The segment, drawn around the window's own edge.
///
/// The run starts at the middle of the top edge and travels clockwise, so the
/// covered length is a distance the eye can read without a number: at the end
/// of a focus the line has met its own start, and a break begins with the
/// boundary whole and gives it back.
///
/// The path is built from that start point rather than from a rounded
/// rectangle: `addRRect` begins at the bottom-left corner, and a slice of its
/// metric measured from anywhere else would have to carry the distance between
/// the two. Walking the corners by hand means offset zero *is* the start.
class _BoundaryProgress extends CustomPainter {
  const _BoundaryProgress({
    required this.progress,
    required this.color,
    required this.track,
  });

  /// 0 to 1 of the boundary that is covered.
  final double progress;
  final Color color;
  final Color track;

  /// The line's distance from the window edge, and the radius of the corners
  /// it turns. A hairline at the very edge is half off the glass on a phone
  /// with rounded corners.
  static const _inset = 10.0;
  static const _radius = 26.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      _inset,
      _inset,
      size.width - _inset * 2,
      size.height - _inset * 2,
    );
    if (rect.width <= 0 || rect.height <= 0) return;

    const radius = Radius.circular(_radius);
    final path = Path()
      ..moveTo(rect.center.dx, rect.top)
      ..lineTo(rect.right - _radius, rect.top)
      ..arcToPoint(Offset(rect.right, rect.top + _radius), radius: radius)
      ..lineTo(rect.right, rect.bottom - _radius)
      ..arcToPoint(Offset(rect.right - _radius, rect.bottom), radius: radius)
      ..lineTo(rect.left + _radius, rect.bottom)
      ..arcToPoint(Offset(rect.left, rect.bottom - _radius), radius: radius)
      ..lineTo(rect.left, rect.top + _radius)
      ..arcToPoint(Offset(rect.left + _radius, rect.top), radius: radius)
      ..lineTo(rect.center.dx, rect.top);
    final metric = path.computeMetrics().first;

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = track,
    );

    final covered = metric.length * progress.clamp(0.0, 1.0);
    if (covered <= 0) return;

    canvas.drawPath(
      metric.extractPath(0, covered),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_BoundaryProgress old) =>
      old.progress != progress || old.color != color || old.track != track;
}
