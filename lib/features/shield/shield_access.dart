import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/shield_providers.dart';
import '../../core/providers/usage_providers.dart';
import '../../core/services/native_shield_service.dart';
import '../../core/services/permission_manager.dart';
import '../../shared/widgets/accessibility_disclosure.dart';
import '../settings/settings_support.dart';

/// Shared by the Shield prompts so requesting access is injectable in tests.
final shieldPermissionManagerProvider = Provider<PermissionManager>(
  (ref) => const PermissionManager(),
);

/// Checks the grants for a local rule before the UI can save it as enabled.
///
/// Browser and desktop previews can still configure rules without Android APIs.
Future<bool> ensureShieldAccess(
  BuildContext context,
  WidgetRef ref, {
  bool requiresUsageAccess = false,
}) async {
  if (!NativeShieldService.isSupported) return true;

  ref.invalidate(shieldEnabledProvider);
  final accessibility = await _granted(ref.read(shieldEnabledProvider.future));
  if (!context.mounted) return false;
  if (!accessibility) {
    await _offerAccess(context, ref, AppPermission.accessibility);
    return false;
  }

  if (requiresUsageAccess) {
    ref.invalidate(usageAccessProvider);
    final usage = await _granted(ref.read(usageAccessProvider.future));
    if (!context.mounted) return false;
    if (!usage) {
      await _offerAccess(context, ref, AppPermission.usageAccess);
      return false;
    }
  }
  return true;
}

Future<bool> _granted(Future<bool> answer) async {
  try {
    return await answer;
  } catch (_) {
    return false;
  }
}

Future<void> _offerAccess(
  BuildContext context,
  WidgetRef ref,
  AppPermission permission,
) async {
  final accessibility = permission == AppPermission.accessibility;
  final allow = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(
        accessibility
            ? Icons.accessibility_new_rounded
            : Icons.timelapse_rounded,
      ),
      title: Text(
        accessibility ? 'Allow app blocking first' : 'Allow usage access first',
      ),
      scrollable: true,
      content: Text(
        accessibility
            ? 'Accessibility access is off, so FocusForge cannot block apps '
                  'or YouTube yet. This rule will stay off.\n\n'
                  'In Android Settings, choose FocusForge under Accessibility '
                  'and turn on its service. Return here and try again.'
            : 'Usage access is off, so FocusForge cannot measure the time '
                  'needed for a daily budget. This rule will stay off.\n\n'
                  'In Android Usage access settings, choose FocusForge and '
                  'allow access. Return here and save the rule again.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            accessibility ? 'Review and allow' : 'Open usage settings',
          ),
        ),
      ],
    ),
  );
  if (allow != true || !context.mounted) return;
  await requestShieldPermission(context, ref, permission);
}

/// Opens only the requested Android setting, with accessibility disclosure.
Future<void> requestShieldPermission(
  BuildContext context,
  WidgetRef ref,
  AppPermission permission,
) async {
  if (permission == AppPermission.accessibility &&
      !await confirmShieldAccess(context)) {
    return;
  }
  if (!context.mounted) return;
  final outcome = await ref
      .read(shieldPermissionManagerProvider)
      .request(permission);
  if (!context.mounted) return;
  // Settings grants are checked again by ShieldScreen when the app resumes.
  ref.invalidate(shieldEnabledProvider);
  ref.invalidate(usageAccessProvider);
  ref.invalidate(appUsageTodayProvider);
  if (outcome == PermissionOutcome.unsupported) {
    showAppSnack(
      context,
      permission == AppPermission.accessibility
          ? 'Open Android Settings → Accessibility → FocusForge to allow blocking.'
          : 'Open Android Settings → Usage access → FocusForge to allow budgets.',
    );
  }
}
