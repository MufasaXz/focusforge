import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/app/router.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/services/auth_service.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/shared/widgets/email_auth_sheet.dart';

class _PendingAuth extends LocalAuthService {
  _PendingAuth(super.store);
  bool pending = false;
  bool linkUsed = false;
  @override
  bool get usesRemoteCredentials => true;
  @override
  bool get needsEmailVerification => pending;
  @override
  String? get verificationEmail => pending ? 'person@example.com' : null;
  @override
  Future<UserProfile> signInWithEmail(String email, String password) async {
    pending = true;
    throw const AuthException(AuthFailure.emailVerificationRequired);
  }

  @override
  Future<void> sendEmailVerification() async {}
  @override
  Future<UserProfile?> refreshEmailVerification() async {
    if (!linkUsed) return null;
    pending = false;
    return const UserProfile(uid: 'verified', isAnonymous: false);
  }
}

void main() {
  testWidgets(
    'unverified sign-in shows verification actions instead of success',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final auth = _PendingAuth(await LocalStore.open());
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: EmailAuthSheet(service: auth)),
        ),
      );
      await tester.enterText(
        find.byType(TextField).first,
        'person@example.com',
      );
      await tester.enterText(find.byType(TextField).last, 'password');
      await tester.pump();
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Verify your email'), findsOneWidget);
      expect(find.text('person@example.com'), findsOneWidget);
      expect(find.text('I’ve verified my email'), findsOneWidget);
      expect(find.text('Send verification email'), findsOneWidget);
      expect(find.text('Use a different account'), findsOneWidget);
      await tester.tap(find.text('I’ve verified my email'));
      await tester.pumpAndSettle();
      expect(find.text('Verify your email'), findsOneWidget);
      expect(auth.pending, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('all routes redirect pending email credentials to verification', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    final auth = _PendingAuth(store)..pending = true;
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        authServiceProvider.overrideWithValue(auth),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(auth.dispose);
    final router = container.read(routerProvider);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.go('/dashboard');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/verify-email');
    router.go('/profile/groups');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/verify-email');
  });
  test(
    'guest fallback refuses fabricated email accounts and reset claims',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      final auth = GuestOnlyAuthService(store);
      addTearDown(auth.dispose);
      expect(auth.supportedProviders, {'local'});
      await expectLater(
        auth.signUpWithEmail('nobody@example.com', 'password'),
        throwsA(isA<AuthException>()),
      );
      await expectLater(
        auth.signInWithEmail('nobody@example.com', 'password'),
        throwsA(isA<AuthException>()),
      );
      await expectLater(
        auth.sendPasswordReset('nobody@example.com'),
        throwsA(isA<AuthException>()),
      );
      expect(auth.current, isNull);
      expect((await auth.signInAnonymously()).isAnonymous, isTrue);
    },
  );
}
