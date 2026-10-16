import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/models/study.dart';
import 'package:flutter/material.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/widget_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('focusforge/widgets');
  final calls = <String>[];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    WidgetService.enabled = true;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return call.method == 'takeFocusLaunch' ||
                  call.method == 'takeDashboardLaunch'
              ? true
              : null;
        });
  });

  tearDown(() {
    WidgetService.enabled = false;
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'timer, history and theme writes refresh the launcher after saving',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      for (final key in [
        StoreKeys.presets,
        StoreKeys.sessions,
        StoreKeys.theme,
        StoreKeys.palette,
        StoreKeys.subjects,
        StoreKeys.dailyGoalDays,
        StoreKeys.user,
        StoreKeys.achievementHistoryOwner,
        StoreKeys.achievementAliases,
      ]) {
        await store.setString(key, 'snapshot');
        expect(store.getString(key), 'snapshot');
      }
      await store.setInt(StoreKeys.dailyGoal, 180);
      expect(store.getInt(StoreKeys.dailyGoal), 180);
      expect(calls, List.filled(10, 'refresh'));
      await store.setBool(StoreKeys.amoled, true);
      expect(store.getBool(StoreKeys.amoled), isTrue);
      expect(calls.length, 11);
      await store.setInt('unrelated', 42);
      await store.setBool('unrelatedFlag', true);
      expect(calls.length, 11);
      await store.clearAll();
      expect(calls.last, 'refresh');
      expect(store.getString(StoreKeys.sessions), isNull);
    },
  );

  test(
    'widgets use a chosen subject name and never invent an unchosen template',
    () async {
      final store = await LocalStore.open();
      await store.clearAll();
      final container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      expect(container.read(subjectsProvider), isEmpty);
      await container
          .read(subjectsProvider.notifier)
          .add(
            const Subject(
              id: 'math',
              name: 'Math',
              icon: Icons.book,
              color: Colors.blue,
            ),
          );
      container.read(timerProvider.notifier).setSubject('math');
      await Future<void>.delayed(Duration.zero);
      expect(store.getMap(StoreKeys.presets)?['subjectName'], 'Math');
      expect(store.getList(StoreKeys.subjects).single['name'], 'Math');
      container.read(timerProvider.notifier).setSubject(null);
      await Future<void>.delayed(Duration.zero);
      expect(store.getMap(StoreKeys.presets)?['subjectName'], isNull);
    },
  );

  test('widget taps are read from the Android launch intent', () async {
    expect(await WidgetService.takeFocusLaunch(), isTrue);
    expect(await WidgetService.takeDashboardLaunch(), isTrue);
    expect(calls, ['takeFocusLaunch', 'takeDashboardLaunch']);
  });

  test(
    'native live progress uses the current segment length after nudging',
    () async {
      final store = await LocalStore.open();
      await store.clearAll();
      final container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final timer = container.read(timerProvider.notifier);
      timer.nudge(const Duration(minutes: 5));
      timer.start();
      await Future<void>.delayed(Duration.zero);
      final active = store.getMap(StoreKeys.presets)!;
      expect(active['plannedMs'], const Duration(minutes: 30).inMilliseconds);
      expect(active['running'], isTrue);
      expect(active['targetEnd'], isNotNull);
      timer.pause();
      await Future<void>.delayed(Duration.zero);
      final paused = store.getMap(StoreKeys.presets)!;
      expect(paused['running'], isFalse);
      expect(paused['targetEnd'], isNull);
      expect(paused['plannedMs'], active['plannedMs']);
    },
  );

  test('an embedding without widgets cannot break the focus app', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await WidgetService.refresh();
    expect(await WidgetService.takeFocusLaunch(), isFalse);
    expect(await WidgetService.takeDashboardLaunch(), isFalse);
  });
}
