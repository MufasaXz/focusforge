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
          'Could not save this step. Try again.',
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

    final body = <Widget>[
      Stagger(
        index: 0,
        child: Semantics(
          header: true,
          child: Text(
            widget.title,
            style: Theme.of(context).textTheme.headlineLarge,
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
        if (constraints.maxHeight < 400 ||
            (largeText && constraints.maxHeight < 650)) {
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
            DecoratedBox(
              decoration: BoxDecoration(
                color: t.surface,
                border: Border(
                  top: BorderSide(
                    color: t.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
              ),
              child: footer,
            ),
          ],
        );
      },
    );
  }
}
