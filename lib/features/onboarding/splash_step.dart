import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/widgets/app_mark.dart';

/// Screen 0 — the splash.
///
/// It is on screen for less than two seconds, so it does one job: put the mark
/// and the promise in front of the user while the app finds its footing. The
/// entrance gives the mark a brief settling motion before the account screen.
class SplashStep extends StatefulWidget {
  const SplashStep({super.key, required this.onDone});

  /// Fired once, after the entrance has had time to land.
  final VoidCallback onDone;

  /// A brief introduction before the first interactive screen.
  static const hold = Duration(milliseconds: 1100);

  @override
  State<SplashStep> createState() => _SplashStepState();
}

class _SplashStepState extends State<SplashStep> with TickerProviderStateMixin {
  Timer? _handoff;
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (!visible) {
      _handoff?.cancel();
      _handoff = null;
    } else {
      _handoff ??= Timer(SplashStep.hold, () {
        _handoff = null;
        if (mounted) widget.onDone();
      });
    }
    if (MediaQuery.disableAnimationsOf(context) || !visible) {
      _intro.value = 1;
    }
  }

  @override
  void dispose() {
    _handoff?.cancel();
    _intro.dispose();
    super.dispose();
  }

  Animation<double> _fade(double begin, double end) => CurvedAnimation(
    parent: _intro,
    curve: Interval(begin, end, curve: Curves.easeOutCubic),
  );

  @override
  Widget build(BuildContext context) {
    final logoScale = Tween<double>(
      begin: 0.8,
      end: 1,
    ).animate(CurvedAnimation(parent: _intro, curve: Curves.easeOutBack));

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.all(Gap.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FadeTransition(
                    opacity: _fade(0, 0.55),
                    child: ScaleTransition(
                      scale: logoScale,
                      // The app's own mark, not a stock glyph — the first thing the
                      // user sees should be the thing they tapped to get here.
                      child: const AppMark(
                        size: 108,
                        semanticLabel: 'FocusForge',
                      ),
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
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
