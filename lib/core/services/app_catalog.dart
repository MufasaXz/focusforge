import 'package:flutter/foundation.dart';
import 'package:usage_stats/usage_stats.dart';

/// One app installed on the device.
@immutable
class InstalledApp {
  const InstalledApp({
    required this.packageId,
    required this.name,
    required this.isSystem,
    this.category,
  });

  final String packageId;
  final String name;
  final bool isSystem;

  /// Android's declared app category, when the phone reports one.
  final int? category;
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
            category: app.category,
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

  /// `SCREEN_NON_INTERACTIVE`, `KEYGUARD_SHOWN` and `DEVICE_SHUTDOWN`. After
  /// any of them nothing is in front of the user, whatever the last app event
  /// said: an app that never reported its pause stops counting here.
  static const int _screenOff = 16;
  static const int _keyguardShown = 17;
  static const int _shutdown = 26;

  /// How far before a window its events are read. An app already open when
  /// the window starts is then seen opening, and its time inside the window
  /// counts; everything is clipped to the window, so nothing before it does.
  static const Duration _lookback = Duration(hours: 3);

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
      final events = await UsageStats.queryEvents(
        midnight.subtract(_lookback),
        now,
      );
      return foregroundMinutes(events, from: midnight, until: now);
    } catch (_) {
      return const {};
    }
  }

  /// Foreground minutes per package between [start] and [end], from the same
  /// event stream as [usageToday]. Android keeps these events for a limited
  /// number of days, so older ranges can come back empty.
  static Future<Map<String, int>> usageBetween(
    DateTime start,
    DateTime end,
  ) async {
    if (!isSupported || !end.isAfter(start)) return const {};
    try {
      final events = await UsageStats.queryEvents(
        start.subtract(_lookback),
        end,
      );
      return foregroundMinutes(events, from: start, until: end);
    } catch (_) {
      return const {};
    }
  }

  /// Folds a window's usage events into minutes of foreground time per
  /// package, counted the way the system's own Digital Wellbeing counts.
  ///
  /// Split out so the arithmetic is reachable without a platform channel —
  /// this is the part that has been wrong, and it is pure.
  ///
  /// One app is in front at a time. It is in front from its first resumed
  /// activity until the last of them pauses or stops, until another app
  /// comes to the front, or until the screen goes off or locks — whichever
  /// is first. Each activity is tracked by its class, so a stop that a
  /// previous screen reports late cannot end the current one, and an app
  /// that never reports its pause stops counting the moment anything else
  /// takes over. Time is clipped to [from]–[until]; whatever is still in
  /// front at [until] is counted up to it, because that is the session the
  /// user is in while they look at the number.
  ///
  /// The sum is kept in milliseconds and only then cut into whole minutes,
  /// with the leftover seconds handed to the apps they are largest for. The
  /// apps' minutes then add up to the window's own rounded total, where
  /// rounding each app separately could drift a day by many minutes.
  static Map<String, int> foregroundMinutes(
    Iterable<EventUsageInfo> events, {
    required DateTime until,
    DateTime? from,
  }) {
    final windowStart = from?.millisecondsSinceEpoch;
    final windowEnd = until.millisecondsSinceEpoch;
    final spent = <String, int>{};

    String? front;
    var since = 0;
    // The front app's resumed activities. A named activity is resumed or it
    // is not; events without a class name are counted, so two of those still
    // need two pauses.
    final resumed = <String?, int>{};

    void close(int at) {
      final package = front;
      if (package == null) return;
      final begin = windowStart != null && since < windowStart
          ? windowStart
          : since;
      final end = at < windowEnd ? at : windowEnd;
      if (end > begin) spent[package] = (spent[package] ?? 0) + (end - begin);
      front = null;
      resumed.clear();
    }

    for (final event in events) {
      final type = event.eventTypeValue;
      final at = int.tryParse(event.timeStamp ?? '');
      if (type == null || at == null) continue;
      if (type == _screenOff || type == _keyguardShown || type == _shutdown) {
        close(at);
        continue;
      }
      final package = event.packageName;
      if (package == null || package.isEmpty) continue;
      final activity = event.className;
      if (type == _resumed) {
        if (front != package) {
          close(at);
          front = package;
          since = at;
        }
        resumed[activity] = activity == null ? (resumed[activity] ?? 0) + 1 : 1;
      } else if ((type == _paused || type == _stopped) && front == package) {
        final count = resumed[activity] ?? 0;
        if (count <= 0) continue;
        if (count == 1) {
          resumed.remove(activity);
        } else {
          resumed[activity] = count - 1;
        }
        if (resumed.isEmpty) close(at);
      }
    }
    close(windowEnd);

    final minutes = <String, int>{};
    final leftover = <String, int>{};
    var whole = 0;
    var all = 0;
    for (final MapEntry(key: package, value: ms) in spent.entries) {
      minutes[package] = ms ~/ 60000;
      leftover[package] = ms % 60000;
      whole += ms ~/ 60000;
      all += ms;
    }
    var spare = (all / 60000).round() - whole;
    for (final package
        in leftover.keys.toList()
          ..sort((a, b) => leftover[b]!.compareTo(leftover[a]!))) {
      if (spare <= 0) break;
      minutes[package] = minutes[package]! + 1;
      spare--;
    }
    return {
      for (final entry in minutes.entries)
        if (entry.value > 0) entry.key: entry.value,
    };
  }
}
