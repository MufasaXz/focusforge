import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/study_backup_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:focusforge/core/models/study.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';

import 'dart:convert';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:focusforge/core/services/widget_service.dart';

class MemoryBackup implements StudyBackupBackend {
  final accounts = <String, StudyBackup>{};
  bool failLoad = false;
  bool failSave = false;
  int saves = 0;

  /// Runs while a read is under way, as if the phone kept working.
  Future<void> Function()? duringLoad;
  @override
  Future<StudyBackup?> load(String uid) async {
    if (failLoad) throw StateError('offline');
    final value = accounts[uid];
    await duringLoad?.call();
    return value;
  }

  @override
  Future<void> save(String uid, StudyBackup backup) async {
    saves++;
    if (failSave) throw StateError('offline');
    accounts[uid] = backup;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore store;
  late MemoryBackup backend;
  late StudyBackupService service;
  const alice = UserProfile(
    uid: 'alice',
    isAnonymous: false,
    onboardingComplete: true,
    dailyGoalMinutes: 480,
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
    await store.clearAll();
    backend = MemoryBackup();
    service = StudyBackupService(store, backend);
  });
  tearDown(() => service.dispose());

  test(
    'session-only cloud backup preserves unversioned local settings',
    () async {
      await store.setMap(StoreKeys.user, alice.toJson());
      await store.setList(StoreKeys.subjects, [
        {'id': 'saved-local'},
      ]);
      await store.setBool(StoreKeys.boardOptIn, true);
      final db = FakeFirebaseFirestore();
      await db.doc('users/alice/sessionData/partial').set({
        'id': 'partial',
        'ownerUid': 'alice',
        'minutes': 25,
        'startedAt': 1,
      });
      final partial = StudyBackupService(store, FirebaseStudyBackupBackend(db));
      addTearDown(partial.dispose);
      await partial.connect(alice);
      expect(store.getList(StoreKeys.subjects).single['id'], 'saved-local');
      expect(store.getBool(StoreKeys.boardOptIn), isTrue);
      expect(store.getList(StoreKeys.sessions).single['id'], 'partial');
    },
  );

  for (final remoteRevision in [
    0,
    DateTime.now().millisecondsSinceEpoch - 1000,
  ]) {
    test(
      'unversioned account cache keeps saved settings at revision $remoteRevision',
      () async {
        await store.setMap(StoreKeys.user, alice.toJson());
        await store.setBool(StoreKeys.boardOptIn, false);
        await store.setList(StoreKeys.subjects, [
          {'id': 'old-local'},
        ]);
        backend.accounts['alice'] = StudyBackup(
          settings: {
            StoreKeys.user: jsonEncode(alice.toJson()),
            StoreKeys.boardOptIn: true,
            StoreKeys.subjects: jsonEncode([
              {'id': 'saved-math'},
            ]),
          },
          sessions: [],
          modifiedAt: remoteRevision,
        );
        await service.connect(alice);
        expect(store.getBool(StoreKeys.boardOptIn), isTrue);
        expect(store.getList(StoreKeys.subjects).single['id'], 'saved-math');
        await service.flush();
        expect(
          backend.accounts['alice']!.settings[StoreKeys.boardOptIn],
          isTrue,
        );
      },
    );
  }

  test(
    'canceling restore during a local write cannot replace the next account',
    () async {
      await store.setMap(StoreKeys.user, alice.toJson());
      backend.accounts['alice'] = StudyBackup(
        settings: {
          StoreKeys.subjects: jsonEncode([
            {'id': 'remote-alice'},
          ]),
        },
        sessions: [],
        modifiedAt: DateTime.now().millisecondsSinceEpoch + 1000,
      );
      final started = Completer<void>();
      final resume = Completer<void>();
      const channel = MethodChannel('focusforge/widgets');
      WidgetService.enabled = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            if (!started.isCompleted) {
              started.complete();
              await resume.future;
            }
            return null;
          });
      addTearDown(() {
        WidgetService.enabled = false;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final restoring = service.connect(alice);
      final failed = expectLater(restoring, throwsStateError);
      await started.future;
      service.disconnect();
      await store.setMap(
        StoreKeys.user,
        const UserProfile(uid: 'bob', isAnonymous: false).toJson(),
      );
      await store.setInt(StoreKeys.dailyGoal, 333);
      resume.complete();
      await failed;
      expect(store.getMap(StoreKeys.user)?['uid'], 'bob');
      expect(store.getInt(StoreKeys.dailyGoal), 333);
      await service.flush();
      expect(backend.saves, 0);
    },
  );

  test(
    'offline sessions preserve newer remote settings during reconciliation',
    () async {
      await store.setMap(StoreKeys.user, alice.toJson());
      await store.setList(StoreKeys.subjects, [
        {'id': 'local'},
      ]);
      await service.connect(alice);
      await service.flush();
      service.dispose();
      service = StudyBackupService(store, backend);
      backend.failLoad = true;
      await service.connect(alice);
      await store.setList(StoreKeys.sessions, [
        {'id': 'offline-session', 'ownerUid': 'alice', 'startedAt': 1},
      ]);
      backend.accounts['alice'] = StudyBackup(
        settings: {
          ...backend.accounts['alice']!.settings,
          StoreKeys.subjects: jsonEncode([
            {'id': 'remote-new'},
          ]),
        },
        sessions: [],
        modifiedAt: DateTime.now()
            .add(const Duration(days: 1))
            .millisecondsSinceEpoch,
      );
      backend.failLoad = false;
      await service.flush();
      expect(store.getList(StoreKeys.subjects).single['id'], 'remote-new');
      expect(store.getList(StoreKeys.sessions).single['id'], 'offline-session');
    },
  );

  test('known account opens offline and defers writes until successful reconciliation', () async {
    await store.setMap(StoreKeys.user, alice.toJson());
    await store.setList(StoreKeys.subjects, [
      {'id': 'math'},
    ]);
    await store.setMap(StoreKeys.presets, {'running': true, 'targetEnd': 1234});
    await service.connect(alice);
    await service.flush();
    service.dispose();
    service = StudyBackupService(store, backend);
    backend.failLoad = true;
    final count = backend.saves;
    final restored = await service.connect(alice);
    expect(restored.uid, 'alice');
    expect(store.getMap(StoreKeys.presets)?['targetEnd'], 1234);
    await expectLater(service.flush(), throwsStateError);
    expect(backend.saves, count);
    backend.failLoad = false;
    backend.accounts['alice'] = StudyBackup(
      settings: backend.accounts['alice']!.settings,
      sessions: [
        {'id': 'other-device', 'ownerUid': 'alice', 'startedAt': 1},
      ],
      modifiedAt: 1,
    );
    await service.flush();
    expect(store.getList(StoreKeys.sessions).single['id'], 'other-device');
    expect(backend.saves, greaterThan(count));
  });

  test(
    'failed guest restore cannot replace unknown account settings',
    () async {
      backend.accounts['alice'] = StudyBackup(
        settings: {
          StoreKeys.subjects: jsonEncode([
            {'id': 'remote'},
          ]),
        },
        sessions: [],
        modifiedAt: 1,
      );
      await store.setMap(
        StoreKeys.user,
        const UserProfile(uid: 'guest').toJson(),
      );
      await store.setBool('achievements.linked.guest', false);
      await store.setList(StoreKeys.subjects, [
        {'id': 'guest'},
      ]);
      backend.failLoad = true;
      await expectLater(service.connect(alice), throwsStateError);
      await service.flush();
      expect(
        backend.accounts['alice']!.settings[StoreKeys.subjects],
        contains('remote'),
      );
      expect(store.getList(StoreKeys.subjects).single['id'], 'guest');
      backend.failLoad = false;
      await service.connect(alice);
      expect(store.getList(StoreKeys.subjects).single['id'], 'remote');
    },
  );

  testWidgets(
    'backup retries through a prolonged outage without another edit',
    (tester) async {
      service.dispose();
      service = StudyBackupService(store, backend);
      await store.setMap(StoreKeys.user, alice.toJson());
      await service.connect(alice);
      await service.flush();
      backend.failSave = true;
      await store.setInt(StoreKeys.dailyGoal, 480);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 21));
      final attempts = backend.saves;
      backend.failSave = false;
      await tester.pump(const Duration(seconds: 21));
      expect(backend.saves, greaterThan(attempts));
      expect(backend.accounts['alice']!.settings[StoreKeys.user], isNotNull);
    },
  );

  test('reinstall restores profile and level, and nothing else', () async {
    await store.setMap(StoreKeys.user, alice.toJson());
    await store.setMap(StoreKeys.stats, const {
      'xp': 40,
      'level': 7,
      'creditedSessionIds': ['monday'],
    });
    await store.setList(StoreKeys.subjects, [
      {'id': 'math', 'name': 'Mathematics'},
    ]);
    await store.setMap(StoreKeys.planLibrary, {
      'version': 1,
      'plans': [
        {'id': 'own-plan'},
      ],
    });
    await store.setMap('goal.planner', {
      'version': 2,
      'day': {'totalMinutes': 480},
    });
    await store.setList(StoreKeys.sessions, [
      {
        'id': 'monday',
        'ownerUid': 'alice',
        'startedAt': DateTime(2026, 10, 12).millisecondsSinceEpoch,
        'minutes': 240,
        'completed': true,
      },
    ]);
    await service.connect(alice);
    await service.flush();
    service.disconnect();
    await store.clearAll();
    final restored = await service.connect(
      const UserProfile(uid: 'alice', isAnonymous: false),
    );
    expect(restored.onboardingComplete, isTrue);
    expect(restored.dailyGoalMinutes, 480);
    expect(store.getMap(StoreKeys.stats)?['level'], 7);
    expect(store.getMap(StoreKeys.stats)?['xp'], 40);
    expect(store.getList(StoreKeys.subjects), isEmpty);
    expect(store.getMap(StoreKeys.planLibrary), isNull);
    expect(store.getMap('goal.planner'), isNull);
    expect(store.getList(StoreKeys.sessions), isEmpty);
  });

  test('a name edit on a behind phone never lowers the saved level', () async {
    Map<String, dynamic> stats(int level) => {'xp': 10, 'level': level};
    await store.setMap(StoreKeys.user, alice.toJson());
    await store.setMap(StoreKeys.stats, stats(5));
    await service.connect(alice);
    await service.flush();
    // Another phone reaches level 6 and saves it.
    final other = backend.accounts['alice']!;
    backend.accounts['alice'] = StudyBackup(
      settings: {...other.settings, StoreKeys.stats: jsonEncode(stats(6))},
      sessions: const [],
      modifiedAt: other.modifiedAt + 1000,
    );
    UserProfile? reconciled;
    service.onReconciled = (profile) => reconciled = profile;

    await store.setMap(
      StoreKeys.user,
      alice.copyWith(displayName: 'Alice B').toJson(),
    );
    await service.flush();

    final cloud = backend.accounts['alice']!;
    final cloudStats = jsonDecode(cloud.settings[StoreKeys.stats] as String);
    expect(cloudStats['level'], 6);
    expect(
      jsonDecode(cloud.settings[StoreKeys.user] as String)['displayName'],
      'Alice B',
    );
    expect(store.getMap(StoreKeys.stats)?['level'], 6);
    expect(reconciled?.uid, 'alice');
  });

  test('recovery keeps the further level of the phone and the cloud', () async {
    await store.setMap(StoreKeys.user, alice.toJson());
    await store.setMap(StoreKeys.stats, const {'xp': 5, 'level': 9});
    await store.setInt('study.modified.alice', 1);
    backend.accounts['alice'] = StudyBackup(
      settings: {
        StoreKeys.user: jsonEncode(alice.toJson()),
        StoreKeys.stats: jsonEncode(const {'xp': 50, 'level': 4}),
      },
      sessions: const [],
      modifiedAt: 99,
    );
    await service.connect(alice);
    expect(store.getMap(StoreKeys.stats)?['level'], 9);
  });

  test('progress made during the cloud read is not rolled back', () async {
    Map<String, dynamic> stats(int level) => {'xp': 10, 'level': level};
    await store.setMap(StoreKeys.user, alice.toJson());
    await store.setMap(StoreKeys.stats, stats(5));
    await service.connect(alice);
    await service.flush();
    final saved = backend.accounts['alice']!;
    backend.accounts['alice'] = StudyBackup(
      settings: {...saved.settings, StoreKeys.stats: jsonEncode(stats(6))},
      sessions: const [],
      modifiedAt: saved.modifiedAt + 1000,
    );
    // A session lifts this phone to level 7 while the cloud is being read.
    backend.duringLoad = () async {
      backend.duringLoad = null;
      await store.setMap(StoreKeys.stats, {
        ...stats(7),
        'creditedSessionIds': ['during-read'],
      });
    };
    await store.setMap(
      StoreKeys.user,
      alice.copyWith(displayName: 'Alice B').toJson(),
    );
    await service.flush();
    expect(store.getMap(StoreKeys.stats)?['level'], 7);
    expect(store.getMap(StoreKeys.stats)?['creditedSessionIds'], [
      'during-read',
    ]);
  });

  test('a save racing a higher level keeps the higher one', () async {
    final db = FakeFirebaseFirestore();
    final cloud = FirebaseStudyBackupBackend(db);
    String settingsAt(int level) => jsonEncode({
      StoreKeys.stats: jsonEncode({'xp': 0, 'level': level}),
    });
    // The other phone's level 6 lands after this phone read level 5.
    await db.doc('users/alice/preferences/studyBackup').set({
      'version': 1,
      'ownerUid': 'alice',
      'data': settingsAt(6),
      'modifiedAt': 2,
    });
    await cloud.save(
      'alice',
      StudyBackup(
        settings: {
          StoreKeys.stats: jsonEncode({'xp': 0, 'level': 5}),
          StoreKeys.user: jsonEncode(alice.toJson()),
        },
        sessions: const [],
        modifiedAt: 3,
      ),
    );
    final data = (await db.doc('users/alice/preferences/studyBackup').get())
        .data()!;
    final settings = jsonDecode(data['data'] as String) as Map;
    expect(jsonDecode(settings[StoreKeys.stats] as String)['level'], 6);
    expect(settings.containsKey(StoreKeys.user), isTrue);
  });

  test(
    'nothing but profile, level and sharing consent reaches the cloud',
    () async {
      await store.setMap(StoreKeys.user, alice.toJson());
      await store.setMap(StoreKeys.stats, const {
        'xp': 40,
        'level': 7,
        'creditedSessionIds': ['s-1760000000000000'],
      });
      await store.setBool(StoreKeys.boardOptIn, true);
      await store.setList(StoreKeys.subjects, [
        {'id': 'math'},
      ]);
      await store.setInt(StoreKeys.dailyGoal, 480);
      await store.setList(StoreKeys.sessions, [
        {
          'id': 's-1760000000000000',
          'ownerUid': 'alice',
          'startedAt': 1,
          'minutes': 25,
          'completed': true,
        },
      ]);
      await service.connect(alice);
      await service.flush();
      final cloud = backend.accounts['alice']!;
      expect(cloud.sessions, isEmpty);
      expect(cloud.settings.keys.toSet(), {
        StoreKeys.user,
        StoreKeys.stats,
        StoreKeys.boardOptIn,
      });
      expect(jsonEncode(cloud.settings), isNot(contains('s-1760000000000000')));
      expect(
        store.getList(StoreKeys.sessions).single['id'],
        's-1760000000000000',
      );
    },
  );

  test(
    'signing back in on the same device keeps its local study data',
    () async {
      await store.setMap(StoreKeys.user, alice.toJson());
      await store.setList(StoreKeys.subjects, [
        {'id': 'math'},
      ]);
      await store.setMap(StoreKeys.stats, const {
        'xp': 1,
        'level': 2,
        'creditedSessionIds': ['monday'],
      });
      await store.setList(StoreKeys.sessions, [
        {'id': 'monday', 'ownerUid': 'alice', 'startedAt': 1, 'minutes': 25},
      ]);
      await service.connect(alice);
      await service.flush();
      service.disconnect();
      backend.accounts['alice'] = StudyBackup(
        settings: {
          ...backend.accounts['alice']!.settings,
          StoreKeys.stats: jsonEncode(const {'xp': 9, 'level': 8}),
        },
        sessions: const [],
        modifiedAt: DateTime.now()
            .add(const Duration(days: 1))
            .millisecondsSinceEpoch,
      );
      await service.connect(alice, reconcile: true);
      expect(store.getList(StoreKeys.subjects).single['id'], 'math');
      expect(store.getList(StoreKeys.sessions).single['id'], 'monday');
      final stats = store.getMap(StoreKeys.stats)!;
      expect(stats['level'], 8);
      // The newer level came from the cloud; the receipt that stops this device
      // awarding the same block twice did not, and must survive.
      expect(stats['creditedSessionIds'], ['monday']);
    },
  );

  test(
    'switching accounts never uploads or restores the previous account data',
    () async {
      await store.setMap(StoreKeys.user, alice.toJson());
      await store.setBool('achievements.linked.alice', true);
      await store.setList(StoreKeys.sessions, [
        {
          'id': 'a',
          'ownerUid': 'alice',
          'minutes': 300,
          'startedAt': 1,
          'completed': true,
        },
      ]);
      await store.setList(StoreKeys.subjects, [
        {'id': 'private-a'},
      ]);
      await service.connect(alice);
      await service.flush();
      final bob = await service.connect(
        const UserProfile(uid: 'bob', isAnonymous: false),
      );
      expect(bob.onboardingComplete, isFalse);
      expect(store.getList(StoreKeys.sessions), isEmpty);
      expect(store.getList(StoreKeys.subjects), isEmpty);
      await service.flush();
      expect(backend.accounts['bob']?.sessions, isEmpty);
      await service.connect(
        const UserProfile(uid: 'alice', isAnonymous: false),
      );
      expect(store.getList(StoreKeys.sessions).single['id'], 'a');
      expect(store.getList(StoreKeys.subjects).single['id'], 'private-a');
    },
  );

  test('first guest promotion preserves history once and repeated recovery deduplicates it', () async {
    await store.setMap(
      StoreKeys.user,
      const UserProfile(uid: 'guest', onboardingComplete: true).toJson(),
    );
    await store.setBool('achievements.linked.guest', false);
    await store.setList(StoreKeys.sessions, [
      {
        'id': 'guest-session',
        'ownerUid': 'guest',
        'minutes': 60,
        'startedAt': 1,
        'completed': true,
      },
    ]);
    final restored = await service.connect(alice);
    expect(restored.onboardingComplete, isTrue);
    expect(store.getList(StoreKeys.sessions).single['ownerUid'], 'alice');
    await service.flush();
    await service.connect(alice);
    expect(store.getList(StoreKeys.sessions), hasLength(1));
  });

  test('Firestore backend never uploads sessions', () async {
    final db = FakeFirebaseFirestore();
    final cloud = FirebaseStudyBackupBackend(db);
    await cloud.save(
      'alice',
      StudyBackup(
        settings: const {'goal': 'saved'},
        sessions: [
          FocusSession(
            id: 'session/1',
            subjectId: 'math',
            startedAt: DateTime(2026, 10, 12),
            minutes: 25,
            ownerUid: 'alice',
          ).toJson(),
        ],
        modifiedAt: 100,
      ),
    );
    expect(
      (await db.collection('users/alice/sessionData').get()).docs,
      isEmpty,
    );
    final recovered = await FirebaseStudyBackupBackend(db).load('alice');
    expect(recovered?.settings, {'goal': 'saved'});
    expect(recovered?.sessions, isEmpty);
    expect(await cloud.load('bob'), isNull);
  });

  test(
    'sessions an older build uploaded move to the device, then leave the cloud',
    () async {
      final db = FakeFirebaseFirestore();
      for (var i = 0; i < 405; i++) {
        await db
            .doc('users/alice/sessionData/row$i')
            .set(
              FocusSession(
                id: 'session/$i',
                subjectId: 'math',
                startedAt: DateTime(2026, 10, 12),
                minutes: 25,
                ownerUid: 'alice',
              ).toJson(),
            );
      }
      await db.doc('users/alice/preferences/studyBackup').set({
        'version': 1,
        'ownerUid': 'alice',
        'data': jsonEncode({
          StoreKeys.user: jsonEncode(alice.toJson()),
          StoreKeys.subjects: jsonEncode([
            {'id': 'legacy-math'},
          ]),
        }),
        'modifiedAt': 100,
      });
      final migrating = StudyBackupService(
        store,
        FirebaseStudyBackupBackend(db),
      );
      addTearDown(migrating.dispose);
      await migrating.connect(
        const UserProfile(uid: 'alice', isAnonymous: false),
      );
      expect(store.getList(StoreKeys.sessions), hasLength(405));
      expect(store.getList(StoreKeys.subjects).single['id'], 'legacy-math');
      await migrating.flush();
      expect(
        (await db.collection('users/alice/sessionData').get()).docs,
        isEmpty,
      );
      final saved = await db.doc('users/alice/preferences/studyBackup').get();
      expect(saved.data()?['data'], isNot(contains('legacy-math')));
      // The device copy outlives the cloud copy.
      expect(store.getList(StoreKeys.sessions), hasLength(405));
      expect(store.getList(StoreKeys.subjects).single['id'], 'legacy-math');
    },
  );

  test('a session row loaded after the last read is not deleted', () async {
    final db = FakeFirebaseFirestore();
    final cloud = FirebaseStudyBackupBackend(db);
    final row = {'id': 'seen', 'ownerUid': 'alice', 'startedAt': 1};
    await db.doc('users/alice/sessionData/seen').set(row);
    await cloud.load('alice');
    await db.doc('users/alice/sessionData/late').set({...row, 'id': 'late'});
    await cloud.save(
      'alice',
      const StudyBackup(settings: {}, sessions: [], modifiedAt: 1),
    );
    final left = await db.collection('users/alice/sessionData').get();
    expect(left.docs.map((d) => d.id), ['late']);
  });

  test('changing account abandons the previous accounts live timer', () async {
    final container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    container.read(userProvider.notifier).hydrate(alice);
    container.read(timerProvider.notifier).toggle();
    expect(container.read(timerProvider).running, isTrue);
    container
        .read(userProvider.notifier)
        .hydrate(const UserProfile(uid: 'bob', isAnonymous: false));
    expect(container.read(timerProvider).running, isFalse);
    expect(container.read(timerProvider).segmentOwnerUid, isNull);
    expect(container.read(sessionsProvider), isEmpty);
  });
}
