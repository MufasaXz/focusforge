import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:focusforge/core/app_version.dart';

void main() {
  test(
    'Play distribution keeps its version and excludes the GitHub updater',
    () {
      expect(kAppVersion, '1.0.1');
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains('version: 1.0.1+3001'),
      );
      for (final file in [
        'lib/core/services/app_update_service.dart',
        'lib/core/providers/app_update_providers.dart',
        'lib/shared/widgets/app_update_gate.dart',
      ]) {
        expect(File(file).existsSync(), isFalse, reason: file);
      }
      expect(
        File('lib/app/shell/app_shell.dart').readAsStringSync(),
        isNot(contains('AppUpdateGate')),
      );
      expect(
        File('lib/features/settings/about_screen.dart').readAsStringSync(),
        isNot(contains('CheckForUpdatesTile')),
      );
      expect(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        isNot(contains('REQUEST_INSTALL_PACKAGES')),
      );
    },
  );
}
