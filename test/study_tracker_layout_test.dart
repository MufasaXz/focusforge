import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/data/seed.dart';
import 'package:focusforge/features/dashboard/widgets/study_tracker.dart';
import 'package:focusforge/shared/widgets/pressable.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('month dates remain usable on a narrow phone, dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final days = List.generate(
        31,
        (i) => DayBar(
          '',
          i.isEven ? 2 : .25,
          isToday: i == 30,
          date: DateTime(2026, 10, i + 1),
        ),
      );
      DayBar? opened;
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(
              disableAnimations: true,
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: StudyTracker(
                  days: days,
                  month: true,
                  onDayTap: (day) => opened = day,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final scroll = find.byKey(const ValueKey('month-progress-scroll'));
      expect(scroll, findsOneWidget);
      expect(
        tester.getSize(find.byType(Pressable).first).width,
        greaterThanOrEqualTo(44),
      );
      await tester.tap(find.text('31'));
      await tester.pump();
      expect(opened, same(days.last));
      await tester.drag(scroll, const Offset(1600, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1'));
      await tester.pump();
      expect(opened, same(days.first));
      expect(tester.takeException(), isNull);
    });
  }
}
