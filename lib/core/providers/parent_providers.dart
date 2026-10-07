import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/parent.dart';
import '../services/app_catalog.dart';
import '../services/local_store.dart';
import '../services/parent_service.dart';
import 'app_providers.dart';
import 'shield_providers.dart';
import 'study_providers.dart';

/// The pairing backend for this build.
///
/// Firebase when it initialised, and a service that refuses every call when it
/// did not — the web preview, a build with no project, a phone with no
/// connection at launch. Screens ask [ParentService.available] before offering
/// a control, so the refusal is never something the user walks into.
final parentServiceProvider = Provider<ParentService>((ref) {
  final service = FirebaseParentService.isSupported
      ? FirebaseParentService()
      : const UnavailableParentService();
  ref.onDispose(service.dispose);
  return service;
});

/// The signed-in account id, or null before there is one.
///
/// The profile's uid is the backend's uid — the auth service re-keys the
/// record when a session starts — so this is what Firestore's rules see.
final accountUidProvider = Provider<String?>((ref) {
  final uid = ref.watch(userProvider).uid;
  return uid.isEmpty ? null : uid;
});

// -- Child side --------------------------------------------------------------

/// The parent this device is linked to, if any.
final guardianProvider = StreamProvider<GuardianLink?>((ref) {
  final service = ref.watch(parentServiceProvider);
  final uid = ref.watch(accountUidProvider);
  if (!service.available || uid == null) return Stream.value(null);
  return service.watchGuardian(uid);
});

/// The blocks a parent has set for this device.
///
/// Empty unless a parent is linked, so an unlinked device never asks for a
/// document it has no right to.
final myRemoteBlocksProvider = StreamProvider<RemoteBlocks?>((ref) {
  final service = ref.watch(parentServiceProvider);
  final uid = ref.watch(accountUidProvider);
  if (!service.available || uid == null) return Stream.value(null);
  if (ref.watch(guardianProvider).value == null) return Stream.value(null);
  return service.watchBlocks(uid);
});

/// The security code that gates turning the link off.
///
/// Set by a parent, checked here. It is a speed bump, not a lock: Android
/// cannot stop a child from clearing the app's data or uninstalling it, and
/// the screen that asks for it says so rather than implying otherwise.
class SecurityCodeNotifier extends Notifier<bool> {
  final _random = Random.secure();

  @override
  bool build() => false;

  LocalStore get _store => ref.read(localStoreProvider);

  static String _hash(String code, String salt) =>
      sha256.convert(utf8.encode('$salt:$code')).toString();

  /// Whether a code is set, read from the store during bootstrap.
  void hydrate(String? stored) => state = stored != null && stored.isNotEmpty;

  Future<void> set(String code) async {
    final salt = List.generate(
      16,
      (_) => _random.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await _store.setString(
      StoreKeys.parentSecurity,
      '$salt:${_hash(code, salt)}',
    );
    state = true;
  }

  bool verify(String code) {
    final stored = _store.getString(StoreKeys.parentSecurity);
    if (stored == null) return false;
    final split = stored.indexOf(':');
    if (split <= 0) return false;
    return _hash(code, stored.substring(0, split)) ==
        stored.substring(split + 1);
  }

  Future<void> clear() async {
    await _store.setString(StoreKeys.parentSecurity, '');
    state = false;
  }
}

final securityCodeProvider = NotifierProvider<SecurityCodeNotifier, bool>(
  SecurityCodeNotifier.new,
);

// -- Parent side -------------------------------------------------------------

/// The children on this parent's list.
final childrenProvider = StreamProvider<List<ChildLink>>((ref) {
  final service = ref.watch(parentServiceProvider);
  final uid = ref.watch(accountUidProvider);
  if (!service.available || uid == null) {
    return Stream.value(const <ChildLink>[]);
  }
  return service.watchChildren(uid);
});

/// The child the parent is looking at.
///
/// Held by id rather than by index: a stream that reorders — a child added, a
/// link removed — must not silently move the selection to somebody else.
class SelectedChildNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? uid) => state = uid;
}

final selectedChildProvider = NotifierProvider<SelectedChildNotifier, String?>(
  SelectedChildNotifier.new,
);

/// The child the parent is actually looking at: the chosen one while they are
/// still on the list, and the first child otherwise.
final activeChildProvider = Provider<ChildLink?>((ref) {
  final children = ref.watch(childrenProvider).value ?? const <ChildLink>[];
  if (children.isEmpty) return null;
  final selected = ref.watch(selectedChildProvider);
  return children.where((c) => c.uid == selected).firstOrNull ?? children.first;
});

/// The selected child's summary.
final childProgressProvider = StreamProvider.family<ChildProgress?, String>((
  ref,
  childUid,
) {
  final service = ref.watch(parentServiceProvider);
  if (!service.available) return Stream.value(null);
  return service.watchProgress(childUid);
});

/// The block list set for the selected child.
final childBlocksProvider = StreamProvider.family<RemoteBlocks?, String>((
  ref,
  childUid,
) {
  final service = ref.watch(parentServiceProvider);
  if (!service.available) return Stream.value(null);
  return service.watchBlocks(childUid);
});

/// The apps on the selected child's device, for the parent's picker.
final childCatalogProvider = StreamProvider.family<List<CatalogApp>, String>((
  ref,
  childUid,
) {
  final service = ref.watch(parentServiceProvider);
  if (!service.available) return Stream.value(const <CatalogApp>[]);
  return service.watchCatalog(childUid);
});

/// Whether the parent's security code has been entered on this run.
///
/// Session-only on purpose: the code is what stands between a child and the
/// rules their parent set, so it is asked for again after the app is closed
/// rather than remembered for good.
class ParentLockNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void open() => state = true;

  void lock() => state = false;
}

final parentLockProvider = NotifierProvider<ParentLockNotifier, bool>(
  ParentLockNotifier.new,
);

/// True while a change to the shield has to clear the parent's code first.
///
/// All three parts matter: a linked parent, a code that was actually set —
/// setting one is optional — and this run not having been unlocked already.
final parentLockedProvider = Provider<bool>((ref) {
  if (ref.watch(guardianProvider).value == null) return false;
  if (!ref.watch(securityCodeProvider)) return false;
  return !ref.watch(parentLockProvider);
});

// -- Wiring ------------------------------------------------------------------

/// Keeps the engine in step with the timer and with the parent's rules.
///
/// Read once during bootstrap. The launch push it performs is the point: the
/// accessibility service outlives the app and can be holding rules from before
/// it was closed, including a focus window that has since ended.
final shieldSyncBridgeProvider = Provider<void>((ref) {
  // A parent's rules land in the shield's own state first, so every later
  // rebuild of the config — a toggle, a preset change — carries them too.
  ref.listen(myRemoteBlocksProvider, (previous, next) {
    final blocks = next.value;
    if (blocks == null) return;
    // A parent who is only watching keeps their list, and this is what makes
    // "only watching" mean nothing is enforced rather than nothing is stored.
    ref.read(remoteBlocksProvider.notifier).set(blocks.inForce);
  });
  ref.listen(timerProvider, (previous, next) => syncShield(ref));
  syncShield(ref);
});

/// Publishes this device's summary for a linked parent to read.
///
/// A summary and nothing else: minutes, sessions, the goal, the streak and the
/// subject that led the week. The session log itself stays here — a parent can
/// see whether the work is happening without reading the child's whole day.
final parentProgressPublisherProvider = Provider<void>((ref) {
  Future<void> publish() async {
    final service = ref.read(parentServiceProvider);
    final uid = ref.read(accountUidProvider);
    if (!service.available || uid == null) return;
    if (ref.read(guardianProvider).value == null) return;

    final now = DateTime.now();
    final sessions = ref.read(sessionsProvider.notifier).forDay(now);
    final top = ref.read(topSubjectProvider(StudyRange.week));
    await service.publishProgress(
      uid,
      ChildProgress(
        minutes: ref.read(focusMinutesTodayProvider),
        sessions: sessions.where((s) => s.completed).length,
        goalMinutes: ref.read(todayGoalMinutesProvider),
        streak: ref.read(currentStreakProvider),
        topSubject: top?.name,
        day:
            '${now.year}-${now.month.toString().padLeft(2, '0')}-'
            '${now.day.toString().padLeft(2, '0')}',
        updatedAt: now,
      ),
    );
  }

  ref.listen(sessionsProvider, (previous, next) => unawaited(publish()));
  ref.listen(dailyGoalProvider, (previous, next) => unawaited(publish()));
  ref.listen(guardianProvider, (previous, next) => unawaited(publish()));
  unawaited(publish());
});

/// Publishes this device's app list so a linked parent can choose from it.
///
/// Only while a parent is linked, and only the two fields the picker needs:
/// the package the rule is written against and a name to recognise it by.
/// Nothing about how the apps are used travels with it.
final catalogPublisherProvider = Provider<void>((ref) {
  Future<void> publish() async {
    final service = ref.read(parentServiceProvider);
    final uid = ref.read(accountUidProvider);
    if (!service.available || uid == null) return;
    if (ref.read(guardianProvider).value == null) return;

    final installed = await AppCatalog.installed(
      excludePackage: AppCatalog.selfPackage,
    );
    // System apps are most of the list and none of the intent: a parent
    // blocking the settings app is not what "block their apps" means, and the
    // engine refuses several of them anyway.
    await service.publishCatalog(uid, [
      for (final app in installed)
        if (!app.isSystem)
          CatalogApp(packageId: app.packageId, name: app.name),
    ]);
  }

  // A fresh link is the moment the parent's picker has something to show.
  ref.listen(guardianProvider, (previous, next) => unawaited(publish()));
  unawaited(publish());
});
