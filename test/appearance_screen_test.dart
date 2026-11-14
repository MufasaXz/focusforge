import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/router.dart';
import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/features/profile/profile_screen.dart';
import 'package:focusforge/features/settings/appearance_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStore store;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
  });

  setUp(() async => store.clearAll());

  ProviderContainer container({bool linked = false}) {
    final engine = RecordingShieldService();
    addTearDown(engine.dispose);
    final c = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        shieldServiceProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(c.dispose);
    c
        .read(userProvider.notifier)
        .hydrate(
          UserProfile(
            uid: linked ? 'uid-1' : 'local',
            displayName: 'Asha',
            isAnonymous: !linked,
          ),
        );
    return c;
  }

  Widget app(
    ProviderContainer c, {
    required String start,
    bool dark = false,
    Size size = const Size(412, 915),
  }) {
    final router = GoRouter(
      initialLocation: start,
      routes: [
        GoRoute(
          path: '/profile',
          name: AppRoutes.profile,
          builder: (context, state) => const Scaffold(body: ProfileScreen()),
          routes: [
            GoRoute(
              path: 'appearance',
              name: AppRoutes.appearance,
              builder: (context, state) => const AppearanceScreen(),
            ),
            GoRoute(
              path: 'clock-face',
              name: AppRoutes.clockFace,
              builder: (context, state) =>
                  const Scaffold(body: Text('clock face page')),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    return UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
      ),
    );
  }

  void phone(WidgetTester tester, [Size size = const Size(412, 915)]) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('the Appearance row names the palette and opens its page', (
    tester,
  ) async {
    phone(tester);
    final c = container(linked: true);
    await tester.pumpWidget(app(c, start: '/profile'));
    await tester.pumpAndSettle();

    final palette = c.read(themeSettingsProvider).palette;
    final row = find.ancestor(
      of: find.text('Appearance'),
      matching: find.byType(InkWell),
    );
    expect(
      find.descendant(of: row.first, matching: find.text(palette.label)),
      findsOneWidget,
    );

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Accent color'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picking a palette and a theme updates the settings', (
    tester,
  ) async {
    phone(tester);
    final c = container();
    await tester.pumpWidget(app(c, start: '/profile/appearance'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tide'));
    await tester.pumpAndSettle();
    expect(c.read(themeSettingsProvider).palette, AppPalette.tide);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(c.read(themeSettingsProvider).mode, ThemePreference.dark);
    expect(tester.takeException(), isNull);
  });

  testWidgets('true black is offered only when the app is dark', (
    tester,
  ) async {
    phone(tester);
    final c = container();
    await tester.pumpWidget(app(c, start: '/profile/appearance'));
    await tester.pumpAndSettle();
    expect(find.text('True black'), findsNothing);

    await tester.pumpWidget(app(c, start: '/profile/appearance', dark: true));
    await tester.pumpAndSettle();
    expect(find.text('True black'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(c.read(themeSettingsProvider).amoled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the clock face row opens the face picker', (tester) async {
    phone(tester);
    final c = container();
    await tester.pumpWidget(app(c, start: '/profile/appearance'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.timer_outlined));
    await tester.pumpAndSettle();
    expect(find.text('clock face page'), findsOneWidget);
  });

  testWidgets('every You setting fits on about one phone screen', (
    tester,
  ) async {
    // The complaint this page answers: the settings ran on for screens.
    // With the profile card on top, the whole list should need well under
    // one more screen of scrolling at normal text size.
    phone(tester);
    final c = container(linked: true);
    await tester.pumpWidget(app(c, start: '/profile'));
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const ValueKey('profile-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(scrollable.position.maxScrollExtent, lessThan(915 * 0.75));
    for (final label in [
      'Achievements',
      'Leaderboard',
      'Study Groups',
      'Appearance',
      'Notifications',
      'Strict Mode',
      'App access',
      'Account',
      'About FocusForge',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the settings rows survive a narrow phone at large text', (
    tester,
  ) async {
    phone(tester, const Size(320, 640));
    final c = container();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: const AppearanceScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
