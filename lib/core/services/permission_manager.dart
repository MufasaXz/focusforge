import 'package:flutter/foundation.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:usage_stats/usage_stats.dart';

/// The permissions onboarding asks for.
enum AppPermission {
  accessibility,
  notifications,
  usageAccess,
  overlay,
  doNotDisturb,
}

/// What a permission currently resolves to.
enum PermissionOutcome {
  /// The operating system says yes.
  granted,

  /// Refused, or not yet asked.
  denied,

  /// Refused in a way the platform will no longer prompt for.
  ///
  /// The only way back is the app's own settings page — asking again returns
  /// the same refusal without showing anything.
  permanentlyDenied,

  /// The request opened a system Settings page.
  ///
  /// Android has no dialog for accessibility, usage access or overlay — the
  /// user has to find the app in a list and toggle it themselves. The answer
  /// therefore does not exist yet when [PermissionManager.request] returns,
  /// and the UI must not claim either way until the app is resumed.
  openedSettings,

  /// This platform has no such permission.
  unsupported,
}

/// Asks the operating system for the access the shield needs.
///
/// Deliberately free of `dart:io`: the app ships to the web as well as to
/// Android, and `Platform.isAndroid` does not compile there. Every branch is
/// gated on [defaultTargetPlatform] behind a [kIsWeb] check, and every plugin
/// call is wrapped, because a plugin with no implementation for the current
/// platform throws rather than returning a negative answer.
class PermissionManager {
  const PermissionManager();

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get _isApple =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Whether the current platform can be asked at all.
  ///
  /// Notifications exist everywhere; the other four are Android's app-usage
  /// and notification-policy APIs and have no iOS equivalent.
  bool supports(AppPermission permission) => switch (permission) {
    AppPermission.notifications => _isAndroid || _isApple,
    _ => _isAndroid,
  };

  /// Reads the current answer without prompting.
  Future<PermissionOutcome> check(AppPermission permission) async {
    if (!supports(permission)) return PermissionOutcome.unsupported;
    try {
      final status = await _statusOf(permission);
      return status.isGranted
          ? PermissionOutcome.granted
          : status.isPermanentlyDenied
          ? PermissionOutcome.permanentlyDenied
          : PermissionOutcome.denied;
    } catch (_) {
      // A missing plugin implementation or a platform that changed shape
      // underneath us. "Unsupported" is the honest answer, and it keeps a
      // permission probe from taking the onboarding flow down with it.
      return PermissionOutcome.unsupported;
    }
  }

  /// Asks the operating system, prompting if that platform has a prompt.
  Future<PermissionOutcome> request(AppPermission permission) async {
    if (!supports(permission)) return PermissionOutcome.unsupported;
    try {
      switch (permission) {
        case AppPermission.notifications:
          return _fromStatus(await Permission.notification.request());

        case AppPermission.doNotDisturb:
          return _fromStatus(
            await Permission.accessNotificationPolicy.request(),
          );

        case AppPermission.accessibility:
          // No dialog exists. This opens Accessibility settings and returns
          // immediately, so the real answer arrives on resume.
          await FlutterAccessibilityService.requestAccessibilityPermission();
          return await _settle(permission);

        case AppPermission.usageAccess:
          await UsageStats.openUsageAccessSettings();
          return await _settle(permission);

        case AppPermission.overlay:
          // Also a settings page on Android, not a dialog.
          await Permission.systemAlertWindow.request();
          return await _settle(permission);
      }
    } catch (_) {
      return PermissionOutcome.unsupported;
    }
  }

  /// Sends the user to the app's own settings page.
  ///
  /// The only route back from a permanent refusal: once Android has stopped
  /// prompting, this screen is where the toggle lives.
  Future<void> openSettings() => openAppSettings();

  Future<PermissionStatus> _statusOf(AppPermission permission) =>
      switch (permission) {
        AppPermission.notifications => Permission.notification.status,
        AppPermission.doNotDisturb => Permission.accessNotificationPolicy.status,
        AppPermission.accessibility =>
          FlutterAccessibilityService.isAccessibilityPermissionEnabled().then(
            (on) => on ? PermissionStatus.granted : PermissionStatus.denied,
          ),
        AppPermission.usageAccess => UsageStats.checkUsagePermission().then(
          (on) => on ?? false ? PermissionStatus.granted : PermissionStatus.denied,
        ),
        AppPermission.overlay => Permission.systemAlertWindow.status,
      };

  static PermissionOutcome _fromStatus(PermissionStatus status) =>
      status.isGranted
      ? PermissionOutcome.granted
      : status.isPermanentlyDenied
      ? PermissionOutcome.permanentlyDenied
      : PermissionOutcome.denied;

  /// Some platforms grant immediately (an older Android, or a settings page
  /// that was already on); the rest have to wait for the user to come back.
  Future<PermissionOutcome> _settle(AppPermission permission) async {
    final now = await check(permission);
    return now == PermissionOutcome.granted
        ? PermissionOutcome.granted
        : PermissionOutcome.openedSettings;
  }
}
