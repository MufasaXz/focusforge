import 'package:flutter/foundation.dart';
import 'package:usage_stats/usage_stats.dart';

/// One app installed on the device.
@immutable
class InstalledApp {
  const InstalledApp({
    required this.packageId,
    required this.name,
    required this.isSystem,
  });

  final String packageId;
  final String name;
  final bool isSystem;
}

/// Reads the device's app list, its launcher icons and its real usage.
///
/// Everything here is Android-only and returns an empty result elsewhere
/// rather than throwing: the app ships to the web, and a screen that has to
/// branch on the platform before it can render a list is a screen that will
/// eventually forget to.
///
/// This is the only place `usage_stats` is called, so the platform check and
/// the error handling exist once instead of at every call site.
class AppCatalog {
  const AppCatalog._();

  /// This app's own package.
  ///
  /// Blocking yourself is not a rule anyone wants, and the engine already
  /// exempts it — offering it in the picker would be a promise the engine
  /// silently ignores.
  static const selfPackage = 'dev.focusforge.focusforge';

  /// YouTube's package, where the surface rules apply.
  static const youtubePackage = 'com.google.android.youtube';

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Icons are PNG bytes and are expensive to fetch, so they are cached for
  /// the life of the process. An app's icon does not change while it runs.
  static final Map<String, Uint8List?> _icons = {};

  /// The packages the user can meaningfully block.
  ///
  /// System apps are excluded — the list is for choosing what to close, and
  /// offering the user the ability to block the settings app or their keyboard
  /// is offering them a way to break their phone. FocusForge itself is
  /// excluded for the same reason.
  static Future<List<InstalledApp>> installed({
    String? excludePackage,
  }) async {
    if (!isSupported) return const [];
    try {
      final raw = await UsageStats.queryInstalledApps(includeSystem: false);
      final apps = <InstalledApp>[];
      for (final app in raw) {
        final packageId = app.packageName;
        final label = app.appName;
        if (packageId.isEmpty) continue;
        if (label == null || label.trim().isEmpty) continue;
        if (packageId == excludePackage) continue;
        apps.add(
          InstalledApp(
            packageId: packageId,
            name: label.trim(),
            isSystem: app.isSystemApp,
          ),
        );
      }
      apps.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return apps;
    } catch (_) {
      // A missing plugin or a platform that changed shape. An empty list is
      // the honest answer, and the screen shows its empty state rather than
      // taking the tab down.
      return const [];
    }
  }

  /// The app's launcher icon as PNG bytes, or null when it cannot be read.
  ///
  /// A null is cached too: the usual reason is that the app was uninstalled,
  /// and retrying on every rebuild would mean a channel round-trip per frame.
  static Future<Uint8List?> icon(String packageId) async {
    if (!isSupported) return null;
    if (_icons.containsKey(packageId)) return _icons[packageId];
    try {
      final bytes = await UsageStats.getAppIcon(packageId);
      _icons[packageId] = bytes;
      return bytes;
    } catch (_) {
      _icons[packageId] = null;
      return null;
    }
  }

  /// Whether the OS will answer the usage question at all.
  ///
  /// Separate from [usageToday] because an empty usage map is ambiguous — it
  /// is what "nothing was used" and "no permission" both look like. A budget
  /// that cannot read usage is a rule that never fires, and the UI has to be
  /// able to say so rather than showing a progress bar pinned at zero.
  static Future<bool> hasUsageAccess() async {
    if (!isSupported) return false;
    try {
      return await UsageStats.checkUsagePermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Today's foreground time per package, in minutes.
  ///
  /// Empty when usage access has not been granted. That is a real state the UI
  /// has to show — a budget that silently reads zero is a budget that never
  /// fires, which looks exactly like a broken feature.
  static Future<Map<String, int>> usageToday() async {
    if (!isSupported) return const {};
    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      final stats = await UsageStats.queryAndAggregateUsageStats(
        midnight,
        now,
      );
      final usage = <String, int>{};
      for (final entry in stats.entries) {
        final millis = entry.value.totalTimeInForegroundMs ?? 0;
        if (millis <= 0) continue;
        usage[entry.key] = millis ~/ 60000;
      }
      return usage;
    } catch (_) {
      return const {};
    }
  }
}
