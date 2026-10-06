import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

/// Centred empty state: an outlined icon, a headline, a supporting line and an
/// optional call to action.
///
/// The icon is a plain 48dp outline in `onSurfaceVariant` rather than a haloed
/// badge. An empty state's job is to explain an absence and point at the action
/// that fills it; a decorative bloom behind the glyph competes with the button
/// that is the only thing on the screen worth tapping.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Gap.xl,
        vertical: Gap.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: cs.onSurfaceVariant),
          const SizedBox(height: Gap.lg),
          Text(
            title,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Gap.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          if (action != null) ...[const SizedBox(height: Gap.xl), action!],
        ],
      ),
    );
  }
}
