import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusforge/core/localization/app_strings.dart';
import 'package:focusforge/core/localization/translations.dart';

void main() {
  test('every bundled language has complete copy with matching interpolation slots', () {
    expect(AppStrings.supportedLocales.length, 25);
    final catalog = jsonDecode(
      File('localization/catalog.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final sourceKeys = catalog.keys.toSet();
    final slots = RegExp(r'\{\d+\}');
    for (final locale in AppStrings.supportedLocales.where(
      (l) => l.languageCode != 'en',
    )) {
      final copy = translations[locale.languageCode]!;
      expect(copy.keys.toSet(), sourceKeys, reason: locale.languageCode);
      for (final entry in copy.entries) {
        expect(entry.value, isNotEmpty, reason: entry.key);
        expect(entry.value, isNot(contains('ZXQ')), reason: entry.key);
        expect(
          slots.allMatches(entry.value).map((m) => m[0]).toSet(),
          slots.allMatches(entry.key).map((m) => m[0]).toSet(),
          reason: '${locale.languageCode}: ${entry.key}',
        );
      }
    }
  });
  test('phone language preference list chooses supported language with English fallback', () {
    expect(
      AppStrings.resolve(const [Locale('xx'), Locale('tr', 'TR')]),
      const Locale('tr'),
    );
    expect(AppStrings.resolve(const [Locale('hi', 'IN')]), const Locale('hi'));
    expect(AppStrings.resolve(const [Locale('zh', 'TW')]), const Locale('zh'));
    expect(AppStrings.resolve(const [Locale('xx')]), const Locale('en'));
  });
  test(
    'translated interpolation retains literal user text and percent values',
    () {
      final strings = AppStrings(const Locale('tr'));
      expect(strings.text('Start focus'), 'Odaklanmayı başlat');
      expect(
        strings.text('Avatar for {0}', ['My {1} name']),
        contains('My {1} name'),
      );
      expect(strings.text('Unknown future label'), 'Unknown future label');
    },
  );
  testWidgets(
    'language follows phone changes and Arabic changes reading direction',
    (tester) async {
      tester.binding.platformDispatcher.localesTestValue = const [
        Locale('tr', 'TR'),
      ];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: AppStrings.localizationsDelegates,
          localeListResolutionCallback: (locales, _) =>
              AppStrings.resolve(locales ?? const []),
          home: Builder(
            builder: (context) =>
                Scaffold(body: Text(context.tr('Start focus'))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Odaklanmayı başlat'), findsOneWidget);
      tester.binding.platformDispatcher.localesTestValue = const [Locale('ar')];
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(Text).first);
      expect(Directionality.of(context), TextDirection.rtl);
      expect(find.text('Start focus'), findsNothing);
    },
  );
}
