import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/models/study.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/services/local_store.dart';

class FailSessionWriteOnce extends InMemorySharedPreferencesStore {
  FailSessionWriteOnce() : super.empty();
  bool fail = true;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.ff.${StoreKeys.sessions}' && fail) {
      fail = false;
      throw StateError('disk temporarily unavailable');
    }
    return super.setValue(type, key, value);
  }
}

class FailTimerWriteOnce extends InMemorySharedPreferencesStore {
  FailTimerWriteOnce() : super.empty();
  bool fail = true;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.ff.${StoreKeys.presets}' && fail) {
      fail = false;
      throw StateError('timer disk temporarily unavailable');
    }
    return super.setValue(type, key, value);
  }
}

class FailStatsWriteOnce extends InMemorySharedPreferencesStore {
  FailStatsWriteOnce() : super.empty();
  bool fail = true;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.ff.${StoreKeys.stats}' && fail) {
      fail = false;
      throw StateError('stats disk temporarily unavailable');
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'failed aggregate storage retries without losing or duplicating XP',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      await store.clearAll();
      final platform = FailStatsWriteOnce();
      SharedPreferencesStorePlatform.instance = platform;
      final c = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(c.dispose);
      c
          .read(userProvider.notifier)
          .hydrate(const UserProfile(uid: 'alice', isAnonymous: false));
      final t = c.read(timerProvider.notifier);
      t.hydrate({
        'phase': 'focus',
        'running': true,
        'targetEnd': DateTime.now()
            .subtract(const Duration(seconds: 1))
            .millisecondsSinceEpoch,
        'segmentOwnerUid': 'alice',
        'segmentId': 'retry-stats',
      });
      await Future<void>.delayed(Duration.zero);
      expect(
        store.getMap(StoreKeys.presets)!['pendingCompletions'],
        isNotEmpty,
      );
      t.sync();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final durable = await platform.getAll();
      final saved =
          jsonDecode(durable['flutter.ff.${StoreKeys.stats}'] as String) as Map;
      expect(saved['totalSessions'], 1);
      expect(saved['xp'], 0);
      expect(saved['level'], 2);
      expect(store.getMap(StoreKeys.presets)!['pendingCompletions'], isEmpty);
    },
  );
  for (final credited in [false, true]) {
    test(
      'cold recovery finishes aggregate credit exactly once, credited=$credited',
      () async {
        SharedPreferences.setMockInitialValues({});
        final store = await LocalStore.open();
        await store.clearAll();
        final c = ProviderContainer(
          overrides: [localStoreProvider.overrideWithValue(store)],
        );
        addTearDown(c.dispose);
        c
            .read(userProvider.notifier)
            .hydrate(const UserProfile(uid: 'alice', isAnonymous: false));
        final session = FocusSession(
          id: 'interrupted',
          subjectId: '',
          startedAt: DateTime.now(),
          minutes: 25,
          ownerUid: 'alice',
        );
        await store.setList(StoreKeys.sessions, [session.toJson()]);
        c
            .read(sessionsProvider.notifier)
            .hydrate(store.getList(StoreKeys.sessions));
        final initial = credited
            ? const GamificationStats(
                level: 2,
                totalSessions: 1,
                totalFocusHours: 25 / 60,
                creditedSessionIds: ['interrupted'],
              )
            : const GamificationStats();
        c.read(statsProvider.notifier).hydrate(initial);
        final snapshot = {
          'running': false,
          'pendingCompletions': [session.toJson()],
          'pendingStats': ['interrupted'],
        };
        final timer = c.read(timerProvider.notifier)..hydrate(snapshot);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(c.read(statsProvider).totalSessions, 1);
        expect(c.read(statsProvider).xp, 0);
        expect(c.read(statsProvider).level, 2);
        expect(store.getMap(StoreKeys.stats)!['creditedSessionIds'], [
          'interrupted',
        ]);
        timer.hydrate(snapshot);
        await Future<void>.delayed(Duration.zero);
        expect(c.read(statsProvider).totalSessions, 1);
        expect(c.read(statsProvider).xp, 0);
        expect(c.read(statsProvider).level, 2);
      },
    );
  }
  test(
    'account switch retains a pending completion until its owner returns',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      await store.clearAll();
      final c = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(c.dispose);
      c
          .read(userProvider.notifier)
          .hydrate(const UserProfile(uid: 'alice', isAnonymous: false));
      final t = c.read(timerProvider.notifier);
      final expired = {
        'phase': 'focus',
        'running': true,
        'targetEnd': DateTime.now()
            .subtract(const Duration(seconds: 1))
            .millisecondsSinceEpoch,
        'segmentOwnerUid': 'alice',
        'segmentId': 'pending-alice',
      };
      await store.setMap(StoreKeys.presets, expired);
      SharedPreferencesStorePlatform.instance = FailTimerWriteOnce();
      t.hydrate(expired);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(sessionsProvider), isEmpty);
      c
          .read(userProvider.notifier)
          .hydrate(const UserProfile(uid: 'bob', isAnonymous: false));
      await Future<void>.delayed(Duration.zero);
      expect(c.read(sessionsProvider), isEmpty);
      expect(
        store.getMap(StoreKeys.presets)!['pendingCompletions'],
        isNotEmpty,
      );
      c
          .read(userProvider.notifier)
          .hydrate(const UserProfile(uid: 'alice', isAnonymous: false));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(sessionsProvider).single.id, 'pending-alice');
      expect(c.read(statsProvider).totalSessions, 1);
    },
  );
  test(
    'failed session persistence remains recoverable after sync retry',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      await store.clearAll();
      final platform = FailSessionWriteOnce();
      SharedPreferencesStorePlatform.instance = platform;
      final c = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(c.dispose);
      c
          .read(userProvider.notifier)
          .hydrate(const UserProfile(uid: 'alice', isAnonymous: false));
      final t = c.read(timerProvider.notifier);
      final end = DateTime.now().subtract(const Duration(seconds: 1));
      t.hydrate({
        'phase': 'focus',
        'running': true,
        'targetEnd': end.millisecondsSinceEpoch,
        'segmentStartedAt': end
            .subtract(const Duration(minutes: 25))
            .millisecondsSinceEpoch,
        'segmentOwnerUid': 'alice',
        'segmentId': 'stable-completed-block',
      });
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(sessionsProvider), hasLength(1));
      t.sync();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final durable = await platform.getAll();
      final durableSessions = jsonDecode(
        durable['flutter.ff.${StoreKeys.sessions}'] as String? ?? '[]',
      ) as List;
      final snapshot = jsonDecode(
        durable['flutter.ff.${StoreKeys.presets}'] as String,
      ) as Map;
      final journal = snapshot['pendingCompletions'] as List;
      expect(
        durableSessions.isNotEmpty || journal.isNotEmpty,
        isTrue,
        reason:
            'a retry may acknowledge a block only after its session is durable',
      );
      expect(c.read(statsProvider).totalSessions, 1);
      expect(c.read(statsProvider).totalFocusHours, closeTo(25 / 60, 0.0001));
      expect(c.read(statsProvider).xp, 0);
      expect(c.read(statsProvider).level, 2);
      t.sync();
      await Future<void>.delayed(Duration.zero);
      expect(c.read(statsProvider).totalSessions, 1);
    },
  );
}
