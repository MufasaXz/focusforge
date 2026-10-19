import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusforge/core/services/native_shield_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.focusforge/shield');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'external launch cannot request years of temporary Shield access',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => {
          'package': 'com.google.android.youtube',
          'label': 'YouTube',
          'graceSeconds': 2147483647,
        },
      );
      final service = NativeShieldService();
      addTearDown(service.dispose);
      final launch = await service.takeBlockedApp();
      expect(launch?.graceSeconds, 600);
    },
  );

  test('temporary access sent to either native engine is bounded', () async {
    final grants = <int>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'grantTemporaryAccess') {
        grants.add((call.arguments as Map)['seconds'] as int);
      }
      return true;
    });
    final service = NativeShieldService();
    addTearDown(service.dispose);
    for (final seconds in [-1, 1, 120, 2147483647]) {
      await service.grantTemporaryAccess(
        'com.google.android.youtube',
        seconds: seconds,
      );
    }
    expect(grants, [5, 5, 120, 600]);
  });
}
