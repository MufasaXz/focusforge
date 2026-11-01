import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usage_stats/usage_stats.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('usage_stats');
  final log = <MethodCall>[];

  // Per-test responses, keyed by method name.
  late Map<String, dynamic Function(MethodCall call)> responders;

  setUp(() {
    log.clear();
    responders = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      return responders[call.method]?.call(call);
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Map<dynamic, dynamic> argsOf(String method) =>
      log.firstWhere((c) => c.method == method).arguments as Map;

  final start = DateTime(2024, 6, 10);
  final end = DateTime(2024, 6, 11);

  group('permission', () {
    test('checkUsagePermission returns the platform value', () async {
      responders['isUsagePermission'] = (_) => true;
      expect(await UsageStats.checkUsagePermission(), isTrue);
      expect(log.single.method, 'isUsagePermission');
    });

    test('openUsageAccessSettings invokes the channel', () async {
      await UsageStats.openUsageAccessSettings();
      expect(log.single.method, 'openUsageAccessSettings');
    });
  });

  group('queryEvents', () {
    test('parses events including the new typed fields', () async {
      responders['queryEvents'] = (_) => [
            {
              'eventType': '1',
              'timeStamp': '1700000000000',
              'packageName': 'com.a',
              'className': null,
              'appStandbyBucket': '10',
              'shortcutId': null,
            },
          ];
      final events = await UsageStats.queryEvents(start, end);
      final event = events.single;
      expect(event.packageName, 'com.a');
      expect(event.eventTypeValue, 1);
      expect(event.eventTypeDescription, 'ACTIVITY_RESUMED');
      expect(event.appStandbyBucketValue, 10);
      expect(
        event.timeStampDate,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
    });
  });


  group('package info', () {
    test('queryInstalledApps forwards includeSystem and reads three fields',
        () async {
      responders['queryInstalledApps'] = (_) => [
            {
              'packageName': 'com.a',
              'appName': 'App A',
              'isSystemApp': 'false',
            },
          ];
      final apps = await UsageStats.queryInstalledApps(includeSystem: false);
      expect(argsOf('queryInstalledApps')['includeSystem'], isFalse);
      expect(apps.single.packageName, 'com.a');
      expect(apps.single.appName, 'App A');
      expect(apps.single.isSystemApp, isFalse);
    });

    test('getAppIcon returns the raw bytes', () async {
      responders['getAppIcon'] = (_) => Uint8List.fromList([1, 2, 3]);
      final icon = await UsageStats.getAppIcon('com.a');
      expect(icon, Uint8List.fromList([1, 2, 3]));
    });
  });
}
