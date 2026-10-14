import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/shield.dart';
import '../../core/providers/shield_providers.dart';
import '../../core/providers/usage_providers.dart';
import 'shield_access.dart';
import '../../core/services/native_shield_service.dart';
import '../../shared/widgets/tonal_panel.dart';

class ShieldOverview extends ConsumerWidget {
  const ShieldOverview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final access = ref.watch(appBlockingRunningProvider);
    final paused = ref.watch(appBlockingPausedProvider).valueOrNull ?? false;
    final usage = ref.watch(usageAccessProvider).valueOrNull ?? false;
    final overlay = ref.watch(overlayAccessProvider).valueOrNull ?? false;
    final youtubeAccess = ref.watch(shieldEnabledProvider).valueOrNull ?? false;
    final rules = ref.watch(enforcedRulesProvider);
    final youtube = ref.watch(youtubeRulesProvider);
    final supported = NativeShieldService.isSupported;
    final enabled = supported && usage && overlay && access.valueOrNull == true;
    final count =
        rules.length + (youtube.shorts ? 1 : 0) + (youtube.feed ? 1 : 0);
    final title = !supported
        ? 'Your rules, ready for Android'
        : access.isLoading && !access.hasValue && rules.isNotEmpty
        ? 'Checking your Shield'
        : paused && rules.isNotEmpty
        ? 'App boundaries are paused'
        : rules.isNotEmpty && !enabled
        ? 'Your app rules need attention'
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
                : paused && rules.isNotEmpty
                ? 'Your saved app rules are inactive. Enable an app rule when you want boundaries active again.'
                : rules.isNotEmpty && !enabled
                ? !usage
                      ? 'Inactive · Your app rules are saved. Allow app usage on Home when you want FocusForge to detect and pause these apps.'
                      : !overlay
                      ? 'Inactive · Allow Draw over other apps to show the pause screen. Your app rules stay saved.'
                      : 'Inactive · Your saved app rules are not currently running. Enable an app rule to start boundaries again.'
                : 'Set boundaries for apps and feeds. You stay in control.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (supported && rules.isNotEmpty && !usage) ...[
            const SizedBox(height: Gap.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => showUsageHomeGuidance(context),
                icon: const Icon(Icons.home_outlined),
                label: const Text('Allow app usage on Home'),
              ),
            ),
          ],
          if (supported && rules.isNotEmpty && !enabled && !overlay) ...[
            const SizedBox(height: Gap.md),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  if (await ensureShieldAccess(context, ref)) {
                    ref.invalidate(appBlockingRunningProvider);
                    ref.invalidate(appBlockingPausedProvider);
                  }
                },
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Check overlay access'),
              ),
            ),
          ],
          if (supported && youtube.any && !youtubeAccess) ...[
            const SizedBox(height: Gap.sm),
            Text(
              'YouTube filters are inactive until Accessibility access is restored.',
              style: tt.bodySmall?.copyWith(color: cs.error),
            ),
          ],
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
