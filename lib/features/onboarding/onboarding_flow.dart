import '../../app/theme/app_theme.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../shared/widgets/glass_surface.dart';
import '../../shared/widgets/glass_toggle.dart';
import '../../shared/widgets/mesh_background.dart';
import 'apps_step.dart';
import 'auth_screen.dart';
import 'complete_step.dart';
import 'goal_step.dart';
import 'permissions_step.dart';
import 'persona_step.dart';
import 'profile_step.dart';
import 'splash_step.dart';
import 'subjects_step.dart';

/// The first-run flow — screens 0 through 8 of the plan.
///
/// The router sends every un-onboarded user here and nothing else can, so this
/// widget owns the whole journey: splash, account, persona, profile, subjects,
/// blocks, goal, permissions, celebration. The last step flips
/// `completeOnboarding()` and the router takes it from there.
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

  void _go(int index) {
    if (index < 0 || index >= _stepCount || index == _index) return;
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  void _next() => _go(_index + 1);

  void _back() => _go(_index - 1);

  void _afterSplash() {
    final signedIn = ref.read(authServiceProvider).signedIn;
    _go(signedIn ? _authIndex + 1 : _authIndex);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: MeshBackground(
          child: SafeArea(
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  children: [
                    if (_index > 0)
                      _FlowHeader(
                        index: _index,
                        total: _stepCount - 1,
                        onBack: _back,
                      ),
                    Expanded(
                      child: PageView(
                        controller: _controller,
                        physics: const NeverScrollableScrollPhysics(),
                        onPageChanged: (index) =>
                            setState(() => _index = index),
                        children: [
                          SplashStep(onDone: _afterSplash),
                          AuthScreen(embedded: true, onAuthenticated: _next),
                          PersonaStep(onNext: _next),
                          ProfileStep(onNext: _next),
                          SubjectsStep(onNext: _next),
                          AppsStep(onNext: _next),
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
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.lg, Gap.sm),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Back',
            child: Pressable(
              onTap: onBack,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  Icons.arrow_back_rounded,
                  size: 20,
                  color: cs.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: GlassProgressBar(
              value: index / total,
              color: cs.primary,
              height: 4,
              semanticLabel: 'Setup progress',
            ),
          ),
          const SizedBox(width: Gap.md),
          Text('$index/$total', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
