import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/services/auth_service.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/features/settings/account_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'account gate requires a provider credential before claiming a linked account',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      await store.clearAll();
      final auth = LocalAuthService(store);
      addTearDown(auth.dispose);
      const local = UserProfile(
        uid: 'local-child',
        displayName: 'Ari',
        onboardingComplete: true,
      );
      await auth.updateProfile(local);
      final container = ProviderContainer(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          authServiceProvider.overrideWithValue(auth),
        ],
      );
      addTearDown(container.dispose);
      container.read(userProvider.notifier).hydrate(local);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: AccountGate(
                title: 'Sign in for study groups',
                subtitle: 'Your detailed history stays on this device.',
                unlocked: 'Groups are ready.',
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Sign in or link an account'));
      await tester.pumpAndSettle();
      expect(find.text('Continue with Email'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(container.read(userProvider).isAnonymous, isTrue);
      expect(
        UserProfile.fromJson(store.getMap(StoreKeys.user)!).isAnonymous,
        isTrue,
      );
      expect(find.textContaining('Account linked.'), findsNothing);
      Navigator.of(tester.element(find.text('Continue with Email'))).pop();
      await tester.pumpAndSettle();
      expect(container.read(userProvider).uid, 'local-child');
      expect(container.read(userProvider).isAnonymous, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
