import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/local_store.dart';
import 'auth_screen.dart';
import 'onboarding_chrome.dart';
import 'complete_step.dart';
import 'goal_step.dart';
import 'starting_plan_step.dart';
import 'persona_step.dart';
import 'profile_step.dart';
import 'splash_step.dart';
import 'subjects_step.dart';

/// First-run setup, with only the steps needed by this device.
///
/// The router sends every un-onboarded user here and nothing else can, so this
/// widget owns the whole journey: splash, account, persona, profile, subjects,
/// goal, starting plan and celebration. The last step flips `completeOnboarding()` and
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

  final _controller = PageController();
  int _index = 0;
  bool _moving = false;
  late final Future<void> _restoring;

  @override
  void initState() {
    super.initState();
    // A user who quit mid-flow already has an account. Restoring it lets the
    // splash skip the auth step instead of asking a second time.
    _restoring = _restoreAccount();
  }

  Future<void> _restoreAccount() async {
    try {
      final profile = await ref.read(authServiceProvider).restore();
      if (mounted && profile != null) {
        ref.read(userProvider.notifier).hydrate(profile);
      }
    } catch (_) {
      // Bootstrap already restored the local draft. An offline account
      // refresh must not stop the user from completing it.
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<int> get _steps => const [0, 1, 2, 4, 5, 6, 7, 8];

  Future<void> _go(int step) async {
    final page = _steps.indexOf(step);
    if (_moving || page < 0 || step == _index || !_controller.hasClients) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    _moving = true;
    try {
      if (step >= 2) {
        await ref.read(localStoreProvider).setMap(StoreKeys.setupProgress, {
          'uid': ref.read(userProvider).uid,
          'step': step,
        });
      }
      if (!mounted || !_controller.hasClients) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.jumpToPage(page);
      } else {
        await _controller.animateToPage(
          page,
          duration: const Duration(milliseconds: 300),
          curve: Motion.emphasized,
        );
      }
    } catch (_) {
      if (mounted) {
        showAppSnack(context, 'Could not save your setup progress. Try again.');
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

  void _afterPersona() {
    if (_index == 2) _next();
  }

  Future<void> _afterSplash() async {
    await _restoring;
    if (!mounted) return;
    if (_index != 0) return;
    final signedIn = ref.read(authServiceProvider).signedIn;
    await _go(signedIn ? _resumeStep() : _authIndex);
  }

  int _resumeStep() {
    final profile = ref.read(userProvider);
    final progress = ref
        .read(localStoreProvider)
        .getMap(StoreKeys.setupProgress);
    final step = progress?['step'];
    return !profile.onboardingComplete &&
            progress?['uid'] == profile.uid &&
            step is int &&
            step >= 2 &&
            _steps.contains(step)
        ? step
        : 2;
  }

  void _afterAuthentication() {
    if (_index == _authIndex) unawaited(_go(_resumeStep()));
  }

  @override
  Widget build(BuildContext context) {
    // Refresh subject and goal suggestions after the persona answer changes.
    ref.watch(userProvider.select((u) => u.persona));
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
              constraints: const BoxConstraints(maxWidth: 520),
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
    1 => AuthScreen(embedded: true, onAuthenticated: _afterAuthentication),
    2 => PersonaStep(onNext: _afterPersona),
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
    7 => StartingPlanStep(onNext: () => _advanceFrom(7)),
    _ => const CompleteStep(),
  };

  static String _stageName(int step) => const [
    'Welcome',
    'Account',
    'Your focus',
    '',
    'Profile',
    'Subjects',
    'Daily goal',
    'Starting plan',
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

/// Back affordance plus a per-stage stepper. The user should always know how
/// much setup is left — an open-ended onboarding is one people abandon.
///
/// A single progress track keeps the header quiet while stating the step.
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
                    // Tabular so the count never shifts width as it advances.
                    Text(
                      '$index of $total',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                Semantics(
                  label: 'Setup progress, $title',
                  value: 'Step $index of $total',
                  child: ExcludeSemantics(
                    child: LinearProgressIndicator(
                      value: index / total,
                      minHeight: 3,
                      borderRadius: BorderRadius.circular(Radii.pill),
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
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
