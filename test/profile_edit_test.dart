// One way to edit the profile.
//
// WHAT INVARIANT: the profile's avatar carries no pencil of its own; the Edit
// button and the avatar both open one sheet, and that sheet changes the
// avatar and the display name.
//
// WHY IT MATTERS: two pencils for two halves of one profile asked the user to
// learn which pencil changed what.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/features/profile/profile_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('one Edit opens the avatar and the name together', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await store.clearAll();
    final engine = RecordingShieldService();
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        shieldServiceProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(engine.dispose);
    container
        .read(userProvider.notifier)
        .hydrate(const UserProfile(displayName: 'Sam Rivera'));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ProfileScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A single pencil on the page: the Edit button's.
    expect(find.byIcon(Icons.edit_rounded), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Edit profile').first);
    await tester.pumpAndSettle();

    expect(find.text('Change your avatar'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.text('Change your avatar'));
    await tester.pumpAndSettle();
    expect(find.text('Your avatar'), findsOneWidget);
  });
}
