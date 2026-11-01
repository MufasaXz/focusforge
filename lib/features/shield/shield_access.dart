import '../../core/localization/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/shield_providers.dart';
import '../../core/providers/usage_providers.dart';
import '../../core/services/native_shield_service.dart';
import '../../core/services/permission_manager.dart';
import '../../shared/widgets/accessibility_disclosure.dart';
import '../../shared/widgets/app_list_disclosure.dart';
import '../settings/settings_support.dart';

import 'package:go_router/go_router.dart';

import '../../app/router.dart';

/// Shared by the Shield prompts so requesting access is injectable in tests.
final shieldPermissionManagerProvider = Provider<PermissionManager>(
  (ref) => const PermissionManager(),
);

/// Checks access for a local rule. Whole-app rules may be saved pending Home
/// usage consent, but are only enforced after both Android grants are present.
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

  ref.invalidate(overlayAccessProvider);
  final overlay = await _granted(ref.read(overlayAccessProvider.future));
  if (!context.mounted) return false;
  if (!overlay) {
    await _offerAccess(context, ref, AppPermission.overlay);
    return false;
  }
  // Usage consent belongs on Home. Saving this rule never sends the user to
  // Usage settings; the native engine remains inactive without that grant.
  ref.invalidate(usageAccessProvider);
  final usage = await _granted(ref.read(usageAccessProvider.future));
  if (!context.mounted) return false;
  if (!usage) return true;
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
            ? context.tr("Allow draw over other apps")
            : context.tr("Allow usage access first"),
      ),
      scrollable: true,
      content: Text(
        permission == AppPermission.overlay
            ? context.tr(
                "Draw over other apps is off, so FocusForge cannot show the pause screen over your chosen apps. This rule will stay off.\n\nAllow FocusForge in Android Draw over other apps settings, then return and enable the rule again.",
              )
            : context.tr(
                "Usage access is off, so FocusForge cannot detect when your chosen apps are open or measure their daily budgets. This rule will stay off.\n\nAllow FocusForge in Android Usage access settings, then return and enable the rule again. Usage history stays on this device.",
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.tr("Later")),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            permission == AppPermission.overlay
                ? context.tr("Open overlay settings")
                : context.tr("Open usage settings"),
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
  // Usage access is how per-app time is read, so the app-list disclosure
  // comes first. A "Not now" there ends the request here.
  if (permission == AppPermission.usageAccess &&
      !await confirmAppListAccess(context, ref)) {
    return;
  }
  if (!context.mounted) return;
  if (permission == AppPermission.usageAccess &&
      GoRouter.maybeOf(context)?.routeInformationProvider.value.uri.path
              .contains('shield') ==
          true) {
    await showUsageHomeGuidance(context);
    return;
  }
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

/// Missing usage leaves the rule disabled; permission consent lives on Home.
Future<void> showUsageHomeGuidance(BuildContext context) async {
  final home = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.tr("App usage is off")),
      scrollable: true,
      content: Text(
        context.tr(
          "Draw over other apps can show a pause screen, but cannot detect which app is open. Usage Access supplies that detection, so this saved rule stays inactive without it. Open Home and use Allow app usage to read the explanation and choose access. Accessibility is only needed for the YouTube filters.",
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.tr("Later")),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(context.tr("Go to Home")),
        ),
      ],
    ),
  );
  if (home == true && context.mounted) context.goNamed(AppRoutes.dashboard);
}
