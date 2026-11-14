import '../../core/localization/app_strings.dart';

import 'dart:async';

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
class StepScaffold extends StatefulWidget {
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
  final FutureOr<void> Function()? onPrimary;
  final bool primaryEnabled;
  final bool primaryBusy;
  final Widget? secondary;
  final String? footnote;

  @override
  State<StepScaffold> createState() => _StepScaffoldState();
}

class _StepScaffoldState extends State<StepScaffold> {
  bool _saving = false;

  Future<void> _submit() async {
    if (_saving || widget.primaryBusy || !widget.primaryEnabled) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _saving = true);
    try {
      await widget.onPrimary?.call();
    } catch (_) {
      if (mounted) {
        showAppSnack(
          context,
          tr("Could not save this step. Try again."),
          danger: true,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).colorScheme;

    // No label above the title: the header already names the step, and a
    // second caption in capitals only repeats it.
    final body = <Widget>[
      const SizedBox(height: Gap.sm),
      Stagger(
        index: 0,
        child: Semantics(
          header: true,
          child: Text(
            widget.title,
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(letterSpacing: -.6),
          ),
        ),
      ),
      if (widget.subtitle != null)
        Stagger(
          index: 1,
          child: Padding(
            padding: const EdgeInsets.only(top: Gap.md),
            child: Text(
              widget.subtitle!,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: t.onSurfaceVariant),
            ),
          ),
        ),
      const SizedBox(height: Gap.xl),
      ...widget.children,
    ];
    final footer = Padding(
      padding: EdgeInsets.fromLTRB(
        Gap.xl,
        Gap.lg,
        Gap.xl,
        Gap.lg + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PrimaryAction(
            label: widget.primaryLabel,
            onTap: widget.onPrimary == null ? null : _submit,
            enabled: widget.primaryEnabled,
            busy: widget.primaryBusy || _saving,
            icon: Icons.arrow_forward_rounded,
          ),
          if (widget.secondary != null)
            Padding(
              padding: const EdgeInsets.only(top: Gap.xs),
              child: widget.secondary,
            ),
          if (widget.footnote != null)
            Padding(
              padding: const EdgeInsets.only(top: Gap.sm),
              child: Text(
                widget.footnote!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: t.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
        // A keyboard or landscape viewport needs one scroll surface; a pinned
        // footer must not consume the space needed to reach the fields.
        // Decide from the height before the IME opened. Replacing the layout
        // while Android resizes for its keyboard would dispose the focused
        // text field and immediately close that keyboard again.
        final layoutHeight = MediaQuery.sizeOf(context).height;
        if (layoutHeight < 400 || (largeText && layoutHeight < 650)) {
          return ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Gap.xl,
                  Gap.lg,
                  Gap.xl,
                  Gap.xl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: body,
                ),
              ),
              footer,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  Gap.xl,
                  Gap.lg,
                  Gap.xl,
                  Gap.xl,
                ),
                children: body,
              ),
            ),
            _StepFooter(child: footer),
          ],
        );
      },
    );
  }
}

/// A solid action area keeps the next step clear.
class _StepFooter extends StatelessWidget {
  const _StepFooter({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: Theme.of(context).colorScheme.surface, child: child);
}

/// Back affordance plus a per-stage stepper. The user should always know how
/// much setup is left — an open-ended onboarding is one people abandon.
///
/// A single progress track keeps the header quiet while stating the step.
class OnboardingFlowHeader extends StatelessWidget {
  const OnboardingFlowHeader({
    super.key,
    required this.index,
    required this.total,
    required this.title,
    required this.onBack,
  });

  final int index;
  final int total;
  final String title;

  /// Null on the first interactive step, which has nowhere to go back to.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        onBack == null ? Gap.xl : Gap.sm,
        Gap.sm,
        Gap.lg,
        Gap.sm,
      ),
      child: Row(
        children: [
          if (onBack != null) ...[
            IconButton(
              onPressed: onBack,
              tooltip: context.tr("Back"),
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
            ),
            const SizedBox(width: Gap.sm),
          ],
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
          final pillLeft = (x(index) - pillW / 2).clamp(
            0.0,
            (w - pillW).clamp(0.0, w),
          );

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
