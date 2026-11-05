// Talking to Pip.
//
// WHAT INVARIANT: the chat introduces Pip and asks for the user's exam once;
// a chip carries its request in any language; a typed "lock instagram" finds
// the app and, on one tap, puts it in Shield's focus tier; a plan saved as
// today's goal counts what is already done; "start a block" starts the timer
// on the plan's first subject.
//
// WHY IT MATTERS: these are the moments the assistant does real work. A lock
// that only says "locked", or a plan that drops the morning's study from the
// goal, would make every other answer untrustworthy.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/localization/app_strings.dart';
import 'package:focusforge/core/models/shield.dart';
import 'package:focusforge/core/models/study.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/goal_planner_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/providers/usage_providers.dart';
import 'package:focusforge/core/services/app_catalog.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/features/assistant/assistant_memory.dart';
import 'package:focusforge/features/assistant/brain/assistant_models.dart';
import 'package:focusforge/features/assistant/brain/study_snapshot.dart';
import 'package:focusforge/features/assistant/chat/chat_controller.dart';
import 'package:focusforge/features/assistant/chat/chat_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStore store;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
  });

  setUp(() async => store.clearAll());

  Future<ProviderContainer> pumpChat(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final engine = RecordingShieldService();
    addTearDown(engine.dispose);
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        shieldServiceProvider.overrideWithValue(engine),
        appBlockingSupportedProvider.overrideWithValue(true),
        appListConsentProvider.overrideWith(() => AppListConsentNotifier(true)),
        usageAccessProvider.overrideWith((ref) async => true),
        installedAppsProvider.overrideWith(
          (ref) async => const [
            InstalledApp(
              packageId: 'com.instagram.android',
              name: 'Instagram',
              isSystem: false,
            ),
            InstalledApp(
              packageId: 'org.wikipedia',
              name: 'Wikipedia',
              isSystem: false,
            ),
          ],
        ),
        appUsageTodayProvider.overrideWith(
          (ref) async => const {'com.instagram.android': 48},
        ),
        launchablePackagesProvider.overrideWith((ref) async => const {}),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(userProvider.notifier)
        .hydrate(const UserProfile(displayName: 'Sam Rivera'));
    container.read(subjectsProvider.notifier).hydrate([
      Subject(
        id: 'physics',
        name: 'Physics',
        icon: Icons.science_rounded,
        color: Colors.purple,
      ).toJson()..['icon'] = 'science',
      Subject(
        id: 'biology',
        name: 'Biology',
        icon: Icons.science_rounded,
        color: Colors.teal,
      ).toJson()..['icon'] = 'science',
    ]);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: AppStrings.localizationsDelegates,
          home: const AssistantChatScreen(),
        ),
      ),
    );
    return container;
  }

  /// Lets Pip finish thinking and typing.
  Future<void> wait(WidgetTester tester, [int seconds = 8]) async {
    for (var i = 0; i < seconds * 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('Pip introduces itself once and remembers the exam', (
    tester,
  ) async {
    final container = await pumpChat(tester);
    await wait(tester);

    expect(find.text('Hi, I’m Pip, your study buddy.'), findsOneWidget);
    expect(find.text('Which exam are you preparing for?'), findsOneWidget);
    expect(container.read(assistantMemoryProvider).introduced, isTrue);

    await tester.ensureVisible(find.widgetWithText(ActionChip, 'NEET-UG'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ActionChip, 'NEET-UG'));
    await wait(tester);

    expect(container.read(assistantMemoryProvider).examId, 'neet-ug');
    expect(find.text('Saved. I’ll plan around NEET-UG.'), findsOneWidget);
    expect(
      find.textContaining('Biology is half the paper', findRichText: true),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a typed lock finds the app and puts it in the focus tier', (
    tester,
  ) async {
    // The phone has granted Shield what it needs; the engine starts.
    const channel = MethodChannel('dev.focusforge/shield');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => true);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final container = await pumpChat(tester);
    await wait(tester);

    await tester.enterText(find.byType(TextField), 'lock insta please');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await wait(tester);

    expect(find.text('Pick apps to lock'), findsOneWidget);
    expect(find.text('48m today'), findsOneWidget);

    await tester.ensureVisible(find.text('Lock while focusing'));
    await tester.tap(find.text('Lock while focusing'));
    await wait(tester);

    final entry = container
        .read(whitelistProvider)
        .singleWhere((e) => e.packageId == 'com.instagram.android');
    expect(entry.tier, WhitelistTier.focusOnly);
    expect(
      find.text('Locked. Instagram will close during focus blocks.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'a saved plan keeps the morning in the goal; a start runs the timer',
    (tester) async {
      final container = await pumpChat(tester);
      await wait(tester);
      final now = DateTime.now();
      container.read(sessionsProvider.notifier).hydrate([
        FocusSession(
          id: 'morning',
          subjectId: 'biology',
          startedAt: DateTime(now.year, now.month, now.day, 0, 30),
          minutes: 40,
        ).toJson(),
      ]);
      final chat = container.read(chatProvider.notifier);

      unawaited(chat.run(const AssistantAction(Act.plan)));
      await wait(tester);
      final entry = container
          .read(chatProvider)
          .entries
          .lastWhere((e) => e.card is PlanCard);
      final plan = entry.card! as PlanCard;

      unawaited(chat.savePlan(entry.id, plan));
      await wait(tester, 3);
      final goal = container.read(activeFocusGoalProvider)!;
      expect(goal.totalMinutes, plan.totalMinutes + 40);
      expect(
        goal.subjectMinutes.values.fold<int>(0, (sum, m) => sum + m),
        goal.totalMinutes,
      );
      expect(container.read(chatProvider).savedPlans, contains(entry.id));

      unawaited(chat.startBlock(plan.blocks.first.subjectId));
      await wait(tester, 3);
      final timer = container.read(timerProvider);
      expect(timer.running, isTrue);
      expect(timer.subjectId, plan.blocks.first.subjectId);
      container.read(timerProvider.notifier).reset();
    },
  );
}
