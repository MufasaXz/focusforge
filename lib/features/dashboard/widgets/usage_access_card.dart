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
                label: const Text('Allow app usage'),
              ),
              const SizedBox(height: Gap.sm),
              Text(
                'See your screen time and let your selected app boundaries and daily budgets detect which app is open. App usage stays on this device. Your focus timer works without this access.',
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
    final allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Why FocusForge asks for app usage'),
        scrollable: true,
        content: const Text(
          'Usage Access lets FocusForge read which app is open and how long apps are used. We use this on your device to show screen-time totals and enforce the app boundaries and daily budgets you choose.\n\nThis data stays on this device and is not uploaded. It does not let us read messages, typed text or browsing content. Access is optional: your focus timer and study history work without it. You can revoke it in Android Settings at any time.\n\nContinue to Android Usage Access settings, select FocusForge and decide whether to allow it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open usage settings'),
          ),
        ],
      ),
    );
    if (allow != true || !mounted) return;
    setState(() => _opening = true);
    try {
      await requestShieldPermission(context, ref, AppPermission.usageAccess);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }
}
