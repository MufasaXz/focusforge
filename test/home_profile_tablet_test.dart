import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/data/seed.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/providers/usage_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/features/dashboard/dashboard_screen.dart';
import 'package:focusforge/features/dashboard/widgets/subject_breakdown.dart';
import 'package:focusforge/features/profile/profile_screen.dart';
import 'package:focusforge/features/profile/widgets/avatar_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore store;

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
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
  });

  setUp(() async {
    await store.clearAll();
    await store.setBool(StoreKeys.coachSeen, true);
  });

  ProviderContainer container() {
    final value = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        usageAccessProvider.overrideWith((ref) async => false),
      ],
    );
    addTearDown(value.dispose);
    value
        .read(userProvider.notifier)
        .hydrate(
          const UserProfile(
            displayName: 'Alexandria Morgan Rivera',
            onboardingComplete: true,
          ),
        );
    value.read(subjectsProvider.notifier).hydrate([
      const Subject(
        id: 'math',
        name: 'Mathematics',
        icon: Icons.school_rounded,
        color: Colors.blue,
      ).toJson(),
    ]);
    return value;
  }

  Widget host(ProviderContainer value, Widget screen, {double scale = 1}) =>
      UncontrolledProviderScope(
        container: value,
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
          home: Scaffold(body: screen),
        ),
      );

  testWidgets('Home waits for an explicitly assigned completed session', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final value = container();
    await tester.pumpWidget(host(value, const DashboardScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(SubjectBreakdown), findsNothing);
    for (final assigned in [false, true]) {
      value.read(sessionsProvider.notifier).hydrate([
        FocusSession(
          id: 'unassigned',
          subjectId: '',
          startedAt: DateTime.now(),
          minutes: 25,
        ).toJson(),
        FocusSession(
          id: 'abandoned',
          subjectId: 'math',
          startedAt: DateTime.now(),
          minutes: 5,
          completed: false,
        ).toJson(),
        if (assigned)
          FocusSession(
            id: 'assigned',
            subjectId: 'math',
            startedAt: DateTime.now(),
            minutes: 25,
          ).toJson(),
      ]);
      await tester.pumpAndSettle();
      // ListView builds lazily; reach the bottom before checking the card.
      final scroll = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      scroll.jumpTo(scroll.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        find.byType(SubjectBreakdown),
        assigned ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
  });

  for (final width in [800.0, 920.0, 1280.0]) {
    for (final page in <String, Widget>{
      'Home': const DashboardScreen(),
      'Profile': const ProfileScreen(),
    }.entries) {
      testWidgets(
        '${page.key} scrolls at tablet width $width with enlarged text',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final value = container();
          value.read(sessionsProvider.notifier).hydrate([
            FocusSession(
              id: 'math',
              subjectId: 'math',
              startedAt: DateTime.now(),
              minutes: 45,
            ).toJson(),
          ]);
          value
              .read(statsProvider.notifier)
              .hydrate(
                const GamificationStats(
                  level: 50,
                  xp: 1234,
                  totalFocusHours: 1234.5,
                  totalSessions: 1500,
                ),
              );
          await tester.pumpWidget(host(value, page.value, scale: 1.5));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (var step = 0; step < 30; step++) {
            final scroll = tester
                .stateList<ScrollableState>(find.byType(Scrollable))
                .where((state) => state.position.axis == Axis.vertical)
                .first
                .position;
            if (scroll.pixels == scroll.maxScrollExtent) break;
            scroll.jumpTo(
              (scroll.pixels + 500).clamp(0, scroll.maxScrollExtent),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
          if (page.key == 'Profile') {
            final profileWidth = tester
                .getSize(find.byKey(const ValueKey('profile-scroll')))
                .width;
            expect(
              profileWidth,
              lessThanOrEqualTo(
                width < Layout.wide
                    ? Layout.readable
                    : Layout.readable * 2 + Gap.xl,
              ),
            );
          }
        },
      );
    }
  }

  testWidgets('avatar frames follow level tiers and retain initials', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    for (final entry in {
      1: 'Bronze',
      11: 'Silver',
      21: 'Gold',
      31: 'Emerald',
      41: 'Diamond',
      50: 'Diamond',
    }.entries) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AvatarDisc(
              user: const UserProfile(displayName: 'Sam Rivera'),
              size: 96,
              level: entry.key,
            ),
          ),
        ),
      );
      expect(find.text('SR'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Avatar for Sam Rivera. Level ${entry.key}, ${entry.value} frame',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
    semantics.dispose();
  });
}
