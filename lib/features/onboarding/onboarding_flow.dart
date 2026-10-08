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

/// The first-run flow — screens 0 through 9 of the plan.
///
/// The router sends every un-onboarded user here and nothing else can, so this
/// widget owns the whole journey: splash, account, persona, profile, subjects,
/// blocks, goal, permissions, celebration — and, for a parent, the question
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
  static const _stepCount = 9;
  static const _authIndex = 1;

  /// The page that asks whose device this is.
  ///
  /// It stays in the [PageView] either way — the flow's indices are what the
  /// back button and the progress bar are built on — but it is only ever
  /// visited by a parent. A student setting up their own phone has nothing to
  /// answer here, and a question with one possible answer is a step that only
  /// costs time.
  static const _deviceIndex = 3;

  final _controller = PageController();
  int _index = 0;

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

  /// The page after [index], skipping the device question when the persona
  /// never asked for it.
  int _nextFrom(int index) {
    var next = index + 1;
    if (next == _deviceIndex && !_asksDevice) next++;
    return next;
  }

  /// The page before [index], skipping the same page on the way back. Without
  /// this the back button would walk a student into a question the flow chose
  /// not to ask them.
  int _previousFrom(int index) {
    var previous = index - 1;
    if (previous == _deviceIndex && !_asksDevice) previous--;
    return previous;
  }

  void _go(int index) {
    if (index < 0 || index >= _stepCount || index == _index) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(index);
      return;
    }
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  void _next() => _go(_nextFrom(_index));

  void _back() => _go(_previousFrom(_index));

  /// Leaves the persona step.
  ///
  /// Choosing anything but "Parent" answers the device question by itself —
  /// this is the user's own phone — so a parent answer left over from an
  /// earlier pass is cleared rather than carried into a flow that no longer
  /// shows the page that set it.
  void _afterPersona() {
    if (!_asksDevice && ref.read(userProvider).isGuardian) {
      unawaited(ref.read(userProvider.notifier).setGuardianMode(false));
    }
    _next();
  }

  void _afterSplash() {
    final signedIn = ref.read(authServiceProvider).signedIn;
    _go(signedIn ? _authIndex + 1 : _authIndex);
  }

  @override
  Widget build(BuildContext context) {
    // Watched rather than read: the persona decides whether the device page
    // is part of this run, so the progress bar has to follow the answer the
    // moment it changes.
    final asksDevice =
        ref.watch(userProvider.select((u) => u.persona)) == Persona.parent;
    // The header counts the pages the user will actually see. The splash is
    // not one of them, and neither is the device question when the persona
    // did not ask for it.
    final total = _stepCount - 1 - (asksDevice ? 0 : 1);
    final shown = asksDevice || _index <= _deviceIndex ? _index : _index - 1;

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
                    _FlowHeader(index: shown, total: total, onBack: _back),
                  Expanded(
                    child: PageView(
                      controller: _controller,
                      physics: const NeverScrollableScrollPhysics(),
                      onPageChanged: (index) => setState(() => _index = index),
                      children: [
                        SplashStep(onDone: _afterSplash),
                        AuthScreen(embedded: true, onAuthenticated: _next),
                        PersonaStep(onNext: _afterPersona),
                        DeviceStep(onNext: _next),
                        ProfileStep(onNext: _next),
                        SubjectsStep(onNext: _next),
                        GoalStep(onNext: _next),
                        PermissionsStep(onNext: _next),
                        const CompleteStep(),
                      ],
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
}

/// Back affordance plus a progress bar. The user should always know how much
/// setup is left — an open-ended onboarding is one people abandon.
class _FlowHeader extends StatelessWidget {
  const _FlowHeader({
    required this.index,
    required this.total,
    required this.onBack,
  });

  final int index;
  final int total;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

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
            child: Semantics(
              label: 'Setup progress',
              value: '${(index / total * 100).round()} percent',
              child: LinearProgressIndicator(
                value: index / total,
                color: cs.primary,
                backgroundColor: cs.surfaceContainerHighest,
                minHeight: 5,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
            ),
          ),
          const SizedBox(width: Gap.md),
          Text('$index/$total', style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}
