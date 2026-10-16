import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/study.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/features/onboarding/starting_plan_step.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
    await store.clearAll();
  });
  ProviderContainer fresh() {
    final container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> mount(
    WidgetTester tester,
    ProviderContainer container, {
    bool dark = false,
    double scale = 1,
    VoidCallback? onNext,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
          home: Scaffold(body: StartingPlanStep(onNext: onNext ?? () {})),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('deep work recommendation configures a real persisted timer', (
    tester,
  ) async {
    final container = fresh();
    container
        .read(userProvider.notifier)
        .hydrate(UserProfile.fromJson({'focusIntention': 'deepWork'}));
    var advanced = false;
    await mount(
      tester,
      container,
      onNext: () {
        expect(
          store.getMap(StoreKeys.presets)?['presetKey'],
          'stock:Deep Work',
        );
        advanced = true;
      },
    );
    expect(find.text('50 min focus'), findsOneWidget);
    await tester.tap(find.text('Use this plan'));
    await tester.pumpAndSettle();
    expect(advanced, isTrue);
    expect(
      container.read(timerProvider).remaining,
      const Duration(minutes: 50),
    );
    expect(container.read(timerProvider).running, isFalse);
  });

  testWidgets('incidental subject save does not override the suggested pace', (
    tester,
  ) async {
    final container = fresh();
    container
        .read(userProvider.notifier)
        .hydrate(UserProfile.fromJson({'focusIntention': 'deepWork'}));
    container.read(timerProvider.notifier).setSubject('math');
    await tester.pump();
    await mount(tester, container);
    await tester.tap(find.text('Use this plan'));
    await tester.pumpAndSettle();
    expect(container.read(timerProvider.notifier).preset.name, 'Deep Work');
    expect(container.read(timerProvider).subjectId, 'math');
  });

  testWidgets(
    'another account gets its recommendation instead of the previous draft plan',
    (tester) async {
      await store.setMap(StoreKeys.startingPlan, {
        'uid': 'alice',
        'key': 'stock:Classic',
      });
      final container = fresh();
      container
          .read(userProvider.notifier)
          .hydrate(
            UserProfile.fromJson({'uid': 'bob', 'focusIntention': 'deepWork'}),
          );
      await mount(tester, container);
      await tester.tap(find.text('Use this plan'));
      await tester.pumpAndSettle();
      expect(container.read(timerProvider.notifier).preset.name, 'Deep Work');
      expect(store.getMap(StoreKeys.startingPlan), {
        'uid': 'bob',
        'key': 'stock:Deep Work',
      });
    },
  );

  testWidgets(
    'onboarding creates a named plan and previews its actual duration',
    (tester) async {
      final container = fresh();
      await mount(tester, container);
      await tester.scrollUntilVisible(find.text('Create your own plan'), 180);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create your own plan'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Morning reading');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this plan').last);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(
        container
            .read(presetsProvider)
            .where((plan) => plan.name == 'Morning reading'),
        hasLength(1),
      );
      await tester.scrollUntilVisible(find.text('50 min focus'), -180);
      await tester.pumpAndSettle();
      expect(find.text('50 min focus'), findsOneWidget);
      await tester.tap(find.text('Use this plan'));
      await tester.pumpAndSettle();
      expect(
        container.read(timerProvider.notifier).preset.name,
        'Morning reading',
      );
    },
  );

  testWidgets('custom choice survives leaving and reopening the step', (
    tester,
  ) async {
    final container = fresh();
    await container
        .read(customPlanProvider.notifier)
        .set(
          const CustomPlan(
            id: 'reading',
            name: 'Evening reading',
            goalMinutes: 90,
            focusMinutes: 30,
          ),
        );
    container.read(timerProvider.notifier).setSubject('math');
    await mount(tester, container);
    await tester.scrollUntilVisible(find.text('Evening reading'), 180);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Evening reading'));
    await tester.tap(find.text('Use this plan'));
    await tester.pumpAndSettle();
    expect(
      container.read(timerProvider.notifier).preset.name,
      'Evening reading',
    );
    expect(container.read(timerProvider).subjectId, 'math');
    await tester.pumpWidget(const SizedBox());
    final reopened = fresh();
    reopened
        .read(planLibraryProvider.notifier)
        .hydrate(store.getMap(StoreKeys.planLibrary));
    reopened
        .read(timerProvider.notifier)
        .hydrate(store.getMap(StoreKeys.presets));
    await mount(tester, reopened);
    await tester.tap(find.text('Use this plan'));
    await tester.pumpAndSettle();
    expect(
      reopened.read(timerProvider.notifier).preset.name,
      'Evening reading',
    );
  });

  for (final dark in [false, true]) {
    testWidgets('available plan works at 320dp and large text, dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = fresh();
      final library = container.read(planLibraryProvider.notifier);
      for (final plan in container.read(presetsProvider).skip(1).toList()) {
        await library.remove(plan.key);
      }
      await mount(tester, container, dark: dark, scale: 2);
      await tester.scrollUntilVisible(find.text('Use this plan'), 180);
      await tester.pumpAndSettle();
      expect(find.text('Use this plan').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Use this plan'));
      await tester.pumpAndSettle();
      expect(
        container.read(timerProvider).remaining,
        const Duration(minutes: 25),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
