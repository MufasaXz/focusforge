import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/user.dart';
import '../../core/providers/app_providers.dart';
import 'auth_screen.dart';
import 'complete_step.dart';
import 'device_step.dart';
import 'goal_step.dart';
import 'permissions_step.dart';
import 'persona_step.dart';
import 'profile_step.dart';
import 'splash_step.dart';
import 'subjects_step.dart';

/// First-run setup, with only the steps needed by this device.
///
/// The router sends every un-onboarded user here and nothing else can, so this
/// widget owns the whole journey: splash, account, persona, profile, subjects,
/// goal, permissions, celebration — and, for a parent, the question
/// about whose device this is. The last step flips `completeOnboarding()` and
/// the router takes it from there.
///
/// A [PageView] rather than an [AnimatedSwitcher] because it keeps each step
/// alive while the user moves back and forth: returning to the subject picker
/// should show the same selection, not a fresh screen. Swiping is disabled —
/// the flow has an explicit back affordance and a primary action, and letting
/// a drag skip the account step would be a trap.
class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key});

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  static const _authIndex = 1;

  /// A parent chooses between studying here and managing a child's phone.
  static const _deviceIndex = 3;

  final _controller = PageController();
  int _index = 0;
  bool _moving = false;

  @override
  void initState() {
    super.initState();
    // A user who quit mid-flow already has an account. Restoring it lets the
    // splash skip the auth step instead of asking a second time.
    unawaited(ref.read(authServiceProvider).restore());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Whether this run asks the device question at all.
  bool get _asksDevice => ref.read(userProvider).persona == Persona.parent;

  List<int> get _steps {
    final user = ref.read(userProvider);
    final guardian = user.persona == Persona.parent && user.isGuardian;
    return [
      0,
      1,
      2,
      if (_asksDevice) _deviceIndex,
      4,
      if (!guardian) ...[5, 6, 7],
      8,
    ];
  }

  Future<void> _go(int step) async {
    final page = _steps.indexOf(step);
    if (_moving || page < 0 || step == _index || !_controller.hasClients) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    _moving = true;
    try {
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.jumpToPage(page);
      } else {
        await _controller.animateToPage(
          page,
          duration: const Duration(milliseconds: 300),
          curve: Motion.emphasized,
        );
      }
    } finally {
      _moving = false;
    }
  }

  void _next() {
    final steps = _steps;
    final next = steps.indexOf(_index) + 1;
    if (next < steps.length) unawaited(_go(steps[next]));
  }

  void _advanceFrom(int step) {
    // A save may finish after Back. It may persist the draft, but it must
    // not advance whichever step is visible now.
    if (_index == step) _next();
  }

  void _back() {
    final steps = _steps;
    final previous = steps.indexOf(_index) - 1;
    if (previous >= 0) unawaited(_go(steps[previous]));
  }

  /// Leaves the persona step.
  ///
  /// Choosing anything but "Parent" answers the device question by itself —
  /// this is the user's own phone — so a parent answer left over from an
  /// earlier pass is cleared rather than carried into a flow that no longer
  /// shows the page that set it.
  void _afterPersona() {
    if (_index != 2) return;
    if (!_asksDevice && ref.read(userProvider).isGuardian) {
      unawaited(ref.read(userProvider.notifier).setGuardianMode(false));
    }
    _next();
  }

  void _afterSplash() {
    if (_index != 0) return;
    final signedIn = ref.read(authServiceProvider).signedIn;
    unawaited(_go(signedIn ? _authIndex + 1 : _authIndex));
  }

  @override
  Widget build(BuildContext context) {
    // Watched rather than read: the persona decides whether the device page
    // is part of this run, so the progress bar has to follow the answer the
    // moment it changes.
    ref.watch(userProvider.select((u) => (u.persona, u.isGuardian)));
    final steps = _steps;
    final total = steps.length - 1;
    final shown = steps.indexOf(_index);

    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                children: [
                  if (_index > 0)
                    _FlowHeader(
                      index: shown,
                      total: total,
                      title: _stageName(_index),
                      onBack: _back,
                    ),
                  Expanded(
                    child: PageView.builder(
                      controller: _controller,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: steps.length,
                      findChildIndexCallback: (key) {
                        final step = (key as ValueKey<int>).value;
                        final index = steps.indexOf(step);
                        return index < 0 ? null : index;
                      },
                      onPageChanged: (page) =>
                          setState(() => _index = steps[page]),
                      itemBuilder: (context, page) {
                        final step = steps[page];
                        return _KeepStep(
                          key: ValueKey(step),
                          child: TickerMode(
                            enabled: _index == step,
                            child: _buildStep(step),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(int step) => switch (step) {
    0 => SplashStep(onDone: _afterSplash),
    1 => AuthScreen(embedded: true, onAuthenticated: () => _advanceFrom(1)),
    2 => PersonaStep(onNext: _afterPersona),
    3 => DeviceStep(onNext: () => _advanceFrom(3)),
    4 => ProfileStep(onNext: () => _advanceFrom(4)),
    // Rebuild persona-specific recommendations when that answer changes.
    5 => SubjectsStep(
      key: ValueKey(ref.read(userProvider).persona),
      onNext: () => _advanceFrom(5),
    ),
    6 => GoalStep(
      key: ValueKey(ref.read(userProvider).persona),
      onNext: () => _advanceFrom(6),
    ),
    7 => PermissionsStep(onNext: () => _advanceFrom(7)),
    _ => const CompleteStep(),
  };

  static String _stageName(int step) => const [
    'Welcome',
    'Account',
    'Your focus',
    'This device',
    'Profile',
    'Subjects',
    'Daily goal',
    'Permissions',
    'Ready',
  ][step];
}

class _KeepStep extends StatefulWidget {
  const _KeepStep({super.key, required this.child});
  final Widget child;

  @override
  State<_KeepStep> createState() => _KeepStepState();
}

class _KeepStepState extends State<_KeepStep>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Back affordance plus a progress bar. The user should always know how much
/// setup is left — an open-ended onboarding is one people abandon.
class _FlowHeader extends StatelessWidget {
  const _FlowHeader({
    required this.index,
    required this.total,
    required this.title,
    required this.onBack,
  });

  final int index;
  final int total;
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final reduce = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.sm, Gap.lg, Gap.sm),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title, style: theme.textTheme.labelMedium),
                    ),
                    Text('$index of $total', style: theme.textTheme.labelSmall),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                Semantics(
                  label: 'Setup progress, $title',
                  value: 'Step $index of $total',
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: index / total),
                    duration: reduce ? Duration.zero : Motion.base,
                    curve: Motion.decelerate,
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      color: cs.primary,
                      backgroundColor: cs.surfaceContainerHighest,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
