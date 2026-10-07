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

  /// Every app on the device, system apps included.
  ///
  /// The whole device, unfiltered: this answers what is installed, and a
  /// caller that wants a narrower list narrows it. The Shield's list is the
  /// one that does — it drops system apps, because they are most of the
  /// device and none of the intent, and keeps only those that already carry a
  /// rule. `isSystem` is carried through for that decision.
  ///
  /// The packages that genuinely cannot be blocked are named by the engine
  /// itself and arrive through `NativeShieldService.protectedPackages()`; the
  /// screen marks those instead of hiding them, so the switch never lies.
  /// FocusForge is the one package dropped outright, since blocking yourself
  /// is not a rule anyone wants.
  static Future<List<InstalledApp>> installed({String? excludePackage}) async {
    if (!isSupported) return const [];
    try {
      final raw = await UsageStats.queryInstalledApps(includeSystem: true);
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
      apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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

  /// `UsageEvents.Event.ACTIVITY_RESUMED`, and `MOVE_TO_FOREGROUND` before
  /// Android 10. The same integer, and the same meaning.
  static const int _resumed = 1;

  /// `ACTIVITY_PAUSED` / `MOVE_TO_BACKGROUND`.
  static const int _paused = 2;

  /// `ACTIVITY_STOPPED`. Not every app raises a pause on the way out, so this
  /// closes a session too — guarded so it can never close one twice.
  static const int _stopped = 23;

  /// Today's foreground time per package, in minutes.
  ///
  /// Empty when usage access has not been granted. That is a real state the UI
  /// has to show — a budget that silently reads zero is a budget that never
  /// fires, which looks exactly like a broken feature.
  ///
  /// Summed from the event stream rather than read from
  /// `queryAndAggregateUsageStats`, which is the obvious call and the wrong
  /// one. That API returns the system's own daily buckets: the bucket for
  /// today is written as the day goes on, so the session the user is in right
  /// now is missing from it, and the figure it does return is the bucket's
  /// total rather than a sum of what actually happened. It also silently drops
  /// packages it has no bucket for. Pairing resumed/paused events and closing
  /// whatever is still open at [DateTime.now] gives the number the system's
  /// own Digital Wellbeing screen shows.
  static Future<Map<String, int>> usageToday() async {
    if (!isSupported) return const {};
    try {
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      final events = await UsageStats.queryEvents(midnight, now);
      return foregroundMinutes(events, until: now);
    } catch (_) {
      return const {};
    }
  }

  /// Folds a day's usage events into minutes of foreground time per package.
  ///
  /// Split out from [usageToday] so the arithmetic is reachable without a
  /// platform channel — this is the part that was wrong, and it is pure.
  ///
  /// An app's time is the span between a resume and the matching pause. The
  /// two are counted rather than toggled, because one app can have several
  /// activities alive at once: a pause that takes the count to zero ends the
  /// session, and any other pause is an activity the user moved off inside the
  /// same app. Anything still open at [until] is counted up to it — that is
  /// the session in progress, and leaving it out is what made the number look
  /// stuck.
  static Map<String, int> foregroundMinutes(
    Iterable<EventUsageInfo> events, {
    required DateTime until,
  }) {
    final open = <String, int>{};
    final since = <String, int>{};
    final total = <String, int>{};

    for (final event in events) {
      final packageId = event.packageName;
      final type = event.eventTypeValue;
      final at = int.tryParse(event.timeStamp ?? '');
      if (packageId == null ||
          packageId.isEmpty ||
          type == null ||
          at == null) {
        continue;
      }

      final count = open[packageId] ?? 0;
      if (type == _resumed) {
        if (count == 0) since[packageId] = at;
        open[packageId] = count + 1;
      } else if ((type == _paused || type == _stopped) && count > 0) {
        // Guarded rather than trusted: the query is documented to answer in
        // time order, and a negative span folded into the total would silently
        // subtract real time from the day.
        final startedAt = since[packageId] ?? at;
        if (at > startedAt) {
          total[packageId] = (total[packageId] ?? 0) + (at - startedAt);
          // The span just counted ends here, and the app is still in front —
          // so the next one starts here too. Leaving `since` where it was
          // counts everything between the first resume and the last pause
          // once per activity, which on a feed with three activities open
          // trebles the day.
          since[packageId] = at;
        }
        open[packageId] = count - 1;
        if (count - 1 == 0) since.remove(packageId);
      }
    }

    // Whatever is still open is being used right now.
    final end = until.millisecondsSinceEpoch;
    for (final entry in open.entries) {
      if (entry.value <= 0) continue;
      final startedAt = since[entry.key];
      if (startedAt == null || end <= startedAt) continue;
      total[entry.key] = (total[entry.key] ?? 0) + (end - startedAt);
    }

    // Rounded, not truncated: an app used for 50 seconds is a minute of the
    // day, and dropping the remainder from every row is how a day's total ends
    // up an hour short. Nothing is dropped for being small — a package that
    // was opened at all was opened, and the card's empty state has to mean
    // what it says.
    return {
      for (final entry in total.entries)
        if (entry.value > 0) entry.key: (entry.value / 60000).round(),
    };
  }
}
