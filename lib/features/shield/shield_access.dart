import '../../core/localization/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/shield_providers.dart';
import '../../core/providers/usage_providers.dart';
import '../../core/services/native_shield_service.dart';
import '../../core/services/permission_manager.dart';
import '../../shared/widgets/accessibility_disclosure.dart';
import '../../shared/widgets/app_list_disclosure.dart';
import '../../shared/widgets/settings_guide.dart';
import '../settings/settings_support.dart';

/// Shared by the Shield prompts so requesting access is injectable in tests.
final shieldPermissionManagerProvider = Provider<PermissionManager>(
  (ref) => const PermissionManager(),
);

/// Checks access before enabling a local rule. App-list consent does not
/// grant Android Usage Access; usage and overlay are checked separately.
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

  ref.invalidate(usageAccessProvider);
  final usage = await _granted(ref.read(usageAccessProvider.future));
  if (!context.mounted) return false;
  if (!usage) {
    await requestShieldPermission(context, ref, AppPermission.usageAccess);
    // Opening settings is not a grant. A subsequent enable rechecks Android.
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
      context.tr(
        "App boundaries could not start. Check Usage access and Draw over other apps, then try again.",
      ),
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

/// The overlay guide says what the access is for and how to turn it on, so no
/// separate explanation dialog comes first.
Future<void> _offerAccess(
  BuildContext context,
  WidgetRef ref,
  AppPermission permission,
) => requestShieldPermission(context, ref, permission);

/// Opens only the requested Android setting, with accessibility disclosure.
Future<void> requestShieldPermission(
  BuildContext context,
  WidgetRef ref,
  AppPermission permission, {
  String? feature,
}) async {
  // Usage access is how per-app time is read, so the app-list disclosure
  // comes first. A "Not now" there ends the request here.
  if (permission == AppPermission.usageAccess &&
      !await confirmAppListAccess(context, ref)) {
    return;
  }
  if (!context.mounted) return;
  if (permission == AppPermission.accessibility &&
      !await confirmShieldAccess(context, feature: feature)) {
    return;
  }
  if (!context.mounted) return;
  // Android opens a long list here, with no dialog of its own; the guide shows
  // exactly what to tap before the user is sent there.
  final guide = SettingsGuide.forPermission(permission);
  if (guide != null && !await showSettingsGuide(context, guide)) return;
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
          ? context.tr(
              "Open Android Settings → Accessibility → FocusForge to allow blocking.",
            )
          : permission == AppPermission.overlay
          ? context.tr(
              "Open Android Settings → Draw over other apps → FocusForge.",
            )
          : context.tr("Open Android Settings → Usage access → FocusForge."),
    );
  }
}
