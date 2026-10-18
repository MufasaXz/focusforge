import '../../core/localization/app_strings.dart';

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
                  const SizedBox(height: Gap.md),
                  // The promise, arriving after the mark has settled — the last
                  // thing to fade in is the thing the next screen has to keep.
                  const SizedBox(height: Gap.md),
                  // A compact promise row gives the first frame a useful
                  // answer to “why this app?” without delaying the handoff.
                  FadeTransition(
                    opacity: _fade(0.45, 0.95),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: Gap.sm,
                      runSpacing: Gap.xs,
                      children: [
                        _PromiseChip(
                          icon: Icons.timer_outlined,
                          label: context.tr("Focus time"),
                        ),
                        _PromiseChip(
                          icon: Icons.shield_outlined,
                          label: context.tr("Fewer distractions"),
                        ),
                      ],
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

class _PromiseChip extends StatelessWidget {
  const _PromiseChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .6)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.md,
          vertical: Gap.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: cs.primary),
            const SizedBox(width: Gap.xs),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}
