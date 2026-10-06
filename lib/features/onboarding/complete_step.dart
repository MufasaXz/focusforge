import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/study_providers.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/confetti_burst.dart';
import '../../shared/widgets/glass_surface.dart';
import '../../shared/widgets/stagger.dart';
import 'onboarding_chrome.dart';
import 'onboarding_state.dart';

/// Screen 8 — the celebration, and the end of the flow.
///
/// It reflects the user's own choices back at them — persona, subjects, blocks,
/// goal — because the fastest way to make a setup feel worth it is to show
/// that it actually configured something. "Let's Go" is the only action: it
/// flips the onboarding flag and hands over to the dashboard, which is what
/// the router has been waiting for.
class CompleteStep extends ConsumerStatefulWidget {
  const CompleteStep({super.key});

  @override
  ConsumerState<CompleteStep> createState() => _CompleteStepState();
}

class _CompleteStepState extends ConsumerState<CompleteStep> {
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    // A beat after the page settles — firing during the page transition makes
    // the burst look like it belongs to the previous screen.
    Future<void>.delayed(const Duration(milliseconds: 450), () {
      if (mounted) ConfettiBurst.fire(context);
    });
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    await ref.read(userProvider.notifier).completeOnboarding();
    if (!mounted) return;
    context.go(AppRoutes.paths[AppRoutes.dashboard]!);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final persona = ref.watch(userProvider).persona;
    final subjectCount = ref.watch(subjectsProvider).length;
    final blockedCount = ref.watch(blockedAppsProvider).length;
    final goal = ref.watch(dailyGoalProvider);

    return StepScaffold(
      title: "You're all set",
      subtitle: 'Here is what FocusForge will do for you.',
      primaryLabel: "Let's Go",
      primaryBusy: _finishing,
      onPrimary: _finish,
      children: [
        Stagger(
          index: 2,
          child: Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: persona.icon,
                  color: persona.color,
                  value: persona.label,
                  label: 'Profile',
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: _StatTile(
                  icon: Icons.menu_book_rounded,
                  color: cs.secondary,
                  value: '$subjectCount',
                  label: subjectCount == 1 ? 'Subject' : 'Subjects',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.sm),
        Stagger(
          index: 3,
          child: Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.shield_rounded,
                  color: cs.tertiary,
                  value: '$blockedCount',
                  label: 'Apps blocked',
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: _StatTile(
                  icon: Icons.timer_rounded,
                  color: cs.tertiary,
                  value: formatMinutes(goal),
                  label: 'Daily goal',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.xl),
        const Stagger(index: 4, child: SectionHeader(title: 'Quick tips')),
        Stagger(
          index: 5,
          child: GlassPanel(
            radius: Radii.card,
            padding: const EdgeInsets.symmetric(vertical: Gap.xs),
            child: const Column(
              children: [
                _Tip(
                  icon: Icons.timer_rounded,
                  text: 'Tap Focus to start your first session.',
                ),
                _Tip(
                  icon: Icons.insights_rounded,
                  text: 'The dashboard fills in as you study.',
                  divider: true,
                ),
                _Tip(
                  icon: Icons.shield_rounded,
                  text: 'Tune what gets blocked in the Shield tab.',
                  divider: true,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GlassPanel(
      level: 2,
      radius: Radii.item,
      sheen: false,
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassIconBadge(
            icon: icon,
            color: color,
            size: 34,
            radius: Radii.tile,
          ),
          const SizedBox(height: Gap.md),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(letterSpacing: -0.4),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip({required this.icon, required this.text, this.divider = false});

  final IconData icon;
  final String text;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        if (divider)
          Padding(
            padding: const EdgeInsets.only(left: Gap.md + 19 + Gap.md),
            child: Divider(height: 1, thickness: 1, color: cs.outlineVariant),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.md,
            vertical: Gap.md,
          ),
          child: Row(
            children: [
              Icon(icon, size: 19, color: cs.primary),
              const SizedBox(width: Gap.md),
              Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
            ],
          ),
        ),
      ],
    );
  }
}
