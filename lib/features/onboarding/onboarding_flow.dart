import '../../core/localization/app_strings.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/providers/app_providers.dart';
import '../../core/services/local_store.dart';
import 'auth_screen.dart';
import 'onboarding_chrome.dart';
import 'complete_step.dart';
import 'starting_plan_step.dart';
import 'persona_step.dart';
import 'profile_step.dart';
import 'splash_step.dart';
import 'subjects_step.dart';
import 'usage_access_step.dart';

/// First-run setup, with only the steps needed by this device.
///
/// The router sends every un-onboarded user here and nothing else can, so this
/// widget owns the whole journey: splash, account, persona, profile, subjects,
/// starting plan and celebration. The last step flips `completeOnboarding()` and
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

  // Usage Access is the final optional setup choice, immediately before the
  // completion handoff. Keeping the starting pace before it means Back from
  // that screen still returns to Subjects as it did in the original flow.
  List<int> get _steps => const [0, 1, 2, 4, 5, 7, 6, 8];

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
          if (step == 6) 'flow': 'usage_access',
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
        showAppSnack(
          context,
          tr("Could not save your setup progress. Try again."),
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
    // Drafts saved on the retired goal screen return to subjects.
    final storedStep = progress?['step'];
    final step = storedStep == 6 && progress?['flow'] != 'usage_access'
        ? 5
        : storedStep;
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
    // Refresh subject suggestions after the persona answer changes.
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
    6 => UsageAccessStep(onNext: () => _advanceFrom(6)),
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
    'Access',
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
            tooltip: context.tr("Back"),
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
                      child: Text(
                        title,
                        style: theme.textTheme.labelLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: Gap.sm),
                    Text(
                      context.tr("Step {0} of {1}", [index, total]),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                    ),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                Semantics(
                  label: context.tr("Setup progress, {0}", [title]),
                  value: context.tr("Step {0} of {1}", [index, total]),
                  child: ExcludeSemantics(
                    child: _StepTrack(index: index, total: total),
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

/// The setup progress as a journey rather than a fill: a thin rail with one
/// dot per step and the current step stretched into a pill that travels along
/// it. Done steps keep a filled dot; coming steps are outlines. The travel is
/// an implicit animation, so a back-tap rewinds the pill instead of jumping.
class _StepTrack extends StatelessWidget {
  const _StepTrack({required this.index, required this.total});

  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final count = total + 1;

    return SizedBox(
      height: 14,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          // The dots and the travelling pill must never run off the track. On
          // very narrow widths or large text the available width shrinks, so
          // the dots are inset by a fixed margin and the spacing is derived
          // from that inset span rather than the raw width — otherwise the
          // first and last dots, and the pill over them, bleed past the edge.
          const edgeInset = 6.0;
          final span = (w - edgeInset * 2).clamp(0.0, w);
          final gap = count <= 1 ? 0.0 : span / (count - 1);
          double x(int i) => edgeInset + i * gap;
          final pillW = (gap).clamp(14.0, 30.0);
          final pillLeft = (x(index) - pillW / 2).clamp(0.0, (w - pillW).clamp(0.0, w));

          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              // rail
              Positioned(
                left: 0,
                right: 0,
                top: 6,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // done portion of the rail
              Positioned(
                left: 0,
                top: 6,
                child: AnimatedContainer(
                  duration: reduce ? Duration.zero : Motion.base,
                  curve: Motion.emphasized,
                  width: x(index),
                  height: 2,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: .65),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // step dots
              for (var i = 0; i < count; i++)
                Positioned(
                  left: x(i) - 4,
                  top: 3,
                  child: AnimatedContainer(
                    duration: reduce ? Duration.zero : Motion.base,
                    curve: Motion.emphasized,
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < index
                          ? cs.primary
                          : i == index
                          ? cs.primary
                          : cs.surfaceContainerHighest,
                      border: i <= index
                          ? null
                          : Border.all(color: cs.outlineVariant),
                    ),
                  ),
                ),
              // the travelling current-step pill over the active dot
              AnimatedPositioned(
                duration: reduce ? Duration.zero : Motion.base,
                curve: Motion.emphasized,
                left: pillLeft,
                top: 0,
                child: AnimatedContainer(
                  duration: reduce ? Duration.zero : Motion.base,
                  curve: Motion.emphasized,
                  width: pillW,
                  height: 14,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(Radii.pill),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: .55),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
