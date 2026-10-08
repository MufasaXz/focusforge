import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/study.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/audio_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/features/dashboard/widgets/session_shortcut.dart';
import 'package:focusforge/features/dashboard/widgets/day_summary_sheet.dart';
import 'package:focusforge/features/dashboard/widgets/study_tracker.dart';
import 'package:focusforge/core/data/seed.dart';
import 'package:focusforge/features/focus/focus_screen.dart';
import 'package:focusforge/features/focus/ambient_mixer.dart';
import 'package:focusforge/shared/widgets/pressable.dart';
import 'package:focusforge/shared/widgets/stagger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore store;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
  });

  setUp(() async => store.clearAll());

  ProviderContainer container() {
    final result = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    addTearDown(result.dispose);
    return result;
  }

  Widget wrap(
    ProviderContainer scope,
    Widget child, {
    bool reduce = true,
    double textScale = 1,
    ThemeData? theme,
  }) => UncontrolledProviderScope(
    container: scope,
    child: MaterialApp(
      theme: theme ?? AppTheme.light(),
      home: MediaQuery(
        data:
            MediaQueryData.fromView(
              WidgetsBinding.instance.platformDispatcher.views.first,
            ).copyWith(
              disableAnimations: reduce,
              textScaler: TextScaler.linear(textScale),
            ),
        child: Scaffold(body: child),
      ),
    ),
  );

  void phone(WidgetTester tester, {double width = 420}) {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  testWidgets('the named primary control starts and pauses the same block', (
    tester,
  ) async {
    phone(tester, width: 390);
    final scope = container();
    await tester.pumpWidget(wrap(scope, const FocusScreen()));
    await settle(tester);
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(scope.read(timerProvider).running, isTrue);
    final started = scope.read(timerProvider).segmentStartedAt;
    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(scope.read(timerProvider).running, isFalse);
    expect(scope.read(timerProvider).segmentStartedAt, started);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sound choices keep their names and placement when restored', (
    tester,
  ) async {
    phone(tester, width: 320);
    final scope = container();
    await tester.pumpWidget(wrap(scope, const AmbientMixerSection()));
    await settle(tester);
    final rainBefore = tester.getRect(find.text('Rain').first);
    final forestBefore = tester.getRect(find.text('Forest'));
    scope.read(activeSoundsProvider.notifier).hydrate({'rain'}, {});
    await settle(tester);
    expect(tester.getRect(find.text('Rain').first), rainBefore);
    expect(tester.getRect(find.text('Forest')), forestBefore);
    expect(find.byType(Slider), findsOneWidget);
    await tester.tap(find.text('Stop all'));
    await settle(tester);
    expect(scope.read(activeSoundsProvider), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('focus controls fit a narrow phone with large text', (
    tester,
  ) async {
    phone(tester, width: 320);
    await tester.pumpWidget(
      wrap(container(), const FocusScreen(), textScale: 2),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Home starts the selected plan and resumes without resetting it',
    (tester) async {
      final scope = container();
      final timer = scope.read(timerProvider.notifier);
      timer.setPreset(1);
      timer.setSubject('math');
      var opened = 0;
      await tester.pumpWidget(
        wrap(scope, SessionShortcut(onOpen: () => opened++)),
      );
      await tester.tap(find.text('Start focus'));
      await tester.pump();
      expect(scope.read(timerProvider).running, isTrue);
      expect(scope.read(timerProvider).presetIndex, 1);
      expect(scope.read(timerProvider).subjectId, 'math');
      expect(opened, 1);

      final deadline = scope.read(timerProvider).targetEnd;
      await tester.tap(find.text('View timer'));
      await tester.pump();
      expect(
        scope.read(timerProvider).targetEnd,
        deadline,
        reason: 'viewing a running timer must not restart its deadline',
      );

      await tester.pump(const Duration(seconds: 1));
      timer.pause();
      await tester.pump();
      final remaining = scope.read(timerProvider).remaining;
      await tester.tap(find.text('Resume'));
      await tester.pump();
      expect(scope.read(timerProvider).remaining, remaining);
      expect(scope.read(timerProvider).running, isTrue);
      timer.pause();
    },
  );

  testWidgets('a cancelled reset preserves the running block and deadline', (
    tester,
  ) async {
    phone(tester);
    final scope = container();
    final timer = scope.read(timerProvider.notifier);
    timer.start();
    final deadline = scope.read(timerProvider).targetEnd;
    await tester.pumpWidget(wrap(scope, const FocusScreen()));
    await settle(tester);
    await tester.tap(find.text('Reset'));
    await settle(tester);
    expect(find.text('Reset this focus block?'), findsOneWidget);
    await tester.tap(find.text('Keep session'));
    await settle(tester);
    expect(scope.read(timerProvider).targetEnd, deadline);
    expect(scope.read(timerProvider).running, isTrue);
    expect(scope.read(sessionsProvider), isEmpty);
    timer.pause();
  });

  testWidgets('confirming a reset discards only the unfinished block', (
    tester,
  ) async {
    phone(tester);
    final scope = container();
    final timer = scope.read(timerProvider.notifier);
    timer.start();
    timer.pause();
    await scope
        .read(sessionsProvider.notifier)
        .record(
          FocusSession(
            id: 'saved',
            subjectId: 'math',
            startedAt: DateTime.now(),
            minutes: 25,
          ),
        );
    await tester.pumpWidget(wrap(scope, const FocusScreen()));
    await settle(tester);
    await tester.tap(find.text('Reset'));
    await settle(tester);
    await tester.tap(find.text('Reset block'));
    await settle(tester);
    expect(scope.read(timerProvider).segmentStartedAt, isNull);
    expect(scope.read(timerProvider).running, isFalse);
    expect(scope.read(sessionsProvider).single.id, 'saved');
  });

  testWidgets('a confirmation expires when its block finishes', (tester) async {
    phone(tester);
    final scope = container();
    final timer = scope.read(timerProvider.notifier);
    timer.start();
    await tester.pumpWidget(wrap(scope, const FocusScreen()));
    await settle(tester);
    await tester.tap(find.text('Skip'));
    await settle(tester);
    // Represents a completion received while the dialog was open. Confirming
    // the old question must not skip the new phase as well.
    timer.skip();
    final phase = scope.read(timerProvider).phase;
    await tester.tap(find.text('Skip block'));
    await settle(tester);
    expect(scope.read(timerProvider).phase, phase);
    timer.pause();
  });

  testWidgets('reselecting the current preset keeps the session', (
    tester,
  ) async {
    phone(tester);
    final scope = container();
    final timer = scope.read(timerProvider.notifier);
    timer.start();
    final deadline = scope.read(timerProvider).targetEnd;
    await tester.pumpWidget(wrap(scope, const FocusScreen()));
    await settle(tester);
    await tester.tap(find.text('Classic Pomodoro'));
    await settle(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Classic Pomodoro'));
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(scope.read(timerProvider).targetEnd, deadline);
    timer.pause();
  });

  testWidgets('cancelling a preset change preserves the original deadline', (
    tester,
  ) async {
    phone(tester);
    final scope = container();
    final timer = scope.read(timerProvider.notifier);
    timer.start();
    final deadline = scope.read(timerProvider).targetEnd;
    await tester.pumpWidget(wrap(scope, const FocusScreen()));
    await settle(tester);
    await tester.tap(find.text('Classic Pomodoro'));
    await settle(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Deep Work'));
    await settle(tester);
    await tester.tap(find.text('Keep session'));
    await settle(tester);
    expect(scope.read(timerProvider).presetIndex, 0);
    expect(scope.read(timerProvider).targetEnd, deadline);
    timer.pause();
  });

  test(
    'the day log and summary share completed sessions, oldest first',
    () async {
      final scope = container();
      final log = scope.read(sessionsProvider.notifier);
      final day = DateTime(2026, 10, 8);
      for (final session in [
        FocusSession(
          id: 'late',
          subjectId: 'math',
          startedAt: day.add(const Duration(hours: 14)),
          minutes: 50,
        ),
        FocusSession(
          id: 'early',
          subjectId: 'math',
          startedAt: day.add(const Duration(hours: 9)),
          minutes: 25,
        ),
        FocusSession(
          id: 'unfinished',
          subjectId: '',
          startedAt: day.add(const Duration(hours: 10)),
          minutes: 20,
          completed: false,
        ),
        FocusSession(
          id: 'other-day',
          subjectId: 'math',
          startedAt: day.subtract(const Duration(days: 1)),
          minutes: 90,
        ),
      ]) {
        await log.record(session);
      }
      final sessions = scope.read(daySessionsProvider(day));
      expect(sessions.map((s) => s.id), ['early', 'late']);
      final summary = scope.read(daySummaryProvider(day));
      expect(summary.sessions, sessions.length);
      expect(summary.totalMinutes, 75);
      expect(scope.read(sessionsProvider).map((s) => s.id), [
        'late',
        'early',
        'unfinished',
        'other-day',
      ], reason: 'the day view must not reorder the persisted log');
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'the day sheet fits large text in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        phone(tester, width: 320);
        final scope = container();
        final day = DateTime(2026, 10, 8);
        await scope
            .read(sessionsProvider.notifier)
            .record(
              FocusSession(
                id: 'deleted-subject',
                subjectId: 'deleted',
                label: 'Thesis',
                startedAt: day.add(const Duration(hours: 9)),
                minutes: 50,
              ),
            );
        await tester.pumpWidget(
          wrap(
            scope,
            DaySummarySheet(day: day),
            textScale: 2,
            theme: dark ? AppTheme.dark(amoled: true) : AppTheme.light(),
          ),
        );
        await settle(tester);
        expect(find.text('Thesis'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('the session dock fits a 320dp phone', (tester) async {
    phone(tester, width: 320);
    await tester.pumpWidget(wrap(container(), const FocusScreen()));
    await settle(tester);
    for (final label in ['Reset', 'Skip', '-5', '+5']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('each chart day offers a named action and keyboard activation', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final day = DayBar('Thu', 1, date: DateTime(2026, 10, 8));
    DayBar? opened;
    await tester.pumpWidget(
      wrap(
        container(),
        StudyTracker(days: [day], onDayTap: (value) => opened = value),
      ),
    );
    await settle(tester);
    final action = find.bySemanticsLabel(
      'Thursday, 8 October. 1 hour focused. View day summary',
    );
    expect(action, findsOneWidget);
    expect(
      tester
          .getSemantics(action)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opened, same(day));
    handle.dispose();
  });

  testWidgets('reduced motion reveals delayed content immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(container(), const Stagger(index: 100, child: Text('Ready'))),
    );
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1,
    );
    final transform = tester.widget<Transform>(find.byType(Transform).last);
    expect(transform.transform.getTranslation().y, 0);
  });

  testWidgets('an offstage entrance waits until its branch is visible', (
    tester,
  ) async {
    final scope = container();
    var visible = false;
    late StateSetter update;
    await tester.pumpWidget(
      wrap(
        scope,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return TickerMode(
              enabled: visible,
              child: const Stagger(index: 1, child: Text('Ready')),
            );
          },
        ),
        reduce: false,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0,
    );
    update(() => visible = true);
    await tester.pump();
    await settle(tester);
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1,
    );
  });

  testWidgets('reduced motion keeps a pressed control at its original scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        container(),
        Center(
          child: Pressable(
            onTap: () {},
            child: const SizedBox(width: 80, height: 48),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Pressable)),
    );
    await tester.pump();
    final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(scale.scale, 1);
    expect(scale.duration, Duration.zero);
    await gesture.up();
  });
}
