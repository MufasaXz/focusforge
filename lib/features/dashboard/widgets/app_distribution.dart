import '../../../shared/widgets/glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/models/shield.dart';
import '../../../core/providers/usage_providers.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/app_icon_avatar.dart';
import '../../../shared/widgets/icon_badge.dart';
import '../../../shared/widgets/pressable.dart';

/// What the shield is doing, with today's real screen time next to it.
///
/// This is a summary, not a control panel: the dashboard answers "is it
/// working", and the Shield tab is where a rule is changed. Every row is a
/// live rule from [enrichedWhitelistProvider], so the numbers here are the
/// same ones the Shield tab shows rather than a second, drifting copy.
class AppDistribution extends ConsumerWidget {
  const AppDistribution({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final rules = ref.watch(enrichedWhitelistProvider);
    final usageAccess = ref.watch(usageAccessProvider).valueOrNull ?? false;

    if (rules.isEmpty) {
      return GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(
                icon: Icons.shield_outlined,
                color: cs.onSurfaceVariant,
                size: 40,
                radius: Radii.tile,
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No apps shielded yet',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Pick the apps you open without meaning to and they '
                      'close themselves.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: Gap.sm),
                    TextButton(
                      onPressed: () => _openShield(context),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Choose apps'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Busiest first: the top of the list should be the app costing the most,
    // which is the one the card is really about.
    final sorted = [...rules]
      ..sort((a, b) {
        final byUsage = b.usedMinutes.compareTo(a.usedMinutes);
        return byUsage != 0 ? byUsage : a.name.compareTo(b.name);
      });
    final busiest = sorted.first.usedMinutes;
    final shown = sorted.take(4).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) Divider(color: cs.outlineVariant, height: Gap.lg),
          _RuleSummary(
            entry: shown[i],
            busiestMinutes: busiest,
            usageAccess: usageAccess,
          ),
        ],
        if (sorted.length > shown.length) ...[
          const SizedBox(height: Gap.md),
          TextButton(
            onPressed: () => _openShield(context),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              alignment: Alignment.centerLeft,
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text('${sorted.length - shown.length} more in Shield'),
          ),
        ],
      ],
    );
  }

  /// Switches to the Shield tab rather than pushing a route: the branch is
  /// already built, and a push would put a second copy of the screen on top of
  /// a tab the user can see in the bar.
  static void _openShield(BuildContext context) {
    final shell = StatefulNavigationShell.maybeOf(context);
    if (shell != null) {
      shell.goBranch(1);
      return;
    }
    context.go(AppRoutes.paths[AppRoutes.shield]!);
  }
}

class _RuleSummary extends StatelessWidget {
  const _RuleSummary({
    required this.entry,
    required this.busiestMinutes,
    required this.usageAccess,
  });

  final WhitelistEntry entry;
  final int busiestMinutes;
  final bool usageAccess;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = harmonize(entry.tier.color, cs.primary);
    final budgeted = entry.tier == WhitelistTier.budgeted;
    final share = busiestMinutes == 0
        ? 0.0
        : entry.usedMinutes / busiestMinutes;

    void open() => AppDistribution._openShield(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          container: true,
          label:
              '${entry.name}. ${_ruleLabel(entry)}. '
              '${usageAccess ? '${formatMinutes(entry.usedMinutes)} today' : 'Usage unavailable'}. '
              'Opens the Shield tab',
          onTap: open,
          child: ExcludeSemantics(
            child: Pressable(
              scale: 0.985,
              onTap: open,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                child: Row(
                  children: [
                    AppIconAvatar(
                      packageId: entry.packageId,
                      fallbackIcon: entry.icon,
                      fallbackColor: accent,
                      size: 40,
                      radius: Radii.tile,
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
                                  entry.name,
                                  style: Theme.of(context).textTheme.titleSmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: Gap.sm),
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: accent,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _ruleLabel(entry),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Gap.md),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          usageAccess ? formatMinutes(entry.usedMinutes) : '—',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: entry.overBudget ? cs.error : cs.onSurface,
                              ),
                        ),
                        Text(
                          'today',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // The bar compares this app against the busiest one on the list, which
        // is a comparison the user can act on; a bar against an arbitrary
        // ceiling would just look short for everyone.
        if (budgeted && usageAccess) ...[
          const SizedBox(height: Gap.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: LinearProgressIndicator(
              value: share,
              color: entry.overBudget ? cs.error : accent,
              backgroundColor: cs.surfaceContainerHighest,
              minHeight: 4,
            ),
          ),
        ],
      ],
    );
  }

  static String _ruleLabel(WhitelistEntry entry) => switch (entry.tier) {
    WhitelistTier.blocked => 'Closes when opened',
    WhitelistTier.focusOnly => 'Closes while focusing',
    WhitelistTier.budgeted =>
      '${formatMinutes(entry.budgetMinutes ?? 0)} a day',
    WhitelistTier.alwaysAllowed => 'Never closed',
  };
}
