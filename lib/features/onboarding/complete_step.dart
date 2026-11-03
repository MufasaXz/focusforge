import '../../core/localization/display_labels.dart';
import '../../core/localization/app_strings.dart';
import '../../shared/widgets/glass_surface.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/study_providers.dart';
import '../../core/providers/usage_providers.dart';
import '../../shared/widgets/confetti_burst.dart';
import '../../shared/widgets/icon_badge.dart';
import 'onboarding_chrome.dart';

/// Screen 8 — the celebration, and the end of the flow.
///
/// It reflects the user's own choices back at them — persona, subjects and blocks — because the fastest way to make a setup feel worth it is to show
/// that it actually configured something. The final action
/// flips the onboarding flag and hands over to the dashboard, which is what
/// the router has been waiting for.
class CompleteStep extends ConsumerStatefulWidget {
  const CompleteStep({super.key});

  @override
  ConsumerState<CompleteStep> createState() => _CompleteStepState();
}

class _CompleteStepState extends ConsumerState<CompleteStep> {
  bool _finishing = false;
  bool _celebrated = false;
  Timer? _celebration;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled ||
        MediaQuery.disableAnimationsOf(context)) {
      _celebration?.cancel();
      _celebration = null;
      return;
    }
    if (_celebrated || _celebration != null) return;
    _celebration = Timer(const Duration(milliseconds: 560), () {
      if (!mounted) return;
      _celebrated = true;
      ConfettiBurst.fire(context);
    });
  }

  @override
  void dispose() {
    _celebration?.cancel();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      await ref.read(userProvider.notifier).completeOnboarding();
    } catch (_) {
      if (mounted) setState(() => _finishing = false);
      rethrow;
    }
    if (!mounted) return;
    context.go(AppRoutes.paths[AppRoutes.dashboard]!);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = ref.watch(userProvider);
    final persona = user.persona;
    final subjectCount = ref.watch(subjectsProvider).length;
    // The preset the timer will actually start with, not a claim about the
    // shield: apps are chosen in the Shield tab now, so a count here would be
    // a zero dressed up as a fact.
    final plans = ref.watch(presetsProvider);
    final preset =
        plans[ref.watch(timerProvider).presetIndex.clamp(0, plans.length - 1)];
    // Said as it is: agreeing to the app list is not the same as a Shield
    // that is running, so the row never claims more than the agreement.
    final appList = ref.watch(appListConsentProvider);

    return StepScaffold(
      title: context.tr("You're all set"),
      eyebrow: context.tr("READY TO FOCUS"),
      subtitle: context.tr("Your first session is ready."),
      primaryLabel: context.tr("Open FocusForge"),
      primaryBusy: _finishing,
      onPrimary: _finish,
      children: [
        const _ReadyMark(),
        const SizedBox(height: Gap.xl),
        ContentCard(
          child: Column(
            children: [
              ListTile(
                leading: IconBadge(
                  icon: persona.icon,
                  color: cs.primary,
                  size: 40,
                ),
                title: Text(context.tr("Profile")),
                subtitle: Text(context.tr(persona.label)),
              ),
              const Divider(height: 1, indent: 72),
              ListTile(
                leading: IconBadge(
                  icon: Icons.menu_book_outlined,
                  color: cs.primary,
                  size: 40,
                ),
                title: Text(context.tr("Subjects")),
                subtitle: Text(context.tr("{0} selected", [subjectCount])),
              ),
              const Divider(height: 1, indent: 72),
              ListTile(
                leading: IconBadge(
                  icon: Icons.timer_outlined,
                  color: cs.primary,
                  size: 40,
                ),
                title: Text(presetDisplayName(context, preset)),
                subtitle: Text(
                  context.tr("{0} min focus · {1} min break", [
                    preset.focus,
                    preset.shortBreak,
                  ]),
                ),
              ),
              const Divider(height: 1, indent: 72),
              ListTile(
                leading: IconBadge(
                  icon: Icons.shield_outlined,
                  color: appList ? cs.tertiary : cs.onSurfaceVariant,
                  size: 40,
                ),
                title: Text(context.tr("Shield")),
                subtitle: Text(
                  appList
                      ? context.tr("App list allowed · stays on this phone")
                      : context.tr("Set up anytime in the Shield tab"),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.lg),
        Text(
          context.tr("Start your session from Home. Adjust your plan anytime."),
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// The finish line, drawn: a check inside two soft rings. It settles in once
/// and stays still, so it reads as done rather than as something loading.
class _ReadyMark extends StatelessWidget {
  const _ReadyMark();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: reduce ? 1 : .7, end: 1),
          duration: reduce ? Duration.zero : const Duration(milliseconds: 520),
          curve: Curves.easeOutBack,
          builder: (context, t, child) =>
              Transform.scale(scale: t, child: child),
          child: Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primary.withValues(alpha: .08),
            ),
            alignment: Alignment.center,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.primary.withValues(alpha: .16),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary,
                ),
                child: Icon(Icons.check_rounded, size: 30, color: cs.onPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
