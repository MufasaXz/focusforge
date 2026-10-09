import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/shield.dart';
import 'package:focusforge/core/models/study.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/providers/usage_providers.dart';
import 'package:focusforge/core/services/app_catalog.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/features/profile/widgets/focus_overview.dart';
import 'package:focusforge/features/shield/shield_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> container() async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    final engine = RecordingShieldService();
    addTearDown(engine.dispose);
    final c = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        shieldServiceProvider.overrideWithValue(engine),
        installedAppsProvider.overrideWith(
          (ref) async => const [
            InstalledApp(
              packageId: 'com.example.social',
              name: 'Social',
              isSystem: false,
            ),
            InstalledApp(
              packageId: 'com.example.video',
              name: 'Video',
              isSystem: false,
            ),
            InstalledApp(
              packageId: 'com.example.reader',
              name: 'Reader',
              isSystem: false,
            ),
          ],
        ),
        appUsageTodayProvider.overrideWith((ref) async => const {}),
        usageAccessProvider.overrideWith((ref) async => true),
        shieldEnabledProvider.overrideWith((ref) async => true),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Widget wrap(ProviderContainer c, Widget child, {double textScale = 1}) =>
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: Scaffold(body: child),
        ),
      );

  testWidgets(
    'Shield filters compose with package search and never change rules',
    (tester) async {
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = await container();
      await c
          .read(whitelistProvider.notifier)
          .addInstalledApp(packageId: 'com.example.social', name: 'Social');
      await c
          .read(whitelistProvider.notifier)
          .addInstalledApp(
            packageId: 'com.example.video',
            name: 'Video',
            tier: WhitelistTier.budgeted,
          );
      await tester.pumpWidget(wrap(c, const ShieldScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Blocked'));
      await tester.pumpAndSettle();
      expect(find.text('Social'), findsOneWidget);
      expect(find.text('Video'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Budgets'));
      await tester.pumpAndSettle();
      expect(find.text('Video'), findsOneWidget);
      expect(find.text('Social'), findsNothing);
      await tester.enterText(find.byType(TextField), 'com.example.video');
      await tester.pumpAndSettle();
      expect(find.text('Video'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'no-such-app');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show all apps'));
      await tester.pumpAndSettle();
      expect(find.text('Social'), findsOneWidget);
      expect(find.text('Video'), findsOneWidget);
      expect(find.text('Reader'), findsOneWidget);
      expect(c.read(whitelistProvider), hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Shield fits a narrow phone with enlarged text', (tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = await container();
    await tester.pumpWidget(wrap(c, const ShieldScreen(), textScale: 2));
    await tester.pumpAndSettle();
    expect(find.text('Shield'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'weekly recap uses completed sessions and goal shortcut opens the editor',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = await container();
      final today = DateTime.now();
      c.read(sessionsProvider.notifier).hydrate([
        FocusSession(
          id: 'complete',
          subjectId: 'math',
          startedAt: today,
          minutes: 25,
        ).toJson(),
        FocusSession(
          id: 'unfinished',
          subjectId: 'math',
          startedAt: today,
          minutes: 50,
          completed: false,
        ).toJson(),
      ]);
      await tester.pumpWidget(
        wrap(c, const SingleChildScrollView(child: FocusOverview())),
      );
      await tester.pumpAndSettle();
      expect(find.text('25m'), findsOneWidget);
      expect(find.text('1 active day in the last 7 days'), findsOneWidget);
      await tester.tap(find.text('Adjust goal'));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsNWidgets(7));
      expect(tester.takeException(), isNull);
    },
  );
}
