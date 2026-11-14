import 'package:firebase_core/firebase_core.dart';

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/shield.dart';
import '../core/models/user.dart';
import '../core/providers/app_providers.dart';
import '../core/providers/audio_providers.dart';
import '../core/providers/goal_planner_providers.dart';
import '../core/providers/shield_providers.dart';
import '../core/providers/social_providers.dart';
import '../core/providers/study_providers.dart';
import '../core/providers/usage_providers.dart';
import '../core/providers/usage_stats_providers.dart';
import '../core/services/auth_service.dart';
import '../core/services/app_attestation.dart';
import '../core/services/firebase_auth_service.dart';
import '../core/services/firestore_cache.dart';
import '../core/services/local_store.dart';
import '../core/services/native_privacy.dart';
import '../core/services/study_backup_service.dart';
import '../features/assistant/assistant_memory.dart';
import '../features/assistant/chat/chat_controller.dart';
import '../features/assistant/nudges/pip_nudges.dart';
import 'router.dart';

/// Opens the store and rebuilds every persisted notifier from it.
///
/// This all happens *before* the first frame, which is deliberate: reading
/// `SharedPreferences` is synchronous once the plugin has resolved, so there is
/// no loading state to design and no flash of default data. Hydrating lazily
/// behind the first paint would mean the dashboard briefly renders the wrong
/// numbers and the theme briefly renders the wrong colours.
///
/// Returns the container so `main()` can hand it to
/// [UncontrolledProviderScope]. Building the container here — rather than
/// letting `ProviderScope` create one — is what makes pre-frame hydration
/// possible.
Future<ProviderContainer> bootstrap() async {
  final store = await LocalStore.open();

  // Pick the account backend before the container exists: the override below
  // is what the `changes` bridge and every screen will read, and the choice
  // must be settled before the first frame.
  final authService = await _openAuthService(store);
  // Migrate the older sign-out behaviour before any screen hydrates it.
  if (!authService.signedIn &&
      !authService.restorationPending &&
      store.hasLinkedActiveProfile) {
    await store.suspendAccount();
  }

  final container = ProviderContainer(
    overrides: [
      localStoreProvider.overrideWithValue(store),
      authServiceProvider.overrideWithValue(authService),
    ],
  );

  authService.onSessionCleared = () =>
      resetPersistedState(container, preserveSignedOutAccounts: true);

  // -- Account & preferences -------------------------------------------------
  container
      .read(themeSettingsProvider.notifier)
      .hydrate(
        store.getString(StoreKeys.theme),
        store.getString(StoreKeys.palette),
        store.getBool(StoreKeys.amoled),
      );

  final userJson = store.getMap(StoreKeys.user);
  if (userJson != null) {
    container
        .read(userProvider.notifier)
        .hydrate(UserProfile.fromJson(userJson));
  }

  // Install before optional sharing starts. SDK-originated sign-out keeps
  // local history but must close account gates, just like the UI action.
  authService.changes.listen((profile) {
    if (profile != null) {
      if (authService.current?.uid != profile.uid) return;
      hydrateStudyAccount(container, store);
      container.read(userProvider.notifier).hydrate(profile);
    } else {
      if (authService.signedIn) return;
      if (authService.restorationPending) {
        // Credential changes precede an awaited cloud restore. Stop the old
        // segment before that wait, including a guest segment being linked.
        container.read(timerProvider.notifier).setPreset(0);
        container.read(timerProvider.notifier).setSubject(null);
      }
      final local = container.read(userProvider);
      if (!local.isAnonymous) {
        // Gate closure is synchronous; a delayed whole-profile disk write
        // must never overwrite a sign-in that arrives just after this event.
        container
            .read(userProvider.notifier)
            .hydrate(local.copyWith(isAnonymous: true));
      }
    }
  });
  if (authService.usesRemoteCredentials && !authService.signedIn) {
    final local = container.read(userProvider);
    if (!local.isAnonymous) {
      container
          .read(userProvider.notifier)
          .hydrate(local.copyWith(isAnonymous: true));
    }
  }

  final statsJson = store.getMap(StoreKeys.stats);
  if (statsJson != null) {
    container
        .read(statsProvider.notifier)
        .hydrate(GamificationStats.fromJson(statsJson));
  }

  container
      .read(dailyGoalProvider.notifier)
      .hydrate(
        store.getInt(StoreKeys.dailyGoal),
        store.getMap(StoreKeys.dailyGoalDays),
      );

  container
      .read(clockFaceProvider.notifier)
      .hydrate(store.getString(StoreKeys.clockFace));

  // -- Study -----------------------------------------------------------------
  // The stored catalogue contains only user choices. A missing key and an
  // explicitly empty list both restore as empty, without adding templates.
  container
      .read(subjectsProvider.notifier)
      .hydrate(store.getList(StoreKeys.subjects));
  container
      .read(sessionsProvider.notifier)
      .hydrate(store.getList(StoreKeys.sessions));
  // Restore the plan library before the timer resolves its saved identity.
  container
      .read(customPlanProvider.notifier)
      .hydrate(store.getMap(StoreKeys.customPlan));
  // The timer snapshot carries the deadline of a segment that was running
  // when the process died. Hydrating it after the session log means a block
  // that finished while the app was away is recovered into the full log.
  container
      .read(timerProvider.notifier)
      .hydrate(store.getMap(StoreKeys.presets));

  // -- Shield ----------------------------------------------------------------
  container
      .read(whitelistProvider.notifier)
      .hydrate(store.getList(StoreKeys.whitelistTiers));
  container
      .read(youtubeRulesProvider.notifier)
      .hydrate(store.getMap(StoreKeys.youtubeRules));
  container
      .read(strictModeProvider.notifier)
      .hydrate(store.getMap(StoreKeys.strictMode));
  container
      .read(breathEventsProvider.notifier)
      .hydrate(store.getList(StoreKeys.breathEvents));

  // Parent control kept a copy of the child's blocked apps here. The feature
  // is gone; the key is deleted rather than left behind as an empty map.
  await store.remove('shield.parentCache');
  container
      .read(appListConsentProvider.notifier)
      .hydrate(store.getBool(StoreKeys.appListConsent));
  container.read(shieldSyncBridgeProvider);

  // -- Social ----------------------------------------------------------------
  container
      .read(achievementsProvider.notifier)
      .hydrate(store.getBoolMap(StoreKeys.achievements));
  container.listen(achievementSyncProvider, (_, _) {});
  container
      .read(notificationsProvider.notifier)
      .hydrate(store.getMap(StoreKeys.notifications));
  // Opting in is the whole of "appear on the board": nothing is published
  // until it is on, and reading it back is what keeps this device's row in
  // step with the week it has actually studied.
  container
      .read(boardOptInProvider.notifier)
      .hydrate(store.getBool(StoreKeys.boardOptIn));
  container.read(leaderboardPublisherProvider);
  container.read(groupPublisherProvider);

  // -- Audio -----------------------------------------------------------------
  container
      .read(activeSoundsProvider.notifier)
      .hydrate(store.getDoubleMap(StoreKeys.ambientVolumes));
  // Older builds saved the playing tracks to light them on launch, while
  // they stayed silent. Nothing reads that list now.
  await store.remove(StoreKeys.ambientActive);

  // Warm the router so the first navigation resolves its redirect immediately
  // rather than after a frame.
  container.read(routerProvider);

  watchAssistantOwner(container, store);

  // Paint the local shell and recovery surface while the server responds.
  // The changes bridge above adopts the complete restored snapshot together.
  unawaited(authService.restore().catchError((Object error) => null));

  return container;
}

/// Opens the best available account backend.
///
/// Firebase is an upgrade, never a requirement: a user with no network, a
/// build without the native config, or a platform Firebase does not support
/// must still get a working app. `initializeApp()` is therefore wrapped in a
/// catch-all — it can throw an [Error] (for example [UnimplementedError] on a
/// platform with no Firebase implementation), not just an [Exception] — and
/// every failure falls back to the on-device implementation.
///
/// Web is skipped outright: the Firebase project has no web app registered,
/// so `initializeApp()` would throw and take the web preview build down. The
/// reason is logged once so a developer can see which backend is live.
Future<AuthService> _openAuthService(LocalStore store) async {
  if (kIsWeb) {
    debugPrint('[auth] web build: using the local account store.');
    return GuestOnlyAuthService(store);
  }

  try {
    await Firebase.initializeApp();
    try {
      await activateAppAttestation();
    } catch (_) {
      // Monitoring rollout: an attestation outage must not create a new guest
      // identity for someone with an existing Firebase account.
      debugPrint('[auth] App attestation unavailable.');
    }
    // Configure native persistence before its first platform call, then
    // erase older disk data before opening cloud listeners.
    await prepareFirestoreCache(FirebaseFirestore.instance);
    debugPrint('[auth] Firebase initialised: using FirebaseAuthService.');
    return FirebaseAuthService(
      store,
      studyBackup: StudyBackupService(
        store,
        FirebaseStudyBackupBackend(FirebaseFirestore.instance),
      ),
    );
  } catch (_) {
    debugPrint('[auth] Firebase unavailable: using the local account store.');
    return GuestOnlyAuthService(store);
  }
}

/// Keeps Pip's memory and chat with the account they belong to: when a
/// different account takes over this device, Pip starts from that account's
/// own memory, and its reminders are set again for it.
void watchAssistantOwner(ProviderContainer container, LocalStore store) {
  container.listen<String>(userProvider.select((user) => user.uid), (
    from,
    to,
  ) async {
    if (store.restoredAccountUid == to) {
      store.restoredAccountUid = null;
      container.invalidate(assistantMemoryProvider);
      container.invalidate(chatProvider);
      return;
    }
    if (from == null || from == to || from.isEmpty || to.isEmpty) return;
    // A guest that was never linked becoming an account is the same person,
    // and keeps what they told Pip, as the backup keeps their study.
    if (store.getBool('achievements.linked.$from') == false) return;
    // The outgoing account's reminders can name its tasks; the shell sets
    // the new account's on its next sync.
    unawaited(PipNudges.clear());
    await container
        .read(assistantMemoryProvider.notifier)
        .switchAccount(from, to);
    container.invalidate(chatProvider);
  });
}

/// Restore the private account snapshot before publishing its linked profile.
void hydrateStudyAccount(ProviderContainer container, LocalStore store) {
  if (store.restoredAccountUid != null &&
      store.restoredAccountUid == store.getMap(StoreKeys.user)?['uid']) {
    container
        .read(themeSettingsProvider.notifier)
        .hydrate(
          store.getString(StoreKeys.theme),
          store.getString(StoreKeys.palette),
          store.getBool(StoreKeys.amoled),
        );
    container
        .read(clockFaceProvider.notifier)
        .hydrate(store.getString(StoreKeys.clockFace));
    container
        .read(whitelistProvider.notifier)
        .hydrate(store.getList(StoreKeys.whitelistTiers));
    container
        .read(youtubeRulesProvider.notifier)
        .hydrate(store.getMap(StoreKeys.youtubeRules));
    container
        .read(strictModeProvider.notifier)
        .hydrate(store.getMap(StoreKeys.strictMode));
    container
        .read(breathEventsProvider.notifier)
        .hydrate(store.getList(StoreKeys.breathEvents));
    container
        .read(appListConsentProvider.notifier)
        .hydrate(store.getBool(StoreKeys.appListConsent));
    container
        .read(notificationsProvider.notifier)
        .hydrate(store.getMap(StoreKeys.notifications));
    container
        .read(volumesProvider.notifier)
        .hydrate(store.getDoubleMap(StoreKeys.ambientVolumes));
    container.invalidate(planLibraryProvider);
    container.invalidate(usageCategoryOverridesProvider);
  }
  container
      .read(sessionsProvider.notifier)
      .hydrate(store.getList(StoreKeys.sessions));
  container
      .read(subjectsProvider.notifier)
      .hydrate(store.getList(StoreKeys.subjects));
  container
      .read(customPlanProvider.notifier)
      .hydrate(store.getMap(StoreKeys.customPlan));
  container
      .read(dailyGoalProvider.notifier)
      .hydrate(
        store.getInt(StoreKeys.dailyGoal),
        store.getMap(StoreKeys.dailyGoalDays),
      );
  container
      .read(statsProvider.notifier)
      .hydrate(GamificationStats.fromJson(store.getMap(StoreKeys.stats) ?? {}));
  container.invalidate(focusGoalPlannerProvider);
  container
      .read(boardOptInProvider.notifier)
      .hydrate(store.getBool(StoreKeys.boardOptIn));
}

/// Puts every persisted notifier back to its cold-start value and wipes the
/// store — the memory half of "Delete account".
///
/// `AuthService.deleteAccount()` can only clear the store: it cannot see the
/// notifiers, and the ones it leaves populated write themselves straight back
/// on their next save — which is how a "deleted" log reappeared on the next
/// launch. Resetting them here, in the file that already knows how to hydrate
/// every one, keeps memory and storage telling the same story.
///
/// Call this after account deletion. Reset live providers before clearing
/// persistence, then retain the deleted-credential marker and empty subject
/// catalogue so the next onboarding flow starts from the blank state.
Future<void> resetPersistedState(
  ProviderContainer container, {
  bool preserveSignedOutAccounts = false,
}) async {
  final store = container.read(localStoreProvider);
  final deletedCredential = store.getString('auth.deletedCredential');
  await container.read(achievementsProvider.notifier).suspendForDeletion();

  // Subjects are user data, so the list is emptied outright rather than left
  // to retain a previous catalogue. Their counters are derived from the
  // session log, so clearing the list is what zeroes the breakdown.
  for (final subject in container.read(subjectsProvider)) {
    await container.read(subjectsProvider.notifier).remove(subject.id);
  }

  // Stop the ambient mixer before dropping its state; invalidating the set
  // alone would leave audio playing with no visible control. The mixer keeps
  // its own volume map, so clear that too — otherwise the next toggle would
  // play at a volume the reset slider no longer shows.
  await container.read(activeSoundsProvider.notifier).clear();
  container.read(ambientMixerProvider).restore(volumes: const {});

  // Everything below rebuilds to its `build()` default on the next read — the
  // same value a cold install starts from. Invalidate rather than hydrate:
  // every nullable hydrate no-ops on null, so "hydrating with nothing" would
  // silently leave most of these populated.
  container.invalidate(themeSettingsProvider);
  container.invalidate(clockFaceProvider);
  container.invalidate(sessionsProvider);
  container.invalidate(dailyGoalProvider);
  container.invalidate(whitelistProvider);
  container.invalidate(youtubeRulesProvider);
  container.invalidate(strictModeProvider);
  container.invalidate(breathEventsProvider);
  container.invalidate(notificationsProvider);
  container.invalidate(volumesProvider);
  container.invalidate(boardOptInProvider);
  // Agreement to the app-list disclosure was given by the deleted account's
  // owner. The wipe below removes the stored answer; this removes the live one,
  // or the next setup could read the installed-app list without asking.
  container.invalidate(appListConsentProvider);

  // Every shield mutation funnels through `syncShield`, so invalidation alone
  // would leave the platform layer holding the deleted configuration. Writing
  // the default strict-mode value is the one public path that triggers a full
  // re-sync — it reads the freshly rebuilt app rules and YouTube switches.
  await container
      .read(strictModeProvider.notifier)
      .update(const StrictModeConfig());

  // The profile carries the onboarding flag the router reads, so it is
  // blanked explicitly rather than left to a rebuild. Same for the stats
  // aggregate, whose empty value is the whole point of a deletion. Neither
  // write is persisted — the wipe below is the last word.
  container.read(statsProvider.notifier).hydrate(const GamificationStats());
  container.read(userProvider.notifier).hydrate(const UserProfile());

  // The timer persists a snapshot too, and a block left running would log
  // itself into the wiped store. Reset through public methods rather than
  // invalidating: the focus screen subscribes to `completions` once in
  // initState, and a rebuilt notifier would close that stream under it.
  final timer = container.read(timerProvider.notifier);
  await timer.discardPendingHistory();
  await container.read(planLibraryProvider.notifier).clear();
  timer.setPreset(0);
  timer.setSubject(null);

  await store.clearAll(preserveSignedOutAccounts: preserveSignedOutAccounts);
  // These notifiers read the store in build(). Rebuild after the wipe so Home
  // cannot carry a deleted user's target or app groups into the welcome flow,
  // or write those groups back with the next change.
  container.invalidate(focusGoalPlannerProvider);
  container.invalidate(usageCategoryOverridesProvider);
  // Pip's chat, exam, reminders and online-answers consent belong to the
  // deleted account too, and its reminders are already set with Android.
  container.invalidate(assistantMemoryProvider);
  container.invalidate(chatProvider);
  await PipNudges.clear();
  await NativePrivacy.erase();
  if (deletedCredential != null) {
    await store.setString('auth.deletedCredential', deletedCredential);
  }
  container.invalidate(achievementsProvider);
  // Persist the blank catalogue for a fresh onboarding flow.
  await store.setList(StoreKeys.subjects, const []);
}
