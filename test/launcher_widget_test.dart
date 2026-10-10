import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
          return call.method == 'takeFocusLaunch' ? true : null;
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
      ]) {
        await store.setString(key, 'snapshot');
        expect(store.getString(key), 'snapshot');
      }
      expect(calls, ['refresh', 'refresh', 'refresh']);
      await store.clearAll();
      expect(calls.last, 'refresh');
      expect(store.getString(StoreKeys.sessions), isNull);
    },
  );

  test('widget taps are read from the Android launch intent', () async {
    expect(await WidgetService.takeFocusLaunch(), isTrue);
    expect(calls, ['takeFocusLaunch']);
  });

  test('an embedding without widgets cannot break the focus app', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await WidgetService.refresh();
    expect(await WidgetService.takeFocusLaunch(), isFalse);
  });
}
