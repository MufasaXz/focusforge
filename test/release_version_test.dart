import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:focusforge/core/app_version.dart';

void main() {
  test('display and update versions match the packaged release version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final value = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec)![1];
    expect(value, '$kAppVersion+$kAppBuildNumber');
  });
}
