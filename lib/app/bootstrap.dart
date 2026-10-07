import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/shield.dart';
import '../core/models/user.dart';
import '../core/providers/app_providers.dart';
import '../core/providers/audio_providers.dart';
import '../core/providers/parent_providers.dart';
import '../core/providers/shield_providers.dart';
import '../core/providers/social_providers.dart';
import '../core/providers/study_providers.dart';
import '../core/services/auth_service.dart';
import '../core/services/firebase_auth_service.dart';
import '../core/services/local_store.dart';
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

  final container = ProviderContainer(
    overrides: [
      localStoreProvider.overrideWithValue(store),
      authServiceProvider.overrideWithValue(authService),
    ],
  );

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
  //
  // `getList` returns the same empty list for a missing key as for a stored
  // `[]`, so the raw string is read alongside it: no key means a first run,
  // which keeps the seed catalogue; a stored empty list means the user has
  // genuinely removed every subject and must stay empty.
  final subjectsJson = store.getString(StoreKeys.subjects);
  container
      .read(subjectsProvider.notifier)
      .hydrate(subjectsJson == null ? null : store.getList(StoreKeys.subjects));
  container
      .read(sessionsProvider.notifier)
      .hydrate(store.getList(StoreKeys.sessions));
  // The custom plan goes in before the timer: the timer stores an index into
  // the preset list, and a plan hydrated after it would leave the index
  // pointing one slot past the end of a list that had not grown yet.
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

  // -- Parent control --------------------------------------------------------
  //
  // The security code is a hash on this device, set by a parent; hydrating it
  // here is what lets the Parent control page know whether one is armed before
  // it offers to turn the link off.
  container
      .read(securityCodeProvider.notifier)
      .hydrate(store.getString(StoreKeys.parentSecurity));

  // Reading the bridge installs the timer → engine and parent → engine paths
  // and pushes the whole config once. The engine outlives the app and can be
  // holding rules from before it was closed — including a focus window that
  // has since ended — so the launch push is what reconciles the two sides
  // rather than a nicety.
  container.read(shieldSyncBridgeProvider);
  // And a linked child publishes its summary for the parent to read. Nothing
  // is sent while no parent is linked.
  container.read(parentProgressPublisherProvider);
  // The app list a parent picks blocks from, published on the same terms.
  container.read(catalogPublisherProvider);

  // -- Social ----------------------------------------------------------------
  container
      .read(achievementsProvider.notifier)
      .hydrate(store.getBoolMap(StoreKeys.achievements));
  container
      .read(notificationsProvider.notifier)
      .hydrate(store.getMap(StoreKeys.notifications));

  // -- Audio -----------------------------------------------------------------
  container
      .read(activeSoundsProvider.notifier)
      .hydrate(
        store
            .getList(StoreKeys.ambientActive)
            .map((m) => m['id'] as String?)
            .whereType<String>()
            .toSet(),
        store.getDoubleMap(StoreKeys.ambientVolumes),
      );

  // Bridge the auth layer into the user store.
  //
  // `AuthService` owns minting an identity; `UserNotifier` owns everything
  // else about the profile. Without this subscription the two can disagree —
  // the auth call succeeds, writes a real account to storage, and then the
  // next `UserNotifier.save()` from any later screen overwrites it with the
  // blank cold-install record. Subscribing here means every present and future
  // sign-in path is covered, rather than each call site having to remember.
  // Never cancelled on purpose: this container is the app's root scope and
  // lives exactly as long as the process does.
  container.read(authServiceProvider).changes.listen((profile) {
    if (profile != null) container.read(userProvider.notifier).hydrate(profile);
  });

  // Warm the router so the first navigation resolves its redirect immediately
  // rather than after a frame.
  container.read(routerProvider);

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
    return LocalAuthService(store);
  }

  try {
    await Firebase.initializeApp();
    debugPrint('[auth] Firebase initialised: using FirebaseAuthService.');
    return FirebaseAuthService(store);
  } catch (error) {
    debugPrint(
      '[auth] Firebase unavailable ($error): using the local account store.',
    );
    return LocalAuthService(store);
  }
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
/// Call this *after* `deleteAccount()`. The wipe below is deliberately the
/// last write, except for the two values written after it: the one-shot
/// demo-history marker and an explicit empty subject list. The onboarding that
/// follows a deletion is not a first run, and must not seed demo sessions —
/// or the seed catalogue — over the user's blank slate.
Future<void> resetPersistedState(ProviderContainer container) async {
  final store = container.read(localStoreProvider);

  // Subjects are user data, so the list is emptied outright rather than left
  // to fall back to the seed catalogue. Their counters are derived from the
  // session log, so clearing the list is what zeroes the breakdown.
  for (final subject in container.read(subjectsProvider)) {
    await container.read(subjectsProvider.notifier).remove(subject.id);
  }

  // Stop the ambient mixer before dropping its state; invalidating the set
  // alone would leave audio playing with no visible control. The mixer keeps
  // its own volume map, so clear that too — otherwise the next toggle would
  // play at a volume the reset slider no longer shows.
  await container.read(activeSoundsProvider.notifier).clear();
  container
      .read(ambientMixerProvider)
      .restore(active: const {}, volumes: const {});

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
  container.invalidate(achievementsProvider);
  container.invalidate(notificationsProvider);
  container.invalidate(volumesProvider);

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
  timer.setPreset(0);
  timer.setSubject(null);

  await store.clearAll();
  // The wipe erased the empty subject list the removals above wrote, and
  // an absent key reads as a first run — which would restore the seed
  // catalogue. Writing the empty list back keeps the deleted state deleted.
  await store.setList(StoreKeys.subjects, const []);
}
