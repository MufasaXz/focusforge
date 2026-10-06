import '../../app/theme/app_theme.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/models/shield.dart';
import '../../core/providers/shield_providers.dart';
import '../../shared/widgets/glass_surface.dart';
import '../../shared/widgets/mesh_background.dart';

/// The 4-7-8 protocol, in one place.
class _Protocol {
  const _Protocol._();

  static const inhale = Duration(seconds: 4);
  static const hold = Duration(seconds: 7);
  static const exhale = Duration(seconds: 8);
  static const cycles = 3;

  static const cycle = Duration(seconds: 19);
  static const total = Duration(seconds: 57);

  /// The orb's resting and fully-inhaled scales.
  static const restScale = 0.62;
  static const fullScale = 1.0;
}

enum _Phase {
  inhale('Breathe in'),
  hold('Hold'),
  exhale('Breathe out'),
  complete('Well done');

  const _Phase(this.instruction);

  final String instruction;
}

/// One frame of the exercise, derived from the controller's clock.
///
/// Everything the screen shows — phase, orb scale, countdown, ring progress —
/// comes out of this single calculation. Keeping it derived rather than
/// stored is what guarantees the words and the animation can never disagree.
@immutable
class _Frame {
  const _Frame({
    required this.phase,
    required this.cycle,
    required this.scale,
    required this.remaining,
    required this.progress,
  });

  final _Phase phase;

  /// 1-based, for display.
  final int cycle;
  final double scale;
  final Duration remaining;

  /// 0..1 across the whole session.
  final double progress;

  static _Frame at(Duration elapsed) {
    final totalMs = _Protocol.total.inMilliseconds;
    final ms = elapsed.inMilliseconds.clamp(0, totalMs);
    final progress = ms / totalMs;
    final remaining = Duration(milliseconds: totalMs - ms);

    if (ms >= totalMs) {
      return _Frame(
        phase: _Phase.complete,
        cycle: _Protocol.cycles,
        scale: _Protocol.restScale,
        remaining: Duration.zero,
        progress: 1,
      );
    }

    final cycleMs = _Protocol.cycle.inMilliseconds;
    final cycle = ms ~/ cycleMs + 1;
    final inCycle = ms % cycleMs;
    final inhaleMs = _Protocol.inhale.inMilliseconds;
    final holdMs = _Protocol.hold.inMilliseconds;
    final exhaleMs = _Protocol.exhale.inMilliseconds;

    if (inCycle < inhaleMs) {
      final p = Curves.easeInOut.transform(inCycle / inhaleMs);
      return _Frame(
        phase: _Phase.inhale,
        cycle: cycle,
        scale: _mix(_Protocol.restScale, _Protocol.fullScale, p),
        remaining: remaining,
        progress: progress,
      );
    }
    if (inCycle < inhaleMs + holdMs) {
      final p = (inCycle - inhaleMs) / holdMs;
      // A slow swell rather than a dead stop — a motionless circle reads as
      // frozen, and a frozen circle is exactly when attention drifts.
      final pulse = math.sin(p * math.pi * 3) * 0.03;
      return _Frame(
        phase: _Phase.hold,
        cycle: cycle,
        scale: _Protocol.fullScale + pulse,
        remaining: remaining,
        progress: progress,
      );
    }
    final p = Curves.easeInOut.transform(
      (inCycle - inhaleMs - holdMs) / exhaleMs,
    );
    return _Frame(
      phase: _Phase.exhale,
      cycle: cycle,
      scale: _mix(_Protocol.fullScale, _Protocol.restScale, p),
      remaining: remaining,
      progress: progress,
    );
  }

  static double _mix(double a, double b, double t) => a + (b - a) * t;
}

/// The Deep Breath Gate — the pause between an impulse and the app.
///
/// Full-bleed on purpose: the route sits outside the shell, so there is no nav
/// bar to wander off into mid-exercise. The whole screen is one hand-driven
/// [AnimationController] running three 4-7-8 cycles; the phase, the orb scale
/// and the countdown are all derived from its clock rather than kept as
/// parallel timers, which is what stops them drifting apart.
///
/// Both exits record a [BreathEvent] before leaving. The decision is the data
/// — "how often did the pause actually change your mind" is the only number
/// that can tell whether this feature works.
class BreathGateScreen extends ConsumerStatefulWidget {
  const BreathGateScreen({super.key, required this.appName});

  final String appName;

  @override
  ConsumerState<BreathGateScreen> createState() => _BreathGateScreenState();
}

class _BreathGateScreenState extends ConsumerState<BreathGateScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _Protocol.total,
  );

  /// Guards the two exits: a double-tap must not log two decisions.
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish({required bool walkedAway}) async {
    if (_leaving) return;
    setState(() => _leaving = true);
    await ref
        .read(breathEventsProvider.notifier)
        .record(
          BreathEvent(
            appName: widget.appName,
            at: DateTime.now(),
            walkedAway: walkedAway,
          ),
        );
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      // Reached by deep link, so there is nothing to pop back to.
      context.go(AppRoutes.paths[AppRoutes.dashboard]!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: isDark
              ? Brightness.light
              : Brightness.dark,
        ),
        child: MeshBackground(
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // The orb is sized against the worst case — the completion
                    // panel — so it does not jump when the buttons appear. The
                    // scroll view is the safety net: a short or landscape
                    // viewport scrolls rather than overflowing.
                    final orbSize = (constraints.maxHeight * 0.34).clamp(
                      150.0,
                      300.0,
                    );
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            Gap.xl,
                            Gap.xl,
                            Gap.xl,
                            Gap.lg,
                          ),
                          child: AnimatedBuilder(
                            animation: _controller,
                            builder: (context, _) {
                              final elapsed = Duration(
                                milliseconds:
                                    (_controller.value *
                                            _Protocol.total.inMilliseconds)
                                        .round(),
                              );
                              final frame = _Frame.at(elapsed);
                              return Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  _GateHeader(appName: widget.appName),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: Gap.xxl,
                                    ),
                                    child: _BreathOrb(
                                      frame: frame,
                                      size: orbSize,
                                    ),
                                  ),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 320),
                                    switchInCurve: Curves.easeOutCubic,
                                    child: frame.phase == _Phase.complete
                                        ? _CompletionPanel(
                                            key: const ValueKey('complete'),
                                            onWalkAway: () =>
                                                _finish(walkedAway: true),
                                            onContinue: () =>
                                                _finish(walkedAway: false),
                                          )
                                        : _Countdown(
                                            key: const ValueKey('running'),
                                            frame: frame,
                                          ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GateHeader extends StatelessWidget {
  const _GateHeader({required this.appName});

  final String appName;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        GlassPill(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.md,
            vertical: Gap.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield_rounded, size: 14, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                'Deep Breath Gate',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.lg),
        Text(
          'You reached for $appName',
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Gap.xs),
        Text(
          'Three slow breaths before you decide.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _BreathOrb extends StatelessWidget {
  const _BreathOrb({required this.frame, required this.size});

  final _Frame frame;

  /// Edge of the square the orb and its progress ring live in.
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = switch (frame.phase) {
      _Phase.hold => cs.secondary,
      _Phase.complete => cs.tertiary,
      _ => cs.primary,
    };
    final orb = size * 0.74;
    final instructionSize = (size * 0.095).clamp(18.0, 28.0);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The halo follows the orb at a damped ratio, so the two layers move
          // against each other and the whole thing reads as depth rather than
          // one flat disc being resized.
          Transform.scale(
            scale: 1 + (frame.scale - _Protocol.restScale) * 0.22,
            child: Container(
              width: size * 0.92,
              height: size * 0.92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    color.withValues(alpha: 0.12),
                    color.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          CustomPaint(
            size: Size.square(size),
            painter: _ProgressRingPainter(
              progress: frame.progress,
              color: color,
              track: cs.surfaceContainerHighest,
            ),
          ),
          ExcludeSemantics(
            child: Transform.scale(
              scale: frame.scale,
              child: Container(
                width: orb,
                height: orb,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.35, -0.35),
                    radius: 0.95,
                    colors: [
                      color.withValues(alpha: 0.30),
                      color.withValues(alpha: 0.07),
                    ],
                  ),
                  border: Border.all(
                    color: color.withValues(alpha: 0.55),
                    width: 1.4,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.26),
                      blurRadius: 60,
                      spreadRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // The instruction sits in its own non-scaling layer: the type has to
          // stay put while the circle breathes around it, or reading it becomes
          // part of the effort.
          Semantics(
            liveRegion: true,
            label: frame.phase == _Phase.complete
                ? 'Session complete.'
                : '${frame.phase.instruction}. '
                      'Cycle ${frame.cycle} of ${_Protocol.cycles}.',
            child: ExcludeSemantics(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    frame.phase.instruction,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: instructionSize,
                    ),
                  ),
                  const SizedBox(height: Gap.xs),
                  Text(
                    'Cycle ${frame.cycle} / ${_Protocol.cycles}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  const _ProgressRingPainter({
    required this.progress,
    required this.color,
    required this.track,
  });

  final double progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 6;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = track;

    canvas.drawCircle(center, radius, stroke);
    if (progress <= 0) return;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      stroke..color = color,
    );
  }

  @override
  bool shouldRepaint(_ProgressRingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}

class _Countdown extends StatelessWidget {
  const _Countdown({super.key, required this.frame});

  final _Frame frame;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final remaining = frame.remaining;
    final label =
        '${remaining.inMinutes}:'
        '${(remaining.inSeconds % 60).toString().padLeft(2, '0')}';

    return Column(
      children: [
        Semantics(
          label: '${remaining.inSeconds} seconds left',
          child: ExcludeSemantics(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        const SizedBox(height: Gap.xs),
        Text('left in this session', style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _CompletionPanel extends StatelessWidget {
  const _CompletionPanel({
    super.key,
    required this.onWalkAway,
    required this.onContinue,
  });

  final VoidCallback onWalkAway;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Nicely done.',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Gap.xs),
        Text(
          'The urge usually passes in under a minute. Choose what happens '
          'next.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Gap.xl),
        _GateButton(
          label: 'Go back',
          icon: Icons.arrow_back_rounded,
          primary: true,
          onTap: onWalkAway,
        ),
        const SizedBox(height: Gap.md),
        _GateButton(
          label: 'Continue anyway',
          icon: Icons.arrow_forward_rounded,
          primary: false,
          onTap: onContinue,
        ),
      ],
    );
  }
}

/// Primary and ghost variants of the gate's action. The "continue" option is
/// deliberately quieter — it should be reachable without being inviting.
class _GateButton extends StatelessWidget {
  const _GateButton({
    required this.label,
    required this.icon,
    required this.primary,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Pressable(
          onTap: onTap,
          child: GlassPanel(
            radius: Radii.pill,
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.xl,
              vertical: Gap.lg,
            ),
            accent: primary ? cs.primary : null,
            glowStrength: primary ? 0.8 : 0,
            gradient: primary
                ? LinearGradient(
                    colors: [
                      cs.primary.withValues(alpha: 0.30),
                      cs.secondary.withValues(alpha: 0.18),
                    ],
                  )
                : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: primary ? cs.onSurface : cs.onSurfaceVariant,
                ),
                const SizedBox(width: Gap.sm),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: primary ? cs.onSurface : cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
