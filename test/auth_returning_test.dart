import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/services/auth_service.dart';
import 'package:focusforge/core/services/local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore store;
  late LocalAuthService auth;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
  });

  setUp(() async {
    await store.clearAll();
    auth = LocalAuthService(store);
    addTearDown(auth.dispose);
  });

  test(
    'a returning sign-in recognises a completed profile after sign-out',
    () async {
      const profile = UserProfile(
        uid: 'known-user',
        displayName: 'Sam Rivera',
        onboardingComplete: true,
        isAnonymous: false,
        dailyGoalMinutes: 45,
      );
      await auth.updateProfile(profile);
      await auth.signOut();
      final signedIn = await auth.signInWithEmail(
        'sam@example.com',
        'password',
      );
      expect(auth.isReturningUser, isTrue);
      expect(signedIn.uid, profile.uid);
      expect(signedIn.displayName, profile.displayName);
      expect(signedIn.onboardingComplete, isTrue);
      expect(signedIn.dailyGoalMinutes, 45);
      expect(auth.welcomeMessage(signedIn), 'Welcome back, Sam.');
    },
  );

  test(
    'a first sign-in receives a welcome without claiming a return',
    () async {
      final signedIn = await auth.signInWithEmail(
        'sam@example.com',
        'password',
      );
      expect(auth.isReturningUser, isFalse);
      expect(auth.welcomeMessage(signedIn), 'Welcome, Sam.');
    },
  );

  test(
    'an anonymous profile linking an account receives a first welcome',
    () async {
      await auth.updateProfile(
        const UserProfile(
          uid: 'guest-user',
          displayName: 'Morgan',
          onboardingComplete: true,
        ),
      );
      final signedIn = await auth.linkAccount(provider: 'google');
      expect(auth.isReturningUser, isFalse);
      expect(auth.welcomeMessage(signedIn), 'Welcome, Morgan.');
    },
  );

  test('deletion clears the account, history and return recognition', () async {
    await auth.updateProfile(
      const UserProfile(
        uid: 'known-user',
        onboardingComplete: true,
        isAnonymous: false,
      ),
    );
    await auth.signInWithEmail('sam@example.com', 'password');
    await store.setList(StoreKeys.sessions, [
      {'id': 'old-session'},
    ]);
    await auth.deleteAccount();
    expect(auth.current, isNull);
    expect(auth.isReturningUser, isFalse);
    expect(store.exportAll(), isEmpty);
    final fresh = await auth.signInWithEmail('sam@example.com', 'password');
    expect(fresh.onboardingComplete, isFalse);
    expect(auth.isReturningUser, isFalse);
  });
}
