import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focusforge/core/services/auth_service.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/shared/widgets/account_recovery_overlay.dart';
import 'package:focusforge/shared/widgets/expressive_loading_indicator.dart';

void main() {
  testWidgets('recovery blocks actions only while real restoration is active', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final auth = LocalAuthService(await LocalStore.open());
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountRecoveryOverlay(
            service: auth,
            child: Center(
              child: TextButton(
                onPressed: () => taps++,
                child: const Text('Continue'),
              ),
            ),
          ),
        ),
      ),
    );
    auth.recoveryState.value = AccountRecoveryStage.restoring;
    await tester.pump();
    expect(find.text('Recovering your account'), findsOneWidget);
    expect(find.byType(ExpressiveLoadingIndicator), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 450));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Continue'), warnIfMissed: false);
    expect(taps, 0);
    auth.recoveryState.value = AccountRecoveryStage.retrying;
    await tester.pump();
    expect(find.text('Reconnecting to your saved data…'), findsOneWidget);
    auth.recoveryState.value = null;
    await tester.pump();
    expect(find.byType(ExpressiveLoadingIndicator), findsNothing);
    await tester.tap(find.text('Continue'));
    expect(taps, 1);
    auth.dispose();
  });
}
