/// Android usage access, usage events and the installed-app list, wrapping
/// `UsageStatsManager` and `PackageManager` behind a single [UsageStats]
/// facade.
///
/// FocusForge's copy of usage_stats 2.0.1, cut down to the calls the app
/// makes. Upstream's network, storage, configuration and standby queries, and
/// its per-package version and install-time metadata, are removed; see
/// FOCUSFORGE-PATCH.md.
///
/// This package is Android-only. Usage events require the special
/// `PACKAGE_USAGE_STATS` permission, which the user grants from system
/// settings via [UsageStats.openUsageAccessSettings].
library;

import 'dart:async';

import 'package:flutter/services.dart';

import 'src/app_info.dart';
import 'src/event_usage_info.dart';

export 'src/app_info.dart';
export 'src/event_usage_info.dart';

/// Entry point for all usage-statistics queries. All methods are static.
class UsageStats {
  UsageStats._();

  static const MethodChannel _channel = MethodChannel('usage_stats');

  /// Whether the `PACKAGE_USAGE_STATS` permission has been granted to this app.
  static Future<bool?> checkUsagePermission() async {
    return _channel.invokeMethod<bool>('isUsagePermission');
  }

  /// Opens the system "Usage access" settings screen unconditionally, even when
  /// the permission is already granted.
  static Future<void> openUsageAccessSettings() async {
    await _channel.invokeMethod<void>('openUsageAccessSettings');
  }

  /// Returns the raw usage events between [startDate] and [endDate].
  static Future<List<EventUsageInfo>> queryEvents(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final events = await _channel.invokeMethod('queryEvents', {
      'start': startDate.millisecondsSinceEpoch,
      'end': endDate.millisecondsSinceEpoch,
    });
    return (events as List)
        .map((item) => EventUsageInfo.fromMap(item))
        .toList();
  }

  /// Returns [AppInfo] for every installed app the caller is allowed to see.
  ///
  /// Set [includeSystem] to false to exclude system apps. On Android 11+
  /// (API 30) package-visibility rules limit the result to what the host
  /// app's `<queries>` entries make visible.
  static Future<List<AppInfo>> queryInstalledApps({
    bool includeSystem = true,
  }) async {
    final response = await _channel.invokeMethod('queryInstalledApps', {
      'includeSystem': includeSystem,
    });
    return (response as List).map((item) => AppInfo.fromMap(item)).toList();
  }

  /// Returns the PNG-encoded launcher icon for [packageName], or null if it
  /// cannot be resolved.
  static Future<Uint8List?> getAppIcon(String packageName) async {
    return _channel.invokeMethod<Uint8List>('getAppIcon', {
      'packageName': packageName,
    });
  }
}
