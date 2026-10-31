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
final screenTimeTodayProvider = FutureProvider<List<ScreenTimeRow>>((
  ref,
) async {
  final usage = await ref.watch(appUsageTodayProvider.future);
  if (usage.isEmpty) return const [];

  final apps = await ref.watch(installedAppsProvider.future);
  final names = {for (final app in apps) app.packageId: app.name};

  final rows = <ScreenTimeRow>[
    for (final entry in usage.entries)
      if (names[entry.key] case final String name)
        ScreenTimeRow(packageId: entry.key, name: name, minutes: entry.value),
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

/// The packages the engine refuses to cover, asked of the engine itself.
final protectedPackagesProvider = FutureProvider<Set<String>>(
  (ref) => ref.watch(shieldServiceProvider).protectedPackages(),
);

/// The packages with a launcher icon, asked of the engine itself.
///
/// Empty means the engine could not say — an older install, a platform with
/// no engine — and the list falls back to its previous filter rather than
/// rendering as though nothing on the device can be opened.
final launchablePackagesProvider = FutureProvider<Set<String>>(
  (ref) => ref.watch(shieldServiceProvider).launchablePackages(),
);

/// One row of the shield's app list: an app, its rule, and today's usage.
@immutable
class ShieldAppRow {
  const ShieldAppRow({
    required this.packageId,
    required this.name,
    required this.isSystem,
    required this.usedMinutes,
    required this.rule,
  });

  final String packageId;
  final String name;
  final bool isSystem;
  final int usedMinutes;

  /// The user's rule for this app, or null when there is none.
  final WhitelistEntry? rule;

  /// True when a rule is in force. "Always allowed" is a rule too, but it is
  /// the absence of a restriction, so it reads as off.
  bool get isRestricted => rule?.tier.isEnforced ?? false;
}

/// Every app on the device worth a row, joined with its rule and today's usage.
///
/// One list rather than a list of rules plus a picker: with the whole device
/// on screen, "add an app" stops being a step and a rule becomes something you
/// switch on a row that is already there.
///
/// Two kinds of package never reach the list.
///
/// An app with no launcher icon is one the user cannot open, so no block can
/// ever fire on it — every service, every overlay, every vendor stub. The
/// launchable set is asked of the engine, which resolves packages to
/// activities anyway, so the picker's list and the engine's reach answer the
/// same question.
///
/// This used to be decided by `isSystem` instead, which was right while the
/// app held `QUERY_ALL_PACKAGES` and could see the whole device. It stopped
/// being right the moment the manifest narrowed to a `<queries>` declaration:
/// a preinstalled browser, mail client or video app is a *system* app with a
/// launcher icon, and the filter was hiding most of what a student opens the
/// Shield tab to close. `isSystem` is still carried on the row, because the
/// row still says so — it is no longer what decides.
///
/// An engine that cannot answer returns an empty set, and the list falls back
/// to the old filter rather than rendering empty.
///
/// And the packages the engine refuses to cover — the keyboard, the launcher,
/// the status bar, the settings app, this app — are dropped outright rather
/// than listed with an inert switch: a control that cannot do anything is
/// worse than no row. An app that already carries a rule is kept whatever
/// else is true of it, because hiding it would leave a restriction running
/// with nothing on screen that could turn it off.
final shieldAppRowsProvider = Provider<List<ShieldAppRow>>((ref) {
  final apps = ref.watch(installedAppsProvider).valueOrNull;
  if (apps == null) return const [];

  final usage = ref.watch(appUsageTodayProvider).valueOrNull ?? const {};
  final protectedSet =
      ref.watch(protectedPackagesProvider).valueOrNull ?? const {};
  final launchable =
      ref.watch(launchablePackagesProvider).valueOrNull ?? const <String>{};

  final rules = <String, WhitelistEntry>{
    for (final entry in ref.watch(whitelistProvider))
      if (entry.packageId case final String id) id: entry,
  };

  bool openable(InstalledApp app) =>
      launchable.isEmpty ? !app.isSystem : launchable.contains(app.packageId);

  return [
    for (final app in apps)
      if (!protectedSet.contains(app.packageId) &&
          (openable(app) || rules.containsKey(app.packageId)))
        ShieldAppRow(
          packageId: app.packageId,
          name: app.name,
          isSystem: app.isSystem,
          usedMinutes: usage[app.packageId] ?? 0,
          rule: rules[app.packageId],
        ),
  ];
});
