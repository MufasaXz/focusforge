import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/features/onboarding/onboarding_flow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
    await store.clearAll();
  });

  Future<void> mount(WidgetTester tester, String uid) async {
    final container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    container.read(userProvider.notifier).hydrate(UserProfile(uid: uid));
    await store.setMap(StoreKeys.user, container.read(userProvider).toJson());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const OnboardingFlow(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();
  }

  testWidgets('unfinished setup resumes the same user at the saved step', (
    tester,
  ) async {
    await store.setMap('setup.progress', {'uid': 'alice', 'step': 7});
    await mount(tester, 'alice');
    expect(find.text('Starting plan'), findsOneWidget);
    expect(find.text('Find your starting pace'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Daily goal'), findsOneWidget);
    expect(store.getMap('setup.progress'), {'uid': 'alice', 'step': 6});
    expect(tester.takeException(), isNull);
  });

  testWidgets('another account does not inherit the saved setup step', (
    tester,
  ) async {
    await store.setMap('setup.progress', {'uid': 'alice', 'step': 7});
    await mount(tester, 'bob');
    expect(find.text('Your focus'), findsOneWidget);
    expect(find.text('Starting plan'), findsNothing);
    expect(store.getMap('setup.progress'), {'uid': 'bob', 'step': 2});
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid saved progress safely starts from the first choice', (
    tester,
  ) async {
    await store.setMap('setup.progress', {'uid': 'alice', 'step': 999});
    await mount(tester, 'alice');
    expect(find.text('Your focus'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
