import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/models/shield.dart';
import '../../../core/providers/shield_providers.dart';
import '../../../shared/widgets/glass_surface.dart';
import '../../../shared/widgets/glass_toggle.dart';

/// Per-app feed shields, wired to the real shield state.
///
/// Rows come from [allFeedRowsProvider], so toggling one here is the same
/// mutation the Shield tab performs — persisted, synced to the platform
/// service, and reflected everywhere. The whole row is the hit target; the
/// switch is the affordance, not the only place a finger can land.
class AppDistribution extends ConsumerWidget {
  const AppDistribution({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final rows = ref.watch(allFeedRowsProvider);

    if (rows.isEmpty) {
      return Text(
        'No feeds configured yet.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(color: cs.outlineVariant, height: Gap.md),
          _ShieldRow(row: rows[i]),
        ],
      ],
    );
  }
}

class _ShieldRow extends ConsumerWidget {
  const _ShieldRow({required this.row});

  final FeedRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    void toggle() {
      HapticFeedback.lightImpact();
      ref.read(feedGroupsProvider.notifier).toggle(row.id, !row.enabled);
    }

    return Semantics(
      container: true,
      toggled: row.enabled,
      label: '${row.appName}: ${row.title}',
      onTap: toggle,
      child: Pressable(
        onTap: toggle,
        scale: 0.985,
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.sm),
            child: Row(
              children: [
                GlassIconBadge(
                  icon: row.icon,
                  color: row.color,
                  glow: row.enabled ? 0.6 : 0,
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              row.appName,
                              style: Theme.of(context).textTheme.titleSmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (row.enabled) ...[
                            const SizedBox(width: 6),
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: cs.tertiary,
                                boxShadow: [
                                  BoxShadow(
                                    color: cs.tertiary.withValues(alpha: 0.7),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        row.title,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Gap.md),
                GlassToggle(
                  value: row.enabled,
                  onChanged: (_) => toggle(),
                  accent: row.color,
                  semanticLabel: row.title,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
