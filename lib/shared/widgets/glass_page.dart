import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/color_tokens.dart';
import '../../app/theme/glass_theme.dart';
import 'glass_surface.dart';

/// Page chrome for every pushed sub-screen.
///
/// Having one of these is what stops eight settings screens from drifting into
/// eight slightly different headers. The bar is genuinely frosted — a real
/// [BackdropFilter], not a tinted box — because content scrolling underneath it
/// is the whole reason the effect exists.
class GlassPage extends StatelessWidget {
  const GlassPage({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.bottomPadding = 40,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  final double bottomPadding;

  /// Pinned above the scroll view, e.g. a segmented control.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: t.blurNav,
                sigmaY: t.blurNav,
              ),
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  Gap.sm,
                  topInset + Gap.sm,
                  Gap.md,
                  Gap.sm,
                ),
                decoration: BoxDecoration(
                  color: t.navFill,
                  border: Border(bottom: BorderSide(color: t.hairline)),
                ),
                child: Row(
                  children: [
                    _BackButton(),
                    const SizedBox(width: Gap.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: context.type.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              style: context.type.labelSmall?.copyWith(
                                color: t.textTertiary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    ?trailing,
                  ],
                ),
              ),
            ),
          ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 0),
              child: Column(children: actions),
            ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                Gap.lg,
                Gap.lg,
                Gap.lg,
                bottomPadding + MediaQuery.paddingOf(context).bottom,
              ),
              children: [child],
            ),
          ),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    // `canPop` is false when the route was reached by deep link; falling back
    // to the profile root keeps the button from being a dead end.
    final canPop = context.canPop();
    return Semantics(
      button: true,
      label: 'Go back',
      child: Tooltip(
        message: 'Back',
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              if (canPop) {
                context.pop();
              } else {
                context.go('/profile');
              }
            },
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                Icons.arrow_back_rounded,
                size: 20,
                color: t.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled group of rows inside a [GlassPage] — the settings idiom.
class GlassSection extends StatelessWidget {
  const GlassSection({
    super.key,
    required this.title,
    required this.children,
    this.footnote,
  });

  final String title;
  final List<Widget> children;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, Gap.sm),
          child: Text(
            title.toUpperCase(),
            style: context.type.labelMedium?.copyWith(
              color: t.textTertiary,
              letterSpacing: 1.3,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        GlassPanel(
          radius: Radii.card,
          padding: const EdgeInsets.symmetric(vertical: Gap.xs),
          child: Column(children: children),
        ),
        if (footnote != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, Gap.sm, 6, 0),
            child: Text(
              footnote!,
              style: context.type.bodySmall?.copyWith(color: t.textTertiary),
            ),
          ),
        const SizedBox(height: Gap.xl),
      ],
    );
  }
}

/// A tappable settings row. Full-width target, per Fitts's Law — the switch or
/// chevron is an affordance, not the hit box.
class GlassRow extends StatelessWidget {
  const GlassRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.trailing,
    this.onTap,
    this.showDivider = true,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.md),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 19, color: iconColor ?? t.textSecondary),
            const SizedBox(width: Gap.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: context.type.bodyLarge),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: context.type.bodySmall
                          ?.copyWith(color: t.textTertiary),
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: Gap.md),
            trailing!,
          ],
        ],
      ),
    );

    return Column(
      children: [
        if (onTap == null)
          content
        else
          Semantics(
            button: true,
            child: Material(
              color: Colors.transparent,
              child: InkWell(onTap: onTap, child: content),
            ),
          ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.only(left: Gap.md + 19 + Gap.md),
            child: Divider(height: 1, thickness: 1, color: t.hairline),
          ),
      ],
    );
  }
}

/// Chevron used at the end of a navigable row.
class GlassChevron extends StatelessWidget {
  const GlassChevron({super.key});

  @override
  Widget build(BuildContext context) => Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: context.glass.textTertiary,
      );
}
