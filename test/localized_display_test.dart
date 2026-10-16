import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusforge/core/localization/app_strings.dart';
import 'package:focusforge/core/localization/display_labels.dart';
import 'package:focusforge/core/models/study.dart';
import 'package:focusforge/core/utils/format.dart';
import 'package:focusforge/shared/widgets/sheet_chrome.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('date and duration display use the supplied locale and normalize minute carry', () {
    expect(
      formatDate(DateTime(2026, 10, 16), locale: const Locale('tr')),
      '16 Ekim Cuma',
    );
    expect(formatHours(1.999, locale: const Locale('en')), '2h');
    expect(
      formatHoursShort(1.5, locale: const Locale('fr')),
      '{0}h'.replaceAll('{0}', '1,5'),
    );
    expect(
      formatClock(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
  });

  testWidgets('stock names localize while a user plan name stays literal', (
    tester,
  ) async {
    const custom = PomodoroPreset(
      id: 'custom:mine',
      name: 'Start focus',
      icon: Icons.timer,
      focus: 25,
      shortBreak: 5,
      longBreak: 15,
      segments: 4,
    );
    const stock = PomodoroPreset(
      name: 'Start focus',
      icon: Icons.timer,
      focus: 25,
      shortBreak: 5,
      longBreak: 15,
      segments: 4,
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('tr'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: AppStrings.localizationsDelegates,
        home: Builder(
          builder: (context) => Column(
            children: [
              Text(presetDisplayName(context, stock)),
              Text(presetDisplayName(context, custom)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Odaklanmayı başlat'), findsOneWidget);
    expect(find.text('Start focus'), findsOneWidget);
  });

  testWidgets(
    'shared close semantics follows widget locale while preserving custom labels',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('tr'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: AppStrings.localizationsDelegates,
          home: Scaffold(
            body: Column(
              children: [
                SheetCloseButton(onTap: () {}),
                SheetCloseButton(onTap: () {}, label: 'My custom action'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final labels = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .map((widget) => widget.properties.label)
          .whereType<String>()
          .toList();
      expect(labels, contains(AppStrings(const Locale('tr')).text('Close')));
      expect(labels, contains('My custom action'));
    },
  );
}
