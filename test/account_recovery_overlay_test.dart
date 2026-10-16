import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focusforge/core/services/auth_service.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/shared/widgets/account_recovery_overlay.dart';

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
    expect(find.text('Restoring your account'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Continue'), warnIfMissed: false);
    expect(taps, 0);
    auth.recoveryState.value = AccountRecoveryStage.retrying;
    await tester.pump();
    expect(find.text('Reconnecting to your saved data…'), findsOneWidget);
    auth.recoveryState.value = null;
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('Continue'));
    expect(taps, 1);
    auth.dispose();
  });
}
