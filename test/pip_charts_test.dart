// The charts inside Pip's cards.
//
// WHAT INVARIANT: a report shows the week as a column for each day, with
// today picked; tapping another column reads that day out underneath, next
// to what the same day was last week; every column says its day and time to
// a screen reader; a breakdown shows each subject's share of the whole; and
// with reduce motion on, a chart is simply drawn, with nothing left running.
//
// WHY IT MATTERS: a chart nobody can read exact numbers from, or that a
// screen reader skips, is decoration. One that never settles hangs the page.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/features/assistant/brain/assistant_models.dart';
import 'package:focusforge/features/assistant/chat/chat_cards.dart';
import 'package:focusforge/features/assistant/chat/chat_charts.dart';

void main() {
  const report = ReportCard(
    todayMinutes: 90,
    goalMinutes: 180,
    weekMinutes: 210,
    lastWeekSpanMinutes: 150,
    streak: 4,
    subjects: [
      SubjectTrend(
        id: 'physics',
        name: 'Physics',
        color: Colors.purple,
        thisWeek: 150,
        lastWeekSpan: 60,
        today: 90,
      ),
      SubjectTrend(
        id: 'math',
        name: 'Mathematics',
        color: Colors.blue,
        thisWeek: 60,
        lastWeekSpan: 90,
        today: 0,
      ),
    ],
    usageReady: true,
    distractingMinutes: 40,
    topApps: [AppMinutes('com.example.video', 'YouTube', 40)],
    days: [120, 0, 90, 0, 0, 0, 0],
    lastDays: [45, 105, 30, 0, 60, 0, 0],
    today: 2,
    notes: [
      ReportNote(
        Icons.schedule_rounded,
        Copy('You focus most in the evening.'),
      ),
    ],
  );

  Future<void> pump(
    WidgetTester tester,
    Widget card, {
    bool reduceMotion = false,
    double textScale = 1,
    double width = 390,
  }) async {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reduceMotion,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: card,
          ),
        ),
      ),
    );
  }

  testWidgets('the week chart opens on today and reads out a tapped day', (
    tester,
  ) async {
    await pump(tester, const ReportCardView(card: report));
    expect(find.text('3h 30m'), findsOneWidget);
    expect(find.text('1h 30m of 3h'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    // Wednesday is today.
    expect(find.text('Wednesday · 1h 30m'), findsOneWidget);
    expect(find.text('Last week 30m'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Tuesday · 0m'));
    await tester.pump();
    expect(find.text('Tuesday · 0m'), findsOneWidget);
    expect(find.text('Last week 1h 45m'), findsOneWidget);
    expect(find.text('Wednesday · 1h 30m'), findsNothing);

    // What Pip noticed sits under the charts.
    expect(find.text('You focus most in the evening.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every day is a labelled button of at least 48 dp', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(tester, const ReportCardView(card: report), width: 320);
    for (final day in ['Monday · 2h', 'Tuesday · 0m', 'Sunday · 0m']) {
      final node = find.bySemanticsLabel(day);
      expect(node, findsOneWidget, reason: day);
      expect(tester.getSize(node).height, greaterThanOrEqualTo(48));
    }
    expect(
      tester.getSemantics(find.bySemanticsLabel('Monday · 2h')),
      matchesSemantics(
        label: 'Monday · 2h',
        value: 'Last week 45m',
        isButton: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('a fresh chart draws in and then stops', (tester) async {
    await pump(tester, const ReportCardView(card: report, animate: true));
    // Still drawing a frame in, then done: nothing keeps the page awake.
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('with reduce motion a fresh chart is drawn at once', (
    tester,
  ) async {
    await pump(
      tester,
      const ReportCardView(card: report, animate: true),
      reduceMotion: true,
    );
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.byType(WeekBars), findsOneWidget);
  });

  testWidgets('large text on a narrow phone still fits the report', (
    tester,
  ) async {
    await pump(
      tester,
      const ReportCardView(card: report),
      textScale: 1.6,
      width: 320,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a breakdown shows the total and each subject’s share', (
    tester,
  ) async {
    await pump(
      tester,
      const BreakdownCardView(
        card: BreakdownCard(
          title: Copy('Today'),
          totalMinutes: 80,
          goalMinutes: 120,
          shares: [
            Share('Physics', Colors.purple, 60),
            Share('Mathematics', Colors.blue, 20),
          ],
        ),
      ),
    );
    expect(find.text('1h 20m of 2h'), findsOneWidget);
    expect(find.text('67%'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(find.byType(PartsBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
