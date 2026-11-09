// Quiet hours on the Notifications screen (lib/features/settings/
// notifications_screen.dart): the window reads back to the minute it was
// set, and an empty window says that it mutes nothing.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/social.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/social_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/features/settings/notifications_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore store;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
  });
  setUp(() async => store.clearAll());

  Future<ProviderContainer> show(
    WidgetTester tester,
    NotificationPrefs prefs,
  ) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scope = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    addTearDown(scope.dispose);
    scope.read(notificationsProvider.notifier).hydrate(prefs.toJson());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: NotificationsScreen()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    return scope;
  }

  testWidgets('the window shows the minutes it was set to', (tester) async {
    await show(
      tester,
      const NotificationPrefs(quietStart: 22 * 60 + 45, quietEnd: 7 * 60 + 30),
    );
    expect(find.text('Muted 22:45 – 07:30'), findsOneWidget);
    await tester.tap(find.text('Muted 22:45 – 07:30'));
    await tester.pumpAndSettle();
    expect(find.text('22:45'), findsOneWidget);
    expect(find.text('07:30'), findsOneWidget);
    expect(
      find.text(
        'Reminders due in this window wait until 07:30. Calls for timetable blocks inside it are skipped.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty window says it mutes nothing', (tester) async {
    await show(
      tester,
      const NotificationPrefs(quietStart: 21 * 60, quietEnd: 21 * 60),
    );
    expect(
      find.text('Start and end are the same, so nothing is muted.'),
      findsOneWidget,
    );
    expect(find.textContaining('Muted'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
