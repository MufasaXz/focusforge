import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/study_providers.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/confetti_burst.dart';
import '../../shared/widgets/icon_badge.dart';
import '../../shared/widgets/stagger.dart';
import 'onboarding_chrome.dart';

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
    // Timed to the last tile landing rather than to the page transition: the
    // staggered entrance runs to about 735ms (a 275ms delay for the last item
    // plus its 460ms travel), and a burst that arrives before the page has
    // finished composing reads as an interruption.
    Future<void>.delayed(const Duration(milliseconds: 620), () {
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
    final goal = ref.watch(todayGoalMinutesProvider);
    // The preset the timer will actually start with, not a claim about the
    // shield: apps are chosen in the Shield tab now, so a count here would be
    // a zero dressed up as a fact.
    final preset = ref.watch(
      presetsProvider,
    )[ref.watch(timerProvider).presetIndex];

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
                  color: harmonize(persona.color, cs.primary),
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
                  icon: Icons.timer_outlined,
                  color: cs.secondary,
                  value: formatMinutes(preset.focus),
                  label: 'Focus block',
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
          child: const Card.filled(
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: Gap.xs),
              child: Column(
                children: [
                  _Tip(
                    icon: Icons.timer_outlined,
                    text: 'Tap Focus to start your first session.',
                  ),
                  _Tip(
                    icon: Icons.insights_outlined,
                    text: 'The dashboard fills in as you study.',
                    divider: true,
                  ),
                  _Tip(
                    icon: Icons.shield_outlined,
                    text: 'Tune what gets blocked in the Shield tab.',
                    divider: true,
                  ),
                ],
              ),
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

    return Card.outlined(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.item),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBadge(icon: icon, color: color, size: 34, radius: Radii.tile),
            const SizedBox(height: Gap.md),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(letterSpacing: -0.4),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
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
            // Indented to the title, not the leading icon.
            padding: const EdgeInsets.only(left: Gap.lg + 24 + Gap.lg),
            child: Divider(height: 1, thickness: 1, color: cs.outlineVariant),
          ),
        ListTile(
          leading: Icon(icon, color: cs.primary),
          title: Text(text, style: Theme.of(context).textTheme.bodyLarge),
        ),
      ],
    );
  }
}
