import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/app/router.dart';
import 'package:focusforge/features/onboarding/persona_step.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'a former guardian keeps identity and setup as a normal study account',
    () {
      final profile = UserProfile.fromJson({
        'uid': 'returning-user',
        'displayName': 'Alex',
        'persona': 'parent',
        'isGuardian': true,
        'onboardingComplete': true,
        'isAnonymous': false,
        'dailyGoalMinutes': 240,
      });
      expect(profile.persona, Persona.student);
      expect(profile.uid, 'returning-user');
      expect(profile.displayName, 'Alex');
      expect(profile.onboardingComplete, isTrue);
      expect(profile.dailyGoalMinutes, 240);
      expect(profile.toJson().containsKey('isGuardian'), isFalse);
    },
  );
  test('cold-start Shield ignores cached remote blocks and keeps local YouTube choices', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await store.clearAll();
    await store.setMap('shield.parentCache', {
      'uid': 'returning-user',
      'blocks': {
        'apps': [
          {'packageId': 'com.instagram.android', 'name': 'Instagram'},
        ],
        'enforced': true,
        'youtube': {'shorts': true, 'feed': true, 'focusOnly': false},
      },
    });
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
        .hydrate(const UserProfile(uid: 'returning-user'));
    container.read(youtubeRulesProvider.notifier).hydrate({
      'shorts': false,
      'feed': true,
      'focusOnly': true,
    });
    syncShield(container.read(shieldSyncRefProvider));
    expect(engine.lastApplied!.toChannelPayload()['apps'], isEmpty);
    expect(engine.lastApplied!.youtube.shorts, isFalse);
    expect(engine.lastApplied!.youtube.feed, isTrue);
    expect(engine.lastApplied!.youtube.focusOnly, isTrue);
  });
  testWidgets(
    'onboarding offers personal study roles without parent monitoring',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [localStoreProvider.overrideWithValue(store)],
          child: MaterialApp(home: Scaffold(body: PersonaStep(onNext: () {}))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Parent'), findsNothing);
      expect(find.text('Student'), findsOneWidget);
      expect(find.text('Professional'), findsOneWidget);
    },
  );
  testWidgets('old parent deep links redirect to the ordinary profile', (
    tester,
  ) async {
    final store = await LocalStore.open();
    final container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    container
        .read(userProvider.notifier)
        .hydrate(const UserProfile(onboardingComplete: true));
    final router = container.read(routerProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.go('/profile/parent-control/old-child');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/profile');
  });
}

// A real provider Ref exercises the same config push used by app notifiers.
final shieldSyncRefProvider = Provider<Ref>((ref) => ref);
