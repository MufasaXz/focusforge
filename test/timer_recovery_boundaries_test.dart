import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focusforge/core/models/study.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/widget_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
    await store.clearAll();
  });
  ProviderContainer container() => ProviderContainer(
    overrides: [localStoreProvider.overrideWithValue(store)],
  );
  Future<TimerNotifier> randomTimer(ProviderContainer c) async {
    await c
        .read(planLibraryProvider.notifier)
        .save(
          const CustomPlan(
            id: 'r',
            name: 'Random',
            goalMinutes: 120,
            focusMinutes: 30,
            randomMinMinutes: 20,
            randomMaxMinutes: 40,
          ),
        );
    final t = c.read(timerProvider.notifier);
    await t.setPreset(
      c.read(presetsProvider).indexWhere((p) => p.key == 'custom:r'),
    );
    return t;
  }

  test(
    'completed live random block and stale snapshot replay is counted once',
    () async {
      final c = container();
      addTearDown(c.dispose);
      final t = await randomTimer(c);
      final started = DateTime(2026, 10, 16, 2, 0, 0, 17, 123);
      final end = DateTime.now().subtract(const Duration(seconds: 1));
      final stale = {
        'presetKey': 'custom:r',
        'phase': 'focus',
        'running': true,
        'targetEnd': end.millisecondsSinceEpoch,
        'segmentStartedAt': started.millisecondsSinceEpoch,
        'sampledFocusMs': 2220000,
        'remainingMs': 1,
      };
      t.state = TimerState(
        running: true,
        targetEnd: end,
        presetIndex: t.state.presetIndex,
        segmentStartedAt: started,
        sampledFocusDuration: const Duration(minutes: 37),
      );
      t.tick();
      await Future<void>.delayed(Duration.zero);
      expect(c.read(sessionsProvider), hasLength(1));
      t.hydrate(stale);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(sessionsProvider), hasLength(1));
    },
  );
  test('queued recovery must not append old account session after identity changes', () async {
    final c = container();
    addTearDown(c.dispose);
    c
        .read(userProvider.notifier)
        .hydrate(const UserProfile(uid: 'alice', isAnonymous: false));
    final t = await randomTimer(c);
    final end = DateTime.now().subtract(const Duration(seconds: 1));
    t.hydrate({
      'presetKey': 'custom:r',
      'phase': 'focus',
      'running': true,
      'targetEnd': end.millisecondsSinceEpoch,
      'segmentStartedAt': end
          .subtract(const Duration(minutes: 37))
          .millisecondsSinceEpoch,
      'sampledFocusMs': 2220000,
      'remainingMs': 1,
      'segmentOwnerUid': 'alice',
    });
    c
        .read(userProvider.notifier)
        .hydrate(const UserProfile(uid: 'bob', isAnonymous: false));
    c.read(sessionsProvider.notifier).hydrate(const []);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(sessionsProvider), isEmpty);
  });
  test('recovery journal remains durable until session persistence confirms', () async {
    final c = container();
    addTearDown(c.dispose);
    final t = await randomTimer(c);
    final end = DateTime.now().subtract(const Duration(seconds: 1));
    final expired = {
      'presetKey': 'custom:r',
      'phase': 'focus',
      'running': true,
      'targetEnd': end.millisecondsSinceEpoch,
      'segmentStartedAt': end
          .subtract(const Duration(minutes: 37))
          .millisecondsSinceEpoch,
      'sampledFocusMs': 2220000,
      'remainingMs': 1,
    };
    await store.setMap(StoreKeys.presets, expired);
    final writingSession = Completer<void>();
    final release = Completer<void>();
    const channel = MethodChannel('focusforge/widgets');
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    WidgetService.enabled = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          if (store.getList(StoreKeys.sessions).isNotEmpty &&
              !writingSession.isCompleted) {
            writingSession.complete();
            await release.future;
          }
          return null;
        });
    addTearDown(() {
      if (!release.isCompleted) release.complete();
      WidgetService.enabled = false;
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    t.hydrate(expired);
    await writingSession.future;
    final snapshot = store.getMap(StoreKeys.presets)!;
    expect(
      snapshot['pendingCompletions'],
      isNotEmpty,
      reason:
          'an unfinished session write must keep a durable completion journal',
    );
    release.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(store.getMap(StoreKeys.presets)!['pendingCompletions'], isEmpty);
  });
  test('snapshot keeps an exact segment ID and journal replay never double credits', () async {
    final c = container();
    addTearDown(c.dispose);
    final t = await randomTimer(c);
    t.start();
    await Future<void>.delayed(Duration.zero);
    final snapshot = store.getMap(StoreKeys.presets)!;
    final id = snapshot['segmentId'] as String;
    expect(id, 's-${t.state.segmentStartedAt!.microsecondsSinceEpoch}');
    final end = DateTime.now().subtract(const Duration(seconds: 1));
    final expired = {...snapshot, 'targetEnd': end.millisecondsSinceEpoch};
    t.hydrate(expired);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(sessionsProvider).single.id, id);
    final stats = c.read(statsProvider);
    t.hydrate(expired);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(sessionsProvider), hasLength(1));
    expect(c.read(statsProvider).totalSessions, stats.totalSessions);
    expect(c.read(statsProvider).xp, stats.xp);
  });

  test(
    'identity change during session write prevents late aggregate credit',
    () async {
      final c = container();
      addTearDown(c.dispose);
      c
          .read(userProvider.notifier)
          .hydrate(const UserProfile(uid: 'alice', isAnonymous: false));
      final t = await randomTimer(c);
      final writingSession = Completer<void>();
      final release = Completer<void>();
      const channel = MethodChannel('focusforge/widgets');
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      WidgetService.enabled = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            if (store.getList(StoreKeys.sessions).isNotEmpty &&
                !writingSession.isCompleted) {
              writingSession.complete();
              await release.future;
            }
            return null;
          });
      addTearDown(() {
        if (!release.isCompleted) release.complete();
        WidgetService.enabled = false;
        debugDefaultTargetPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final end = DateTime.now().subtract(const Duration(seconds: 1));
      t.hydrate({
        'presetKey': 'custom:r',
        'phase': 'focus',
        'running': true,
        'targetEnd': end.millisecondsSinceEpoch,
        'segmentStartedAt': end
            .subtract(const Duration(minutes: 37))
            .millisecondsSinceEpoch,
        'sampledFocusMs': 2220000,
        'remainingMs': 1,
        'segmentOwnerUid': 'alice',
      });
      await writingSession.future;
      c
          .read(userProvider.notifier)
          .hydrate(const UserProfile(uid: 'bob', isAnonymous: false));
      c.read(sessionsProvider.notifier).hydrate(const []);
      c.read(statsProvider.notifier).hydrate(const GamificationStats());
      release.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(sessionsProvider), isEmpty);
      expect(c.read(statsProvider).totalSessions, 0);
      expect(store.getMap(StoreKeys.presets)!['pendingCompletions'], isEmpty);
    },
  );
  test(
    'a journal snapshot survives restart while preserving older saved sessions',
    () async {
      final original = container();
      addTearDown(original.dispose);
      final originalTimer = await randomTimer(original);
      final now = DateTime.now();
      final old = FocusSession(
        id: 'older',
        subjectId: 'math',
        startedAt: now.subtract(const Duration(hours: 2)),
        minutes: 25,
      );
      await store.setList(StoreKeys.sessions, [old.toJson()]);
      final recovered = FocusSession(
        id: 'stable-random',
        subjectId: 'math',
        startedAt: now.subtract(const Duration(minutes: 37)),
        minutes: 37,
      );
      final journalSnapshot = {
        'presetKey': 'custom:r',
        'phase': 'focus',
        'running': false,
        'remainingMs': 1200000,
        'sampledFocusMs': 1200000,
        'pendingCompletions': [recovered.toJson()],
      };
      originalTimer.hydrate(journalSnapshot);
      await Future<void>.delayed(Duration.zero);
      expect(
        original.read(sessionsProvider),
        isEmpty,
        reason: 'recovery waits for the existing persisted log to hydrate',
      );
      final pending = store.getMap(StoreKeys.presets)!;
      expect(pending['pendingCompletions'], hasLength(1));
      final next = container();
      addTearDown(next.dispose);
      next
          .read(planLibraryProvider.notifier)
          .hydrate(store.getMap(StoreKeys.planLibrary));
      final timer = next.read(timerProvider.notifier)..hydrate(pending);
      next
          .read(sessionsProvider.notifier)
          .hydrate(store.getList(StoreKeys.sessions));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(next.read(sessionsProvider).map((s) => s.id), [
        'older',
        'stable-random',
      ]);
      timer.hydrate(pending);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(next.read(sessionsProvider), hasLength(2));
    },
  );
}
