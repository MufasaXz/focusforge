import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';

/// Page chrome for every pushed sub-screen.
///
/// A plain [Scaffold] with a standard [AppBar]. One helper is what stops eight
/// settings screens from drifting into eight slightly different headers — but
/// the header itself is stock Material 3, not a bespoke frosted bar.
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.bottomPadding = Gap.xxl,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  final double bottomPadding;

  /// Pinned between the app bar and the scroll view, e.g. a segmented control.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        // How far the capped column is inset from the page's own edges. Zero
        // on a phone, where the cap does not bind.
        final inset = math.max(
          0.0,
          (constraints.maxWidth - Layout.readable) / 2,
        );

        return Scaffold(
          // The bar spans the page — chrome that stops short of the edge looks
          // broken — but its contents start and end where the content below
          // them does, so the title sits over the cards rather than off to one
          // side of them.
          appBar: AppBar(
            titleSpacing: 0,
            leadingWidth: _leadingWidth + inset,
            // `canPop` is false when the route was reached by deep link;
            // falling back to the profile root keeps the button from being a
            // dead end.
            leading: Padding(
              padding: EdgeInsets.only(left: inset),
              child: Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back',
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/profile');
                    }
                  },
                ),
              ),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
            actions: [
              ?trailing,
              SizedBox(width: Gap.sm + inset),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Layout.readable),
              child: Column(
                children: [
                  if (actions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Gap.lg,
                        Gap.md,
                        Gap.lg,
                        0,
                      ),
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
            ),
          ),
        );
      },
    );
  }

  /// Material's own width for the app bar's leading slot.
  static const double _leadingWidth = 56;
}

/// A labelled group of rows inside an [AppPage] — the settings idiom.
///
/// Children are expected to be [ListTile]s. The card supplies the surface and
/// the corner clipping; the tiles supply their own padding and ink.
class AppSection extends StatelessWidget {
  const AppSection({
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.xs, 0, Gap.xs, Gap.sm),
          child: Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.titleSmall),
          ),
        ),
        Card.filled(
          // Without this the tile ripples paint square corners over the card's
          // rounded ones.
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
        if (footnote != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.sm, Gap.xs, 0),
            child: Text(
              footnote!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: Gap.xl),
      ],
    );
  }
}

/// Chevron used at the end of a navigable row.
class AppChevron extends StatelessWidget {
  const AppChevron({super.key});

  @override
  Widget build(BuildContext context) => Icon(
    Icons.chevron_right,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );
}

/// Horizontal fade mask — applied to the edges of horizontally scrolling rows
/// so items dissolve instead of being sliced off mid-chip.
class EdgeFade extends StatelessWidget {
  const EdgeFade({
    super.key,
    required this.child,
    this.leading = 0,
    this.trailing = 24,
  });

  final Widget child;
  final double leading;
  final double trailing;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => LinearGradient(
        colors: [
          leading > 0 ? Colors.transparent : Colors.black,
          Colors.black,
          Colors.black,
          trailing > 0 ? Colors.transparent : Colors.black,
        ],
        stops: [
          0,
          leading > 0 ? (leading / rect.width).clamp(0.0, 0.4) : 0.0,
          trailing > 0 ? 1 - (trailing / rect.width).clamp(0.0, 0.4) : 1.0,
          1,
        ],
      ).createShader(rect),
      child: child,
    );
  }
}

/// A sentence-case heading above a group of cards or rows.
///
/// The same treatment [AppSection] gives its heading, exposed separately for
/// the screens that group raw cards rather than list tiles.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.icon,
  });

  final String title;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.xs, 0, Gap.xs, Gap.md),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: Gap.sm),
          ],
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: theme.textTheme.titleMedium),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
