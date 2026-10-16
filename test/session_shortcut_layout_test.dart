import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/data/seed.dart';
import 'package:focusforge/core/localization/app_strings.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/features/dashboard/widgets/session_shortcut.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  Future<ProviderContainer> mount(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
    bool random = false,
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    final scope = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    addTearDown(scope.dispose);
    scope.read(subjectsProvider.notifier).hydrate([
      SeedData.subjects.first.toJson(),
    ]);
    scope.read(timerProvider.notifier).setSubject('math');
    if (random) {
      await scope
          .read(planLibraryProvider.notifier)
          .save(
            const CustomPlan(
              id: 'random-home',
              name: 'Flexible focus',
              goalMinutes: 120,
              focusMinutes: 30,
              randomMinMinutes: 20,
              randomMaxMinutes: 40,
            ),
          );
      final index = scope
          .read(presetsProvider)
          .indexWhere((preset) => preset.key == 'custom:random-home');
      await scope.read(timerProvider.notifier).setPreset(index);
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: MaterialApp(
          theme: AppTheme.dark(),
          locale: locale,
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: AppStrings.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: SessionShortcut(onOpen: () {}),
              ),
            ),
          ),
        ),
      ),
    );
    return scope;
  }

  testWidgets('Home keeps the subject beside its action on a phone', (
    tester,
  ) async {
    await mount(tester);
    final subject = tester.getRect(find.text('Math'));
    final detail = tester.getRect(find.text('25m focus · 5m break'));
    final action = tester.getRect(find.byType(FilledButton));
    expect(action.left, greaterThan(detail.right));
    expect(action.top, lessThan(subject.bottom));
    expect(action.bottom, greaterThan(detail.top));
    expect(action.right, closeTo(350, 0.1));
    expect(tester.takeException(), isNull);
  });

  for (final locale in const [
    Locale('tr'),
    Locale('ar'),
    Locale('hi'),
    Locale('ja'),
  ]) {
    testWidgets(
      'Home shortcut fits compact translated copy for ${locale.languageCode}',
      (tester) async {
        await mount(tester, width: 320, scale: 1.5, locale: locale);
        expect(
          find.text(AppStrings(locale).text('Start focus')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        final action = tester.getRect(find.byType(FilledButton));
        expect(action.left, greaterThanOrEqualTo(40));
        expect(action.right, lessThanOrEqualTo(280));
        if (locale.languageCode == 'ar') {
          expect(
            Directionality.of(tester.element(find.byType(FilledButton))),
            TextDirection.rtl,
          );
        }
      },
    );
  }

  testWidgets('Home gives enlarged text room above its action', (tester) async {
    await mount(tester, width: 320, scale: 2);
    final detail = tester.getRect(find.text('25m focus · 5m break'));
    final action = tester.getRect(find.byType(FilledButton));
    expect(action.top, greaterThan(detail.bottom));
    expect(action.left, closeTo(40, 0.1));
    expect(action.right, closeTo(280, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home stacks before timing text is squeezed by a wider action', (
    tester,
  ) async {
    await mount(tester, scale: 1.35);
    final detail = tester.getRect(find.text('25m focus · 5m break'));
    final action = tester.getRect(find.byType(FilledButton));
    expect(action.top, greaterThan(detail.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home preserves the hidden duration of a random focus block', (
    tester,
  ) async {
    final scope = await mount(tester, random: true);
    expect(find.text('Time stays hidden'), findsOneWidget);
    expect(find.textContaining('m focus'), findsNothing);
    await tester.tap(find.text('Start focus'));
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('Time stays hidden'), findsOneWidget);
    expect(find.textContaining('left'), findsNothing);
    scope.read(timerProvider.notifier).pause();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpWidget(const SizedBox());
    scope.dispose();
    await tester.pump(const Duration(milliseconds: 1));
  });
}
