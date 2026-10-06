import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/seed.dart';

/// Apps the user chose to block during onboarding, keyed by package id.
///
/// The selection has two homes and needs one. Apps that map to a real feed
/// shield are written through to `feedGroupsProvider`; the rest — Reddit,
/// Snapchat, and anything the user opts into from the moderate tier — have no
/// row in the shield catalogue yet and exist only for the length of the flow.
/// The completion summary counts the user's actual choice, so it reads here
/// rather than from the shield provider, which would under-report.
class BlockedAppsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {
    for (final app in SeedData.detectableApps)
      if (app.tier == 0) app.packageId,
  };

  void toggle(String packageId, bool selected) {
    state = selected ? {...state, packageId} : ({...state}..remove(packageId));
  }
}

final blockedAppsProvider = NotifierProvider<BlockedAppsNotifier, Set<String>>(
  BlockedAppsNotifier.new,
);
