import '../../../core/localization/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/providers/usage_providers.dart';
import '../../../core/services/native_shield_service.dart';
import '../../../core/services/permission_manager.dart';
import '../../shield/shield_access.dart';

/// Optional, prominent explanation before opening Android's Usage Access page.
class UsageAccessCard extends ConsumerStatefulWidget {
  const UsageAccessCard({super.key});
  @override
  ConsumerState<UsageAccessCard> createState() => _UsageAccessCardState();
}

class _UsageAccessCardState extends ConsumerState<UsageAccessCard>
    with WidgetsBindingObserver {
  bool _opening = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(usageAccessProvider);
      ref.invalidate(appUsageTodayProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(usageAccessProvider);
    if (!NativeShieldService.isSupported ||
        access.isLoading ||
        access.valueOrNull == true) {
      return const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: Gap.lg),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.tonalIcon(
                onPressed: _opening ? null : _request,
                icon: const Icon(Icons.timelapse_rounded),
                label: Text(context.tr("Allow app usage")),
              ),
              const SizedBox(height: Gap.sm),
              Text(
                context.tr(
                  "Let your selected app boundaries and daily budgets detect which app is open. App usage stays on this device. Your focus timer works without this access.",
                ),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _request() async {
    // One explanation at a time: until the app list is agreed to,
    // `requestShieldPermission` shows that disclosure first; after it, the
    // settings guide says what usage access is for and how to turn it on.
    setState(() => _opening = true);
    try {
      await requestShieldPermission(context, ref, AppPermission.usageAccess);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }
}
