// Talking to Pip.
//
// WHAT INVARIANT: the chat introduces Pip and asks for the user's exam once;
// a chip carries its request in any language; a typed "lock instagram" finds
// the app and, on one tap, puts it in Shield's focus tier; a plan saved as
// today's goal counts what is already done; "start a block" starts the timer
// on the plan's first subject. Every answer stays on the phone.
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
import 'package:focusforge/features/assistant/nudges/pip_nudges.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStore store;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
  });

  setUp(() async => store.clearAll());

  Future<ProviderContainer> pumpChat(WidgetTester tester, {String? uid}) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final engine = RecordingShieldService();
    addTearDown(engine.dispose);
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        pipNotificationAccessProvider.overrideWithValue(
          const _NoNotifications(),
        ),
        accountUidProvider.overrideWithValue(uid),
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
    await tester.pump();
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

  Future<void> ask(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await wait(tester);
  }

  testWidgets('compound app questions keep the explicit lock card flow', (
    tester,
  ) async {
    const channel = MethodChannel('dev.focusforge/shield');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => true);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final container = await pumpChat(tester);
    await wait(tester);
    final before = container.read(whitelistProvider);
    await ask(tester, 'what is strict mode and how do I block instagram');
    await wait(tester, 8);
    final entries = container.read(chatProvider).entries;
    final explanation = entries.indexWhere(
      (e) => e.fromPip && (e.copy?.key.startsWith('Strict') ?? false),
    );
    final selection = entries.indexWhere((e) => e.card is LockCard);
    expect(explanation, greaterThanOrEqualTo(0));
    expect(selection, greaterThan(explanation));
    expect(
      (entries[selection].card! as LockCard).preselected,
      contains('com.instagram.android'),
    );
    expect(container.read(whitelistProvider), before);
    await tester.scrollUntilVisible(
      find.text('Lock while focusing'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Lock while focusing'));
    await wait(tester);
    expect(
      container
          .read(whitelistProvider)
          .singleWhere((e) => e.packageId == 'com.instagram.android')
          .tier,
      WhitelistTier.focusOnly,
    );
  });

  testWidgets('clearing chat discards the pending local quiz', (tester) async {
    final container = await pumpChat(tester);
    await wait(tester);
    await ask(tester, 'quiz me on fractions');
    container.read(chatProvider.notifier).clear();
    await ask(tester, 'B');
    expect(find.textContaining('Not quite', findRichText: true), findsNothing);
    expect(
      find.textContaining('Practice check:', findRichText: true),
      findsNothing,
    );
  });

  testWidgets('a typed timetable is saved and becomes today’s focus plan', (
    tester,
  ) async {
    final container = await pumpChat(tester);
    await wait(tester);

    await ask(tester, 'make a timetable: physics 2 hours, 3 hours a day');
    expect(find.text('Your timetable'), findsOneWidget);

    // A tall card opens at its top, so Save is a scroll away.
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await wait(tester);
    final saved = container.read(assistantMemoryProvider).timetable!;
    expect(saved.subjectMinutes['physics'], 120);
    expect(saved.totalMinutes, 180);
    // Tests cannot grant notifications, so the reminder moves to Home.
    expect(
      container
          .read(chatProvider)
          .entries
          .any((e) => e.copy?.key.contains('remind you on Home') ?? false),
      isTrue,
    );

    await tester.ensureVisible(find.text('Use as today’s focus plan'));
    await tester.tap(find.text('Use as today’s focus plan'));
    await wait(tester);
    final plan = container
        .read(planLibraryProvider)
        .plans
        .singleWhere((p) => p.id == ChatController.timetablePlanId);
    expect(plan.goalMinutes, 180);
    expect(plan.focusMinutes, saved.blockMinutes);
    final today = container.read(focusGoalPlannerProvider).day!;
    expect(today.totalMinutes, 180);
    expect(container.read(timerProvider).subjectId, 'physics');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an exam reminder asks for the date first, then counts down', (
    tester,
  ) async {
    final container = await pumpChat(tester);
    await container.read(assistantMemoryProvider.notifier).setExam('neet-ug');
    await wait(tester);

    await ask(tester, 'remind me about my exam');
    expect(container.read(assistantMemoryProvider).examReminders, isFalse);
    expect(
      find.textContaining('Pick the date', findRichText: true),
      findsOneWidget,
    );

    final date = DateTime.now().add(const Duration(days: 40));
    unawaited(container.read(chatProvider.notifier).setExamDate(date));
    await wait(tester);
    expect(container.read(assistantMemoryProvider).examReminders, isTrue);
    expect(
      find.textContaining('a month, two weeks', findRichText: true),
      findsOneWidget,
    );

    await ask(tester, 'stop exam reminders');
    expect(container.read(assistantMemoryProvider).examReminders, isFalse);
  });
  testWidgets('a dated reminder typed in chat is set, listed and removed', (
    tester,
  ) async {
    final container = await pumpChat(tester);
    await wait(tester);

    await ask(tester, 'set reminder for bov 25 its my physics exam');
    final set = container.read(assistantMemoryProvider).reminders.single;
    expect(set.title, 'Physics exam');
    expect(set.exam, isTrue);
    expect([set.at.month, set.at.day], [11, 25]);
    expect(
      container
          .read(chatProvider)
          .entries
          .any((e) => e.copy?.key.startsWith('Done. I’ll remind you') ?? false),
      isTrue,
    );

    await ask(tester, 'show my reminders');
    expect(find.text('Your reminders'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Remove reminder'));
    await tester.tap(find.byTooltip('Remove reminder'));
    await wait(tester, 2);
    expect(container.read(assistantMemoryProvider).reminders, isEmpty);

    await ask(tester, 'remind me about my chemistry test');
    expect(container.read(assistantMemoryProvider).reminders, isEmpty);
    unawaited(
      container
          .read(chatProvider.notifier)
          .setReminderDate(DateTime.now().add(const Duration(days: 3))),
    );
    await wait(tester);
    expect(
      container.read(assistantMemoryProvider).reminders.single.title,
      'Chemistry test',
    );

    // A time named without a date survives the date being picked after.
    await ask(tester, 'remind me to revise chemistry at 8am');
    final day = DateTime.now().add(const Duration(days: 4));
    unawaited(container.read(chatProvider.notifier).setReminderDate(day));
    await wait(tester);
    final revise = container
        .read(assistantMemoryProvider)
        .reminders
        .singleWhere((r) => r.title == 'Revise chemistry');
    expect(revise.at, DateTime(day.year, day.month, day.day, 8));
  });

  testWidgets('“check my leaderboard position” gets a leaderboard answer', (
    tester,
  ) async {
    final container = await pumpChat(tester);
    await wait(tester);
    await ask(tester, 'check my leaderboard position');
    expect(
      container
          .read(chatProvider)
          .entries
          .any((e) => e.copy?.key.contains('leaderboard') ?? false),
      isTrue,
    );
    expect(find.text('Open leaderboard'), findsOneWidget);
  });
}

/// A phone that has not let FocusForge notify.
class _NoNotifications implements PipNotificationAccess {
  const _NoNotifications();

  @override
  Future<bool> request() async => false;

  @override
  Future<bool> check() async => false;
}
