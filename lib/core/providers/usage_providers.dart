import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/shield.dart';
import '../services/app_catalog.dart';
import 'shield_providers.dart';

/// The apps installed on this device.
///
/// Read once per session and held, rather than re-queried per rebuild: the
/// list is a few hundred entries, and the platform call behind it walks the
/// package manager. It is invalidated on resume, because the user may well
/// have installed something while they were away.
final installedAppsProvider = FutureProvider<List<InstalledApp>>(
  (ref) => AppCatalog.installed(excludePackage: AppCatalog.selfPackage),
);

/// Whether the OS will answer the usage question at all.
///
/// A time budget reads this before it can claim to be enforcing anything: with
/// no usage access the engine cannot know how long an app has been open, so
/// the budget is armed but inert, and the screen has to say so.
final usageAccessProvider = FutureProvider<bool>(
  (ref) => AppCatalog.hasUsageAccess(),
);

/// Today's foreground time per package, in minutes.
///
/// An empty map is a real answer, not a failure: it is what a device with no
/// usage-access grant returns. Screens have to show that state rather than
/// render a row of zeroes that looks like measured calm.
final appUsageTodayProvider = FutureProvider<Map<String, int>>(
  (ref) => AppCatalog.usageToday(),
);

/// One app's screen time for today.
@immutable
class ScreenTimeRow {
  const ScreenTimeRow({
    required this.packageId,
    required this.name,
    required this.minutes,
  });

  final String packageId;
  final String name;
  final int minutes;
}

/// The day's screen time, busiest first, with real app names.
///
/// System packages are dropped: the launcher and the system UI are always at
/// the top of the raw list and neither is something the user chose to spend
/// time in, so leaving them in would bury the one number that means something.
/// A package with no name in the installed list is dropped with them.
final screenTimeTodayProvider = FutureProvider<List<ScreenTimeRow>>((ref) async {
  final usage = await ref.watch(appUsageTodayProvider.future);
  if (usage.isEmpty) return const [];

  final apps = await ref.watch(installedAppsProvider.future);
  final names = {for (final app in apps) app.packageId: app.name};

  final rows = <ScreenTimeRow>[
    for (final entry in usage.entries)
      if (names[entry.key] case final String name)
        ScreenTimeRow(
          packageId: entry.key,
          name: name,
          minutes: entry.value,
        ),
  ]..sort((a, b) => b.minutes.compareTo(a.minutes));
  return rows;
});

/// The rule list with today's real usage folded in.
///
/// Usage is read from the platform rather than stored on the entry — it keeps
/// changing while the app is not running, so a stored copy is a number that is
/// already wrong by the time anyone reads it. Entries with no package have no
/// usage to read and stay at zero.
final enrichedWhitelistProvider = Provider<List<WhitelistEntry>>((ref) {
  final usage = ref.watch(appUsageTodayProvider).valueOrNull;
  final entries = ref.watch(whitelistProvider);
  if (usage == null || usage.isEmpty) return entries;

  return [
    for (final entry in entries)
      entry.copyWith(
        usedMinutes: entry.packageId == null
            ? 0
            : (usage[entry.packageId] ?? 0),
      ),
  ];
});
