import '../../../core/localization/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/providers/usage_providers.dart';
import '../../../core/services/native_shield_service.dart';
import '../../../core/services/permission_manager.dart';
import '../../shield/shield_access.dart';
import '../../../shared/widgets/glass_surface.dart';
import '../../../shared/widgets/icon_badge.dart';

/// Hidden by "Not now" until the next launch: a dismissal is an answer for
/// today, not a promise never to ask.
final usageCardDismissedProvider = StateProvider<bool>((ref) => false);

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
    if (ref.watch(usageCardDismissedProvider)) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // The ask the way system-grade apps make it: what it is, one line of
    // why, and two plain answers. The longer explanation still comes before
    // Android's settings page opens.
    return Padding(
      padding: const EdgeInsets.only(top: Gap.lg),
      child: ContentCard(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Gap.lg + 4,
            Gap.lg + 4,
            Gap.lg,
            Gap.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconBadge(
                    icon: Icons.query_stats_rounded,
                    color: cs.primary,
                    size: 44,
                    radius: 14,
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr("Allow app usage"),
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.tr(
                            "See your screen time and let your app limits work. It stays on this phone.",
                          ),
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.sm),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: Gap.sm,
                children: [
                  TextButton(
                    onPressed: _opening
                        ? null
                        : () =>
                              ref
                                      .read(usageCardDismissedProvider.notifier)
                                      .state =
                                  true,
                    child: Text(context.tr("Not now")),
                  ),
                  FilledButton(
                    onPressed: _opening ? null : _request,
                    child: Text(context.tr("Allow")),
                  ),
                ],
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
