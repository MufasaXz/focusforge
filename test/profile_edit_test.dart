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

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/features/profile/profile_screen.dart';

/// A profile store that waits for [gate], then fails while [fail] is set.
class _SlowFailingUser extends UserNotifier {
  _SlowFailingUser(this.gate);
  Completer<void> gate;
  bool fail = true;
  int saves = 0;

  @override
  Future<void> setDisplayName(String name) async {
    saves++;
    await gate.future;
    if (fail) throw StateError('disk full');
    state = state.copyWith(displayName: name.trim());
  }
}

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

  testWidgets('a name save shows progress, survives a failure, then closes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await store.clearAll();
    final engine = RecordingShieldService();
    final user = _SlowFailingUser(Completer<void>());
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        shieldServiceProvider.overrideWithValue(engine),
        userProvider.overrideWith(() => user),
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
    await tester.tap(find.bySemanticsLabel('Edit profile').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Sam R');
    await tester.pump();

    await tester.tap(find.text('Save changes'));
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    expect(user.saves, 1, reason: 'a second tap waits for the first save');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    user.gate.complete();
    await tester.pumpAndSettle();
    expect(
      find.text('Could not save your profile. Try again.'),
      findsOneWidget,
    );
    expect(find.text('Sam R'), findsOneWidget, reason: 'the typed name stays');
    expect(find.text('Save changes'), findsOneWidget, reason: 'still open');

    user
      ..fail = false
      ..gate = (Completer<void>()..complete());
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('Save changes'), findsNothing);
    expect(container.read(userProvider).displayName, 'Sam R');
  });
}
