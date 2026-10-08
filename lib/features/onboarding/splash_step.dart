import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/widgets/app_mark.dart';

/// Screen 0 — the splash.
///
/// It is on screen for less than two seconds, so it does one job: put the mark
/// and the promise in front of the user while the app finds its footing. The
/// mesh canvas is supplied by [OnboardingFlow]; this step only owns the
/// entrance — logo scaling up from 0.8, tagline 400ms behind it, and a row of
/// dots so the pause reads as loading rather than a frozen frame.
class SplashStep extends StatefulWidget {
  const SplashStep({super.key, required this.onDone});

  /// Fired once, after the entrance has had time to land.
  final VoidCallback onDone;

  /// How long the splash holds before handing over. The plan says two seconds;
  /// this is slightly under so the first interactive screen arrives sooner.
  static const hold = Duration(milliseconds: 1600);

  @override
  State<SplashStep> createState() => _SplashStepState();
}

class _SplashStepState extends State<SplashStep> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();

  late final AnimationController _dots = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1;
      _dots.stop();
      _dots.value = 0.5;
    } else if (!_dots.isAnimating) {
      _dots.repeat();
    }
  }

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(SplashStep.hold, () {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _dots.dispose();
    super.dispose();
  }

  Animation<double> _fade(double begin, double end) => CurvedAnimation(
    parent: _intro,
    curve: Interval(begin, end, curve: Curves.easeOutCubic),
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final logoScale = Tween<double>(
      begin: 0.8,
      end: 1,
    ).animate(CurvedAnimation(parent: _intro, curve: Curves.easeOutBack));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
      child: Column(
        children: [
          const Spacer(flex: 3),
          FadeTransition(
            opacity: _fade(0, 0.55),
            child: ScaleTransition(
              scale: logoScale,
              // The app's own mark, not a stock glyph — the first thing the
              // user sees should be the thing they tapped to get here.
              child: const AppMark(size: 108, semanticLabel: 'FocusForge'),
            ),
          ),
          const SizedBox(height: Gap.xl),
          FadeTransition(
            opacity: _fade(0.15, 0.7),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'FocusForge',
                style: Theme.of(context).textTheme.displayLarge,
              ),
            ),
          ),
          const SizedBox(height: Gap.sm),
          FadeTransition(
            opacity: _fade(0.4, 1),
            child: Text(
              'Forge your focus',
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          const Spacer(flex: 2),
          FadeTransition(opacity: _fade(0.6, 1), child: _loadingDots(context)),
          const Spacer(flex: 1),
        ],
      ),
    );
  }

  Widget _loadingDots(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Starting up',
      child: AnimatedBuilder(
        animation: _dots,
        builder: (context, _) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.primary.withValues(
                      // A travelling wave, so the three read as one animation
                      // rather than three independent blinks.
                      alpha: 0.25 + 0.75 * _wave(i),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  double _wave(int index) {
    final phase = (_dots.value + index / 3) % 1;
    return math.sin(phase * math.pi);
  }
}
