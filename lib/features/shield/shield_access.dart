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
  bool requiresAccessibility = false,
  String? feature,
}) async {
  if (!NativeShieldService.isSupported) return true;

  if (requiresAccessibility) {
    ref.invalidate(shieldEnabledProvider);
    final accessibility = await _granted(
      ref.read(shieldEnabledProvider.future),
    );
    if (!context.mounted) return false;
    if (!accessibility) {
      await requestShieldPermission(
        context,
        ref,
        AppPermission.accessibility,
        feature: feature,
      );
      return false;
    }
    return true;
  }

  // Usage access provides foreground detection for every whole-app rule.
  ref.invalidate(usageAccessProvider);
  final usage = await _granted(ref.read(usageAccessProvider.future));
  if (!context.mounted) return false;
  if (!usage) {
    await _offerAccess(context, ref, AppPermission.usageAccess);
    return false;
  }
  ref.invalidate(overlayAccessProvider);
  final overlay = await _granted(ref.read(overlayAccessProvider.future));
  if (!context.mounted) return false;
  if (!overlay) {
    await _offerAccess(context, ref, AppPermission.overlay);
    return false;
  }
  // An explicit rule enable can resume a notification-paused engine. Background sync cannot.
  final started = await NativeShieldService().resumeAppBlocking();
  if (!context.mounted) return false;
  ref.invalidate(appBlockingPausedProvider);
  ref.invalidate(appBlockingRunningProvider);
  if (!started) {
    showAppSnack(
      context,
      'App boundaries could not start. Check Usage access and Draw over other apps, then try again.',
    );
    return false;
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
  final allow = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.timelapse_rounded),
      title: Text(
        permission == AppPermission.overlay
            ? 'Allow draw over other apps'
            : 'Allow usage access first',
      ),
      scrollable: true,
      content: Text(
        permission == AppPermission.overlay
            ? 'Draw over other apps is off, so FocusForge cannot show the pause screen over your chosen apps. This rule will stay off.\n\nAllow FocusForge in Android Draw over other apps settings, then return and enable the rule again.'
            : 'Usage access is off, so FocusForge cannot detect when your chosen apps are open or measure their daily budgets. This rule will stay off.\n\nAllow FocusForge in Android Usage access settings, then return and enable the rule again. Usage history stays on this device.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            permission == AppPermission.overlay
                ? 'Open overlay settings'
                : 'Open usage settings',
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
  AppPermission permission, {
  String? feature,
}) async {
  if (permission == AppPermission.accessibility &&
      !await confirmShieldAccess(context, feature: feature)) {
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
  ref.invalidate(overlayAccessProvider);
  ref.invalidate(appBlockingRunningProvider);
  ref.invalidate(appBlockingPausedProvider);
  ref.invalidate(appUsageTodayProvider);
  if (outcome == PermissionOutcome.unsupported) {
    showAppSnack(
      context,
      permission == AppPermission.accessibility
          ? 'Open Android Settings → Accessibility → FocusForge to allow blocking.'
          : permission == AppPermission.overlay
          ? 'Open Android Settings → Draw over other apps → FocusForge.'
          : 'Open Android Settings → Usage access → FocusForge.',
    );
  }
}
