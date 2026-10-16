import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/features/onboarding/complete_step.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final width in [360.0, 520.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'setup summary and action stay reachable at width=$width text=$scale',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          final store = await LocalStore.open();
          final container = ProviderContainer(
            overrides: [localStoreProvider.overrideWithValue(store)],
          );
          addTearDown(container.dispose);
          container
              .read(userProvider.notifier)
              .hydrate(const UserProfile(persona: Persona.professional));
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: AppTheme.light(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    disableAnimations: true,
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: child!,
                ),
                home: const Scaffold(body: CompleteStep()),
              ),
            ),
          );
          await tester.pumpAndSettle();
          for (final label in [
            'Profile',
            'Subjects',
          'Classic Pomodoro',
            'Open FocusForge',
          ]) {
            await tester.scrollUntilVisible(find.text(label), 120);
            await tester.pumpAndSettle();
            expect(find.text(label).hitTestable(), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
