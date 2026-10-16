import '../../shared/widgets/glass_surface.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/study_providers.dart';
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

    return StepScaffold(
      title: "You're all set",
      eyebrow: 'READY TO FOCUS',
      subtitle: 'Your first session is ready.',
      primaryLabel: 'Open FocusForge',
      primaryBusy: _finishing,
      onPrimary: _finish,
      children: [
        ContentCard(
          child: Column(
            children: [
              ListTile(
                leading: IconBadge(
                  icon: persona.icon,
                  color: cs.primary,
                  size: 40,
                ),
                title: const Text('Profile'),
                subtitle: Text(persona.label),
              ),
              const Divider(height: 1, indent: 72),
              ListTile(
                leading: IconBadge(
                  icon: Icons.menu_book_outlined,
                  color: cs.primary,
                  size: 40,
                ),
                title: const Text('Subjects'),
                subtitle: Text('$subjectCount selected'),
              ),
              const Divider(height: 1, indent: 72),
              ListTile(
                leading: IconBadge(
                  icon: Icons.timer_outlined,
                  color: cs.primary,
                  size: 40,
                ),
                title: Text(preset.name),
                subtitle: Text(
                  '${preset.focus} min focus · ${preset.shortBreak} min break',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.lg),
        Text(
          'Start your session from Home. Adjust your plan anytime.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}
