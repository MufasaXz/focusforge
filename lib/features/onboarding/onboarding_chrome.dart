import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../shared/widgets/form_controls.dart';
import '../../shared/widgets/stagger.dart';
import '../../shared/widgets/tonal_panel.dart';

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
      if (MediaQuery.sizeOf(context).height >= 400) ...[
        const Eyebrow('MAKE IT YOURS', icon: Icons.tune_rounded),
        const SizedBox(height: Gap.lg),
      ],
      Stagger(
        index: 0,
        child: Semantics(
          header: true,
          child: Text(
            widget.title,
            style: Theme.of(context).textTheme.headlineLarge
                ?.copyWith(letterSpacing: -1.1),
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
            _FrostedFooter(child: footer),
          ],
        );
      },
    );
  }
}

/// The pinned primary-action surface every step shares.
///
/// An opaque footer would cut the page in two; a frosted one keeps the Continue
/// button legible while the content behind shows through, which is why sheets
/// and the nav bar get this material and the footer now matches them. The
/// shared-blur group keeps it cheap, the top hairline marks where the scroll
/// surface ends, and on true black the blur switches off — there is nothing
/// behind a black surface to see — while the hairline stays so the footer
/// still reads as its own surface.
class _FrostedFooter extends StatelessWidget {
  const _FrostedFooter({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final black = cs.surface == const Color(0xFF000000);
    final hairline = Border(
      top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
    );
    // Blurring behind an opaque black surface would spend GPU time to produce
    // the same pixels, so true black keeps the flat fill and the hairline.
    if (black) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          border: hairline,
        ),
        child: child,
      );
    }
    return BackdropGroup(
      child: ClipRect(
        child: BackdropFilter.grouped(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  cs.surfaceContainerLow.withValues(alpha: 0.55),
                  cs.surfaceContainerLow.withValues(alpha: 0.85),
                ],
              ),
              border: hairline,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
