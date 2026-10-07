import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/widgets/form_controls.dart';
import '../../shared/widgets/stagger.dart';

/// Furniture shared by every onboarding step.
///
/// The flow is the app's first impression, so the steps must not each invent
/// their own button, field or snackbar — one set of primitives is what keeps
/// seven screens looking like one product.
///
/// The button, field and snackbar primitives now live in
/// `shared/widgets/form_controls.dart`, because the profile's link-account
/// sheet needs the same ones; they are re-exported here so a step still
/// imports a single file.
export '../../shared/widgets/form_controls.dart'
    show AppTextField, GhostAction, PrimaryAction, showAppSnack;

/// The standard step layout: scrollable body, pinned primary action, optional
/// secondary action and footnote.
class StepScaffold extends StatelessWidget {
  const StepScaffold({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.primaryLabel = 'Continue',
    this.onPrimary,
    this.primaryEnabled = true,
    this.primaryBusy = false,
    this.secondary,
    this.footnote,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final bool primaryEnabled;
  final bool primaryBusy;
  final Widget? secondary;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.lg, Gap.xl, Gap.xl),
            children: [
              Stagger(
                index: 0,
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              if (subtitle != null)
                Stagger(
                  index: 1,
                  child: Padding(
                    padding: const EdgeInsets.only(top: Gap.sm),
                    child: Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: t.onSurfaceVariant),
                    ),
                  ),
                ),
              const SizedBox(height: Gap.xl),
              ...children,
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            Gap.xl,
            Gap.sm,
            Gap.xl,
            Gap.md + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            children: [
              PrimaryAction(
                label: primaryLabel,
                onTap: onPrimary,
                enabled: primaryEnabled,
                busy: primaryBusy,
              ),
              if (secondary != null)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.xs),
                  child: secondary,
                ),
              if (footnote != null)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.sm),
                  child: Text(
                    footnote!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: t.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
