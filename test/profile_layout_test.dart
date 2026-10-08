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

  for (final dark in [false, true]) {
    testWidgets(
      'profile choices fit a narrow phone with large text, dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
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
            .hydrate(
              const UserProfile(displayName: 'Alexandria Morgan Rivera'),
            );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: dark ? AppTheme.dark(amoled: true) : AppTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: const Scaffold(body: ProfileScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Alexandria Morgan Rivera'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Tide'),
          220,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tide'));
        await tester.pumpAndSettle();
        expect(container.read(themeSettingsProvider).palette, AppPalette.tide);
        await tester.scrollUntilVisible(
          find.text('About FocusForge'),
          220,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('About FocusForge').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
