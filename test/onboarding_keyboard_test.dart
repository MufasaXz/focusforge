import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/features/onboarding/profile_step.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final scale in [1.0, 1.8]) {
    testWidgets(
      'profile name keeps keyboard focus when IME opens, scale=$scale',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final store = await LocalStore.open();
        tester.view.physicalSize = const Size(390, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [localStoreProvider.overrideWithValue(store)],
            child: MaterialApp(
              theme: AppTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: TextScaler.linear(scale),
                ),
                child: child!,
              ),
              home: Scaffold(body: ProfileStep(onNext: () {})),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(TextField));
        await tester.tap(find.byType(TextField));
        await tester.pump();
        final field = tester.widget<EditableText>(find.byType(EditableText));
        final focus = field.focusNode;
        expect(focus.hasFocus, isTrue);
        expect(tester.testTextInput.isVisible, isTrue);

        // Android resizeToAvoidBottomInset makes the layout cross both the
        // normal and large-text compact thresholds as the IME is shown.
        tester.view.viewInsets = const FakeViewPadding(bottom: 440);
        await tester.pumpAndSettle();

        expect(
          tester.widget<EditableText>(find.byType(EditableText)).focusNode,
          same(focus),
          reason: 'the IME resize must not replace the focused input',
        );
        expect(focus.hasFocus, isTrue);
        expect(tester.testTextInput.isVisible, isTrue);
        await tester.enterText(find.byType(TextField), 'Alex');
        await tester.pump();
        expect(find.text('Alex'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
