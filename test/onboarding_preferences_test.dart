import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/services/auth_service.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/features/onboarding/persona_step.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
    await store.clearAll();
  });

  test('saved focus intention survives logout and restored setup', () async {
    final auth = LocalAuthService(store);
    addTearDown(auth.dispose);
    await auth.updateProfile(
      UserProfile.fromJson({
        'uid': 'returning',
        'displayName': 'Sam',
        'onboardingComplete': true,
        'isAnonymous': false,
        'focusIntention': 'deepWork',
      }),
    );
    await auth.signOut();
    final restarted = LocalAuthService(store);
    addTearDown(restarted.dispose);
    await restarted.restore();
    final profile = await restarted.signInWithEmail(
      'sam@example.com',
      'password',
    );
    expect(profile.toJson()['focusIntention'], 'deepWork');
    expect(profile.onboardingComplete, isTrue);
    expect(profile.displayName, 'Sam');
  });

  test('older or unreadable preferences keep completed setup', () {
    for (final value in [null, 'retired', 7, <String>[]]) {
      final profile = UserProfile.fromJson({
        'onboardingComplete': true,
        'focusIntention': value,
      });
      expect(profile.toJson()['focusIntention'], 'consistency');
      expect(profile.onboardingComplete, isTrue);
    }
  });

  testWidgets('choosing an intention saves it before continuing', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    var advanced = false;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Scaffold(body: PersonaStep(onNext: () => advanced = true)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Go deeper'), 180);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go deeper'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(advanced, isTrue);
    expect(store.getMap(StoreKeys.user)?['focusIntention'], 'deepWork');
    expect(container.read(userProvider).toJson()['focusIntention'], 'deepWork');
  });

  testWidgets('account restored while mounted keeps its focus preference', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Scaffold(body: PersonaStep(onNext: () {})),
        ),
      ),
    );
    await tester.pumpAndSettle();
    container
        .read(userProvider.notifier)
        .hydrate(
          UserProfile.fromJson({
            'uid': 'restored',
            'persona': 'professional',
            'focusIntention': 'deepWork',
          }),
        );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(container.read(userProvider).persona, Persona.professional);
    expect(store.getMap(StoreKeys.user)?['focusIntention'], 'deepWork');
  });
}
