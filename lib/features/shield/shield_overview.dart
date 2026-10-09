import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/shield.dart';
import '../../core/providers/shield_providers.dart';
import '../../core/services/native_shield_service.dart';
import '../../shared/widgets/tonal_panel.dart';

class ShieldOverview extends ConsumerWidget {
  const ShieldOverview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final access = ref.watch(shieldEnabledProvider);
    final rules = ref.watch(enforcedRulesProvider);
    final youtube = ref.watch(youtubeRulesProvider);
    final supported = NativeShieldService.isSupported;
    final enabled = supported && access.valueOrNull == true;
    final count =
        rules.length + (youtube.shorts ? 1 : 0) + (youtube.feed ? 1 : 0);
    final title = !supported
        ? 'Your rules, ready for Android'
        : access.isLoading
        ? 'Checking your Shield'
        : !enabled
        ? 'One step to protect your focus'
        : count == 0
        ? 'Choose what stays out'
        : 'A quieter phone starts here';

    return TonalPanel(
      accent: true,
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Eyebrow(
            'YOUR ATTENTION, PROTECTED',
            icon: Icons.shield_outlined,
          ),
          const SizedBox(height: Gap.md),
          Text(title, style: tt.titleLarge?.copyWith(letterSpacing: -.6)),
          const SizedBox(height: Gap.sm),
          Text(
            !supported
                ? 'App blocking runs on your Android device.'
                : !enabled
                ? 'Enable accessibility below to apply your chosen rules.'
                : 'Set boundaries for apps and feeds. You stay in control.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: Gap.lg),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              _Count(
                label: 'Blocked',
                count: rules
                    .where((r) => r.tier == WhitelistTier.blocked)
                    .length,
              ),
              _Count(
                label: 'Focus only',
                count: rules
                    .where((r) => r.tier == WhitelistTier.focusOnly)
                    .length,
              ),
              _Count(
                label: 'Budgets',
                count: rules
                    .where((r) => r.tier == WhitelistTier.budgeted)
                    .length,
              ),
              if (youtube.any)
                _Count(
                  label: 'YouTube filters',
                  count: (youtube.shorts ? 1 : 0) + (youtube.feed ? 1 : 0),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(Radii.tile),
      ),
      child: Text(
        '$count $label',
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}
