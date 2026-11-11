// Talking to Pip.
//
// WHAT INVARIANT: the chat introduces Pip and asks for the user's exam once;
// a chip carries its request in any language; a typed "lock instagram" finds
// the app and, on one tap, puts it in Shield's focus tier; a plan saved as
// today's goal counts what is already done; "start a block" starts the timer
// on the plan's first subject. A longer question goes online only after the
// user agrees and only for a signed-in account, carries no name, and falls
// back to the phone's answer when the network fails.
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
import 'package:focusforge/core/services/ai_backend_service.dart';
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

  Future<ProviderContainer> pumpChat(
    WidgetTester tester, {
    AiBackend? backend,
    String? uid,
  }) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final engine = RecordingShieldService();
    addTearDown(engine.dispose);
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        aiBackendProvider.overrideWithValue(backend),
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

  const question = 'I have not studied this week, what should I do tonight?';

  Future<void> ask(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await wait(tester);
  }

  testWidgets('a long question goes online once the user agrees', (
    tester,
  ) async {
    final backend = _FakeBackend(
      reply: 'One 40 minute block of Physics tonight. Start small.',
    );
    final container = await pumpChat(tester, backend: backend, uid: 'u1');
    await wait(tester);

    await ask(tester, question);
    expect(backend.questions, isEmpty);
    expect(
      find.textContaining('smarter answers', findRichText: true),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Allow'));
    await tester.tap(find.text('Allow'));
    await wait(tester);

    expect(container.read(assistantMemoryProvider).aiConsent, isTrue);
    expect(backend.questions, [question]);
    expect(
      find.text('One 40 minute block of Physics tonight. Start small.'),
      findsOneWidget,
    );
    // The study summary carries numbers, never who the user is.
    expect(jsonOf(backend.contexts.single), isNot(contains('Rivera')));
    expect(backend.histories.single, isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only the user\'s words and online answers are sent', (
    tester,
  ) async {
    final backend = _FakeBackend(reply: 'Short blocks, then a long one.');
    final container = await pumpChat(tester, backend: backend, uid: 'u1');
    await container.read(assistantMemoryProvider.notifier).setAiConsent(true);
    await wait(tester);
    await ask(tester, 'what is my top subject');

    await ask(tester, question);
    expect(backend.questions, [question]);
    final sent = backend.histories.single;
    expect(sent.where((turn) => turn['role'] == 'pip'), isEmpty);
    expect(jsonOf(sent), isNot(contains('Sam')));
  });

  testWidgets('the header says where answers come from, and going online '
      'asks first without losing the draft', (tester) async {
    final backend = _FakeBackend(reply: 'unused');
    final container = await pumpChat(tester, backend: backend, uid: 'u1');
    await wait(tester);
    expect(find.text('Answers stay on this phone'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'half-typed question');
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Answer with AI when online'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Never your name or email.'),
      findsOneWidget,
      reason: 'what would be sent is said before it is allowed',
    );
    await tester.tap(find.text('Keep it on this phone'));
    await tester.pumpAndSettle();
    expect(container.read(assistantMemoryProvider).aiConsent, isNot(true));
    expect(find.text('Answers stay on this phone'), findsOneWidget);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Answer with AI when online'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();
    expect(container.read(assistantMemoryProvider).aiConsent, isTrue);
    expect(find.text('Online answers on'), findsOneWidget);
    expect(find.text('half-typed question'), findsOneWidget);
    expect(backend.questions, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('turning online answers off before sending keeps it here', (
    tester,
  ) async {
    final backend = _FakeBackend(reply: 'unused');
    final container = await pumpChat(tester, backend: backend, uid: 'u1');
    await container.read(assistantMemoryProvider.notifier).setAiConsent(true);
    await wait(tester);

    await tester.enterText(find.byType(TextField), question);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump(const Duration(milliseconds: 20));
    await container.read(chatProvider.notifier).setOnlineAnswers(false);
    await wait(tester);
    expect(backend.questions, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline, Pip says so and the phone answers', (tester) async {
    final backend = _FakeBackend(failure: AiFailure.unavailable);
    final container = await pumpChat(tester, backend: backend, uid: 'u1');
    await container.read(assistantMemoryProvider.notifier).setAiConsent(true);
    await wait(tester);

    await ask(tester, 'can you please make a study plan for me today');
    expect(backend.questions, hasLength(1));
    expect(
      find.textContaining('can’t reach my online brain', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Save as today’s goal'), findsOneWidget);
  });

  testWidgets('a guest gets one sign-in note and the phone’s answers', (
    tester,
  ) async {
    final backend = _FakeBackend(reply: 'unused');
    final container = await pumpChat(tester, backend: backend);
    await wait(tester);

    await ask(tester, question);
    await ask(tester, 'what should I study first tomorrow morning then?');
    expect(backend.questions, isEmpty);
    final notes = container
        .read(chatProvider)
        .entries
        .where(
          (e) => e.copy?.key.startsWith('Sign in with your account') ?? false,
        );
    expect(notes, hasLength(1));
    // The phone still answered both questions.
    expect(
      container.read(chatProvider).entries.where((e) => e.fromPip).length,
      greaterThan(3),
    );
  });

  testWidgets('after “keep it on this phone” nothing goes online', (
    tester,
  ) async {
    final backend = _FakeBackend(reply: 'unused');
    final container = await pumpChat(tester, backend: backend, uid: 'u1');
    await wait(tester);

    await ask(tester, question);
    await tester.ensureVisible(find.text('Keep it on this phone'));
    await tester.tap(find.text('Keep it on this phone'));
    await wait(tester);
    await ask(tester, 'what should I study first tomorrow morning then?');

    expect(container.read(assistantMemoryProvider).aiConsent, isFalse);
    expect(backend.questions, isEmpty);
  });
  test('an online answer loses its Markdown marks and keeps its list', () {
    expect(
      tidyAnswer(
        '## Tonight\r\n\r\n\r\n**Start small:**\n- one `40 minute` block\n'
        '* ten questions\n\nThen rest.  ',
      ),
      'Tonight\n\nStart small:\n• one 40 minute block\n• ten questions\n\n'
      'Then rest.',
    );
    // Plain answers pass through, a multiplication sign included.
    expect(tidyAnswer('2 * 3 is 6. Keep going.'), '2 * 3 is 6. Keep going.');
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
  testWidgets('five online answers a day, then the phone answers', (
    tester,
  ) async {
    final backend = _FakeBackend(reply: 'Online answer.');
    final container = await pumpChat(tester, backend: backend, uid: 'u1');
    await container.read(assistantMemoryProvider.notifier).setAiConsent(true);
    await wait(tester);

    for (var i = 0; i < ChatController.onlineAnswersPerDay + 2; i++) {
      await ask(tester, 'please tell me one good way to revise physics');
    }
    expect(backend.questions, hasLength(ChatController.onlineAnswersPerDay));
    final energy = container
        .read(chatProvider)
        .entries
        .where(
          (e) => e.copy?.key.startsWith('Daily Pip energy used up!') ?? false,
        );
    expect(energy, hasLength(1));
  });

  testWidgets('an online answer can be reported, and the study summary '
      'names no apps', (tester) async {
    final backend = _FakeBackend(reply: 'An answer to report.');
    final container = await pumpChat(tester, backend: backend, uid: 'u1');
    await container.read(assistantMemoryProvider.notifier).setAiConsent(true);
    await wait(tester);
    expect(find.textContaining('Pip is an AI study assistant'), findsOneWidget);

    await ask(tester, question);
    expect(backend.contexts.single!.containsKey('topDistractingApps'), isFalse);
    expect(backend.contexts.single!['distractingMinutesToday'], 48);

    await tester.tap(find.byTooltip('Report this answer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Incorrect or misleading advice'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Report'));
    // The report is saved and sent before the thanks shows.
    await wait(tester, 1);

    expect(backend.reports.single.$1, 'incorrect');
    expect(backend.reports.single.$2, 'An answer to report.');
    expect(backend.reports.single.$3, question);
    expect(find.text('Thanks. This answer will be reviewed.'), findsOneWidget);
    final kept =
        container
                .read(localStoreProvider)
                .getMap(StoreKeys.assistantReports)!['items']
            as List;
    expect(kept.single['reason'], 'incorrect');
  });
}

String jsonOf(Object? value) => '$value';

/// Answers or fails like the online backend, recording what it was sent.
class _FakeBackend implements AiBackend {
  _FakeBackend({this.reply, this.failure});

  final String? reply;
  final AiFailure? failure;
  final questions = <String>[];
  final contexts = <Map<String, dynamic>?>[];
  final histories = <List<Map<String, String>>>[];

  @override
  Future<String> askAiAssistant({
    required String userMessage,
    Map<String, dynamic>? extraContext,
    List<Map<String, String>> history = const [],
    String locale = 'en',
    bool Function()? allowed,
  }) async {
    questions.add(userMessage);
    contexts.add(extraContext);
    histories.add(history);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (failure case final failure?) throw AiBackendException(failure);
    return reply!;
  }

  @override
  Future<void> reportReply({
    required String reply,
    required String reason,
    String? question,
  }) async => reports.add((reason, reply, question));

  final reports = <(String, String, String?)>[];
}

/// A phone that has not let FocusForge notify.
class _NoNotifications implements PipNotificationAccess {
  const _NoNotifications();

  @override
  Future<bool> request() async => false;

  @override
  Future<bool> check() async => false;
}
