import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/parent.dart';
import '../services/app_catalog.dart';
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
  if (ref.watch(guardianProvider).valueOrNull == null) {
    return Stream.value(null);
  }
  return service.watchBlocks(uid);
});

/// The code a parent set for this device, as their link record carries it.
///
/// Read rather than stored here: the code belongs to the link, and a link that
/// is gone takes the code with it. A device with no code answers null, and
/// [parentLockedProvider] then never asks.
final parentCodeProvider = Provider<ParentCode?>(
  (ref) => ref.watch(guardianProvider).valueOrNull?.code,
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
  final children =
      ref.watch(childrenProvider).valueOrNull ?? const <ChildLink>[];
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

/// The link record of one child, as their parent sees it.
///
/// The parent's copy of the record is where the code lives, so this is how a
/// parent finds out whether one is set before they offer to change it.
final childGuardianProvider = StreamProvider.family<GuardianLink?, String>((
  ref,
  childUid,
) {
  final service = ref.watch(parentServiceProvider);
  if (!service.available) return Stream.value(null);
  return service.watchGuardian(childUid);
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
  if (ref.watch(guardianProvider).valueOrNull == null) return false;
  if (ref.watch(parentCodeProvider) == null) return false;
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
    // `valueOrNull`, not `value`: an error reading the parent's list must
    // leave the rules as they are, not throw out of the listener.
    final blocks = next.valueOrNull;
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
/// A summary and nothing else: minutes, sessions, the goal, the streak, the
/// subject that led the week and the week's own totals. The session log itself
/// stays here — a parent can see whether the work is happening without reading
/// the child's whole day.
final parentProgressPublisherProvider = Provider<void>((ref) {
  Future<void> publish() async {
    final service = ref.read(parentServiceProvider);
    final uid = ref.read(accountUidProvider);
    if (!service.available || uid == null) return;
    if (ref.read(guardianProvider).valueOrNull == null) return;

    final now = DateTime.now();
    final sessions = ref.read(sessionsProvider.notifier).forDay(now);
    final top = ref.read(topSubjectProvider(StudyRange.week));
    // The week's shape, oldest day first, in minutes — the same bars the
    // child's own dashboard draws, so the two cannot disagree.
    final bars = ref.read(rangeBarsProvider(StudyRange.week));
    final weekSessions = ref
        .read(sessionsProvider)
        .where((s) => s.completed && _withinLastWeek(s.startedAt, now))
        .length;
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
        weekMinutes: bars.fold(0, (sum, b) => sum + (b.hours * 60).round()),
        weekSessions: weekSessions,
        weekDays: [for (final bar in bars) (bar.hours * 60).round()],
      ),
    );
  }

  ref.listen(sessionsProvider, (previous, next) => unawaited(publish()));
  ref.listen(dailyGoalProvider, (previous, next) => unawaited(publish()));
  ref.listen(guardianProvider, (previous, next) => unawaited(publish()));
  unawaited(publish());
});

/// Whether [at] falls inside the seven days the week chart covers — today and
/// the six before it, matching `rangeBarsProvider(StudyRange.week)`.
bool _withinLastWeek(DateTime at, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final start = today.subtract(const Duration(days: 6));
  final day = DateTime(at.year, at.month, at.day);
  return !day.isBefore(start) && !day.isAfter(today);
}

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
    if (ref.read(guardianProvider).valueOrNull == null) return;

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
