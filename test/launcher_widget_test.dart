import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/core/providers/app_providers.dart';
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
      ]) {
        await store.setString(key, 'snapshot');
        expect(store.getString(key), 'snapshot');
      }
      await store.setInt(StoreKeys.dailyGoal, 180);
      expect(store.getInt(StoreKeys.dailyGoal), 180);
      expect(calls, List.filled(7, 'refresh'));
      await store.setInt('unrelated', 42);
      expect(calls.length, 7);
      await store.clearAll();
      expect(calls.last, 'refresh');
      expect(store.getString(StoreKeys.sessions), isNull);
    },
  );

  test(
    'a seeded subject name is available to widgets before a catalogue is saved',
    () async {
      final store = await LocalStore.open();
      await store.clearAll();
      final container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      container.read(timerProvider.notifier).setSubject('math');
      await Future<void>.delayed(Duration.zero);
      expect(store.getMap(StoreKeys.presets)?['subjectName'], 'Math');
      expect(store.getString(StoreKeys.subjects), isNull);
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

  test('an embedding without widgets cannot break the focus app', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await WidgetService.refresh();
    expect(await WidgetService.takeFocusLaunch(), isFalse);
    expect(await WidgetService.takeDashboardLaunch(), isFalse);
  });
}
