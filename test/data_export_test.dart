// "Export all data" (lib/features/settings/privacy_screen.dart and
// lib/core/services/data_export.dart): the export can be saved as a dated
// file through the system picker, a cancelled picker changes nothing, and a
// failed write says so and can be tried again.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/services/auth_service.dart';
import 'package:focusforge/core/services/data_export.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/features/settings/privacy_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.focusforge/export');

  test('the file name carries the date', () {
    expect(
      DataExport.fileName(DateTime(2026, 3, 7, 23, 59)),
      'focusforge-export-2026-03-07.json',
    );
  });

  testWidgets('saving: cancel, a failed write, then a saved file', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await store.setString(StoreKeys.clockFace, 'flip');
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        authServiceProvider.overrideWithValue(LocalAuthService(store)),
      ],
    );
    addTearDown(container.dispose);

    final calls = <Map<Object?, Object?>>[];
    final replies = ['cancelled', 'error', 'saved'];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.arguments as Map<Object?, Object?>);
      final reply = replies.removeAt(0);
      if (reply == 'error') {
        throw PlatformException(code: 'write_failed');
      }
      return reply;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const PrivacyScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export all data (JSON)'));
    await tester.pumpAndSettle();

    final name = DataExport.fileName(DateTime.now());
    expect(find.text('Saves as $name'), findsOneWidget);
    expect(
      find.textContaining('every account saved on this device'),
      findsOneWidget,
    );

    await tester.tap(find.text('Save file'));
    await tester.pumpAndSettle();
    expect(find.text('Save file'), findsOneWidget, reason: 'cancel stays');
    expect(find.text('Saves as $name'), findsOneWidget);

    await tester.tap(find.text('Save file'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save the file. Try again.'), findsOneWidget);

    await tester.tap(find.text('Save file'));
    await tester.pumpAndSettle();
    expect(find.text('Save file'), findsNothing, reason: 'the dialog closes');
    expect(find.text('Saved $name.'), findsOneWidget);

    expect(calls, hasLength(3));
    expect(calls.last['name'], name);
    final saved = jsonDecode(calls.last['json']! as String) as Map;
    expect(saved[StoreKeys.clockFace], 'flip');
    expect(tester.takeException(), isNull);
  });
}
