import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/core/models/study.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/social_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/achievement_service.dart';
import 'package:focusforge/core/services/auth_service.dart';
import 'package:focusforge/app/bootstrap.dart';

import 'dart:async';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore store;
  late ProviderContainer container;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
  });

  setUp(() async {
    await store.clearAll();
    container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    await container
        .read(userProvider.notifier)
        .save(const UserProfile(uid: 'alice', isAnonymous: false));
    container.read(achievementsProvider.notifier).hydrate(const {});
    addTearDown(() => container.dispose());
  });

  Future<void> earnFirstFocus() async {
    await container
        .read(sessionsProvider.notifier)
        .record(
          FocusSession(
            id: 'alice-session',
            subjectId: 'math',
            startedAt: DateTime(2026, 1, 10, 12),
            minutes: 25,
          ),
        );
    await container.read(achievementsProvider.notifier).refresh();
  }

  bool firstFocusUnlocked() => container
      .read(achievementsProvider)
      .singleWhere((badge) => badge.id == 'first_focus')
      .unlocked;

  test(
    'another account cannot inherit badges or unlock them from old sessions',
    () async {
      await earnFirstFocus();
      expect(firstFocusUnlocked(), isTrue);
      await container
          .read(userProvider.notifier)
          .save(const UserProfile(uid: 'bob', isAnonymous: false));
      await container.read(achievementsProvider.notifier).refresh();
      expect(firstFocusUnlocked(), isFalse);
      await container
          .read(userProvider.notifier)
          .save(const UserProfile(uid: 'alice', isAnonymous: false));
      expect(firstFocusUnlocked(), isTrue);
    },
  );

  test(
    'logout and a later restart retain earned badges and their dates',
    () async {
      await earnFirstFocus();
      final earned = container
          .read(achievementsProvider)
          .singleWhere((badge) => badge.id == 'first_focus')
          .unlockedAt;
      await container
          .read(userProvider.notifier)
          .save(const UserProfile(uid: 'alice', isAnonymous: true));
      container.dispose();
      container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      container
          .read(userProvider.notifier)
          .hydrate(UserProfile.fromJson(store.getMap(StoreKeys.user)!));
      container
          .read(achievementsProvider.notifier)
          .hydrate(store.getBoolMap(StoreKeys.achievements));
      await container
          .read(userProvider.notifier)
          .save(const UserProfile(uid: 'alice', isAnonymous: false));
      expect(firstFocusUnlocked(), isTrue);
      expect(
        container
            .read(achievementsProvider)
            .singleWhere((badge) => badge.id == 'first_focus')
            .unlockedAt
            ?.millisecondsSinceEpoch,
        earned?.millisecondsSinceEpoch,
      );
    },
  );

  test(
    'legacy earned badges migrate without inventing an earned date',
    () async {
      await container.read(achievementsProvider.notifier).flushLocal();
      container.dispose();
      await store.clearAll();
      await store.setBoolMap(StoreKeys.achievements, {'week_warrior': true});
      container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      container
          .read(userProvider.notifier)
          .hydrate(const UserProfile(uid: 'alice', isAnonymous: false));
      container
          .read(achievementsProvider.notifier)
          .hydrate(store.getBoolMap(StoreKeys.achievements));
      await container.read(achievementsProvider.notifier).flushLocal();
      final badge = container
          .read(achievementsProvider)
          .singleWhere((badge) => badge.id == 'week_warrior');
      expect(badge.unlocked, isTrue);
      expect(isUnknownUnlockTime(badge.unlockedAt), isTrue);
      expect(store.getMap(StoreKeys.achievementAccounts)?['alice'], {
        'week_warrior': 0,
      });
    },
  );

  test(
    'cloud recovery merges months-old badges without relocking local earns',
    () async {
      await earnFirstFocus();
      await container.read(achievementsProvider.notifier).restoreBackup(
        'alice',
        {'week_warrior': 1735689600000, 'first_focus': 1704067200000},
      );
      expect(container.read(unlockedCountProvider), 2);
      expect(container.read(achievementsProvider.notifier).earnedTimes, {
        'first_focus': 1704067200000,
        'week_warrior': 1735689600000,
      });
      await container
          .read(achievementsProvider.notifier)
          .restoreBackup('alice', {});
      expect(container.read(unlockedCountProvider), 2);
      await container
          .read(userProvider.notifier)
          .save(const UserProfile(uid: 'bob', isAnonymous: false));
      await container.read(achievementsProvider.notifier).restoreBackup(
        'alice',
        {'month_king': 0},
      );
      expect(container.read(unlockedCountProvider), 0);
    },
  );

  test(
    'offline backup remains pending and retries the locally earned cabinet',
    () async {
      await container.read(achievementsProvider.notifier).flushLocal();
      container.dispose();
      final auth = _RemoteAuth(store);
      await auth.signInWithEmail('alice@example.com', 'password');
      final remote = _AchievementBackend()..failWrites = true;
      addTearDown(remote.close);
      addTearDown(auth.dispose);
      container = ProviderContainer(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          authServiceProvider.overrideWithValue(auth),
          achievementServiceProvider.overrideWithValue(remote),
        ],
      );
      await container
          .read(userProvider.notifier)
          .save(const UserProfile(uid: 'alice', isAnonymous: false));
      container.read(achievementsProvider.notifier).hydrate(const {});
      container.listen(achievementSyncProvider, (_, _) {});
      await earnFirstFocus();
      await container.read(achievementSyncProvider)();
      expect(
        container.read(achievementBackupStatusProvider),
        AchievementBackupStatus.pending,
      );
      expect(firstFocusUnlocked(), isTrue);
      remote.failWrites = false;
      await container.read(achievementSyncProvider)();
      expect(remote.saved['alice']?['first_focus'], isPositive);
      expect(
        container.read(achievementBackupStatusProvider),
        AchievementBackupStatus.saved,
      );
      remote.emit('alice', {'week_warrior': 1735689600000});
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(container.read(unlockedCountProvider), 2);
      await container
          .read(userProvider.notifier)
          .save(const UserProfile(uid: 'bob', isAnonymous: false));
      remote.emit('alice', {'month_king': 0});
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(container.read(unlockedCountProvider), 0);
    },
  );

  test('first guest account link preserves guest earns without giving away a signed-out account cabinet', () async {
    await container.read(achievementsProvider.notifier).flushLocal();
    container.dispose();
    await store.clearAll();
    container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    container
        .read(userProvider.notifier)
        .hydrate(const UserProfile(uid: 'guest'));
    await store.setBool('achievements.linked.guest', false);
    container.read(achievementsProvider.notifier).hydrate(const {});
    await earnFirstFocus();
    await container
        .read(userProvider.notifier)
        .save(const UserProfile(uid: 'alice', isAnonymous: false));
    expect(firstFocusUnlocked(), isTrue);
    await container
        .read(userProvider.notifier)
        .save(const UserProfile(uid: 'alice', isAnonymous: true));
    await container
        .read(userProvider.notifier)
        .save(const UserProfile(uid: 'bob', isAnonymous: false));
    expect(firstFocusUnlocked(), isFalse);
    await container
        .read(userProvider.notifier)
        .save(const UserProfile(uid: 'alice', isAnonymous: false));
    expect(firstFocusUnlocked(), isTrue);
  });

  test(
    'deletion cannot resurrect an account cabinet through queued local writes',
    () async {
      await earnFirstFocus();
      await container
          .read(userProvider.notifier)
          .save(const UserProfile(uid: 'bob', isAnonymous: false));
      await resetPersistedState(container);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(store.getMap(StoreKeys.achievementAccounts), isNull);
      expect(store.getBoolMap(StoreKeys.achievements), isEmpty);
      expect(container.read(unlockedCountProvider), 0);
    },
  );

  test('a different restored credential cannot claim a legacy cabinet before bootstrap', () async {
    await container.read(achievementsProvider.notifier).flushLocal();
    container.dispose();
    await store.clearAll();
    await store.setMap(
      StoreKeys.user,
      const UserProfile(uid: 'alice', isAnonymous: false).toJson(),
    );
    await store.setBoolMap(StoreKeys.achievements, {'first_focus': true});
    await store.prepareAchievementIdentity('bob');
    await store.setMap(
      StoreKeys.user,
      const UserProfile(uid: 'bob', isAnonymous: false).toJson(),
    );
    container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    container
        .read(userProvider.notifier)
        .hydrate(UserProfile.fromJson(store.getMap(StoreKeys.user)!));
    container
        .read(achievementsProvider.notifier)
        .hydrate(store.getBoolMap(StoreKeys.achievements));
    expect(firstFocusUnlocked(), isFalse);
    expect(store.getMap(StoreKeys.achievementAccounts)?['alice'], {
      'first_focus': 0,
    });
  });

  test('a focus segment keeps its starting account through pause, switching and recovery', () async {
    final timer = container.read(timerProvider.notifier);
    timer.start();
    timer.pause();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final snapshot = store.getMap(StoreKeys.presets)!;
    expect(snapshot['segmentOwnerUid'], 'alice');
    await container
        .read(userProvider.notifier)
        .save(const UserProfile(uid: 'bob', isAnonymous: false));
    timer.hydrate({
      ...snapshot,
      'running': true,
      'targetEnd': DateTime.now()
          .subtract(const Duration(seconds: 1))
          .millisecondsSinceEpoch,
    });
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await container.read(achievementsProvider.notifier).refresh();
    expect(container.read(sessionsProvider), isEmpty);
    expect(store.getMap(StoreKeys.presets)!['pendingCompletions'], isNotEmpty);
    expect(firstFocusUnlocked(), isFalse);
    timer.start();
    expect(container.read(timerProvider).segmentOwnerUid, 'bob');
  });

  test(
    'backup parser rejects unknown IDs and impossible or wrongly typed dates',
    () {
      expect(
        readAchievementTimes({
          'first_focus': 0,
          'week_warrior': 1735689600000,
          'made_up': 1,
          'month_king': -1,
          'night_owl': '2026',
          'early_bird': 1.5,
          'deep_diver': 253402300800000,
        }),
        {'first_focus': 0, 'week_warrior': 1735689600000},
      );
      expect(
        mergeAchievementTimes(
          {'first_focus': 0, 'week_warrior': 1800000000000},
          {'first_focus': 1735689600000, 'week_warrior': 1704067200000},
        ),
        {'first_focus': 1735689600000, 'week_warrior': 1704067200000},
      );
    },
  );
}

class _RemoteAuth extends LocalAuthService {
  _RemoteAuth(super.store);
  @override
  bool get usesRemoteCredentials => true;
}

class _AchievementBackend implements AchievementService {
  final _streams = <String, StreamController<Map<String, int>>>{};
  final saved = <String, Map<String, int>>{};
  bool failWrites = false;
  @override
  bool get available => true;
  @override
  Stream<Map<String, int>> watch(String uid) =>
      (_streams[uid] ??= StreamController<Map<String, int>>.broadcast()).stream;
  void emit(String uid, Map<String, int> values) => _streams[uid]?.add(values);
  @override
  Future<void> save(String uid, Map<String, int> unlockedAt) async {
    if (failWrites) throw StateError('offline');
    saved[uid] = mergeAchievementTimes(saved[uid] ?? {}, unlockedAt);
  }

  Future<void> close() async {
    for (final stream in _streams.values) {
      await stream.close();
    }
  }
}
