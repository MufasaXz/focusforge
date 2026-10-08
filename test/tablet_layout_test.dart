// Layout tests for the large-screen shapes: the shell's rail, the measure a
// pushed page keeps, and the badge grid's column count.
//
// WHAT INVARIANT: the app changes shape at the width it says it does — a
// tablet gets the rail and the phone gets the bar — and content that has no
// second column to fill the extra width is capped rather than stretched.
//
// WHY IT MATTERS: a wide layout is invisible to every other test in this
// suite, because the default test window is 800x600 and none of the widget
// tests resize it. A regression here would ship as "the tablet build looks
// wrong" and nothing would fail.
//
// The widths are the ones the constants name rather than round numbers: the
// test is about the rule, so it should break when the rule does.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/app.dart';
import 'package:focusforge/app/shell/app_shell.dart';
import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/providers/usage_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/features/profile/profile_screen.dart';
import 'package:focusforge/features/settings/achievements_screen.dart';
import 'package:focusforge/shared/widgets/app_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStore store;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
  });

  setUp(() async {
    await store.clearAll();
  });

  /// A container with the platform reads pinned.
  ///
  /// Same reasoning as the screen smoke tests: the usage providers and the
  /// shield engine both sit behind platform channels that never answer under
  /// the test binding, so a screen behind them would render a spinner for the
  /// rest of the test rather than the layout under test.
  ProviderContainer freshContainer() {
    final engine = RecordingShieldService();
    addTearDown(engine.dispose);

    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        shieldServiceProvider.overrideWithValue(engine),
        installedAppsProvider.overrideWith((ref) async => const []),
        appUsageTodayProvider.overrideWith((ref) async => const {}),
        usageAccessProvider.overrideWith((ref) async => false),
        shieldEnabledProvider.overrideWith((ref) async => false),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Resizes the test window and puts it back afterwards.
  void useViewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// A tablet in landscape: wider than [AppShell.railBreakpoint] and than
  /// [Layout.wide], so both the rail and the second columns are in play.
  void useTablet(WidgetTester tester) =>
      useViewport(tester, const Size(1280, 900));

  /// A phone: narrower than every breakpoint in the app.
  void usePhone(WidgetTester tester) =>
      useViewport(tester, const Size(420, 1600));

  /// Pumps past the stagger entrance and the branch fade.
  ///
  /// [Stagger] schedules its entrance with a bare `Future.delayed`, which
  /// schedules no frame — `pumpAndSettle` alone returns with the timer still
  /// pending and the framework then fails the test on teardown.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  /// Pumps the whole app with the user already through onboarding.
  ///
  /// The shell is only reachable through the router, and the router is only
  /// reachable with an onboarded profile — so the flag is flipped on the
  /// container rather than the shell being pumped on its own.
  ///
  /// The first-run tips are marked seen for the same reason a real user's
  /// second launch has them gone: their scrim covers the whole screen and
  /// absorbs pointers, so a tap meant for the rail would land on the tips.
  Future<void> pumpApp(WidgetTester tester, ProviderContainer container) async {
    await container.read(userProvider.notifier).completeOnboarding();
    await store.setBool(StoreKeys.coachSeen, true);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const FocusForgeApp(),
      ),
    );
    await settle(tester);
  }

  group('Shell', () {
    testWidgets('a tablet gets the rail, not the bar', (tester) async {
      useTablet(tester);
      await pumpApp(tester, freshContainer());

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(
        find.byType(NavigationBar),
        findsNothing,
        reason: 'a bar stretched across a tablet is a phone control on a desk',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a phone keeps the bar', (tester) async {
      usePhone(tester);
      await pumpApp(tester, freshContainer());

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        find.byType(NavigationRail),
        findsNothing,
        reason: 'the rail is for screens with room beside the content',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('every rail destination is reachable without sight', (
      tester,
    ) async {
      useTablet(tester);
      // Disposed inside the test rather than in a tear-down: the binding
      // verifies the handles are gone before tear-downs run.
      final handle = tester.ensureSemantics();
      await pumpApp(tester, freshContainer());

      final nodes = _semanticsNodes(tester)
          .map((n) => n.getSemanticsData())
          .toList();

      for (final label in const ['Home', 'Shield', 'Focus', 'You']) {
        // The label the rail gives is the destination name followed by its
        // position — "Home\nTab 1 of 4" — the same shape the bar produces.
        final named = nodes.where((d) => d.label.startsWith(label));
        expect(
          named,
          isNotEmpty,
          reason:
              'a destination a screen reader cannot name is a dead end; '
              'the tree held ${nodes.map((d) => d.label).toList()}',
        );
        expect(
          named.any((d) => d.hasAction(SemanticsAction.tap)),
          isTrue,
          reason: 'the named node has to be the one that can be operated',
        );
      }

      handle.dispose();
    });

    testWidgets('the rail switches tabs like the bar does', (tester) async {
      useTablet(tester);
      await pumpApp(tester, freshContainer());

      expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        0,
        reason: 'the app opens on the dashboard',
      );

      await tester.tap(find.text('You'));
      await settle(tester);

      expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        3,
      );
      expect(
        find.byType(ProfileScreen),
        findsOneWidget,
        reason: 'the branch the rail selected is the one on screen',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Content measure', () {
    /// A router with one route on it.
    ///
    /// Pushed pages read the router for their back button, so the page cannot
    /// be pumped on its own. The route is scaffolding; the page is the subject.
    Widget pageHarness(Widget Function() page) {
      final router = GoRouter(
        initialLocation: '/page',
        routes: [GoRoute(path: '/page', builder: (context, state) => page())],
      );
      addTearDown(router.dispose);
      return UncontrolledProviderScope(
        container: freshContainer(),
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      );
    }

    /// A page whose whole content is one full-width block.
    Widget pageWithBlock() => pageHarness(
      () => const AppPage(
        title: 'A pushed page',
        child: SizedBox(height: 40, width: double.infinity),
      ),
    );

    testWidgets('a pushed page is capped, and centred', (tester) async {
      useTablet(tester);
      await tester.pumpWidget(pageWithBlock());
      await tester.pumpAndSettle();

      final list = tester.getRect(find.byType(ListView));
      expect(list.width, Layout.readable);
      expect(
        list.center.dx,
        tester.getRect(find.byType(Scaffold)).center.dx,
        reason: 'a capped column sits in the middle, not against one edge',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a phone is left alone', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(pageWithBlock());
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.byType(ListView)).width,
        420,
        reason: 'the cap only binds when there is more room than content',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the badge grid spends the extra width on more columns', (
      tester,
    ) async {
      useTablet(tester);
      await tester.pumpWidget(pageHarness(() => const AchievementsScreen()));
      await tester.pumpAndSettle();

      expect(_columnsOf(tester), greaterThan(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the badge grid is three across on a phone', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(pageHarness(() => const AchievementsScreen()));
      await tester.pumpAndSettle();

      expect(_columnsOf(tester), 3);
      expect(tester.takeException(), isNull);
    });

    /// The profile tab as the shell actually gives it to a tablet: the branch
    /// body, capped at the shell's own maximum.
    Widget profileHarness() => pageHarness(
      () => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppShell.maxWideContentWidth,
          ),
          child: const ProfileScreen(),
        ),
      ),
    );

    testWidgets('the profile splits into two columns on a tablet', (
      tester,
    ) async {
      useTablet(tester);
      await tester.pumpWidget(profileHarness());
      await tester.pumpAndSettle();

      final goals = tester.getRect(find.text('Weekly study goals'));
      final appearance = tester.getRect(
        find.descendant(
          of: find.byType(SectionHeader),
          matching: find.text('Appearance'),
        ),
      );

      expect(
        appearance.left,
        greaterThan(goals.right),
        reason:
            'the settings column sits beside the identity column, not '
            'under it',
      );
      expect(
        appearance.top,
        lessThan(goals.top),
        reason: 'both columns start at the top of the page',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the profile stays one column on a phone', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(profileHarness());
      await tester.pumpAndSettle();

      final goals = tester.getRect(find.text('Weekly study goals'));
      final appearance = tester.getRect(
        find.descendant(
          of: find.byType(SectionHeader),
          matching: find.text('Appearance'),
        ),
      );

      expect(
        appearance.top,
        greaterThan(goals.bottom),
        reason: 'there is no room to put the two columns side by side',
      );
      expect(tester.takeException(), isNull);
    });
  });
}

/// Every node in the live semantics tree, root first.
///
/// Read from the tree rather than from a widget, because the question these
/// tests ask is what a screen reader is offered — and that is a property of
/// the node a widget ends up merged into, not of the widget itself.
List<SemanticsNode> _semanticsNodes(WidgetTester tester) {
  // The legacy single-view owner holds this tree. Its replacement,
  // `rootPipelineOwner`, is the root of a *tree* of owners and carries no
  // semantics of its own in a widget test, so reading through it finds
  // nothing.
  // ignore: deprecated_member_use
  final root = tester.binding.pipelineOwner.semanticsOwner?.rootSemanticsNode;
  if (root == null) return const [];

  final out = <SemanticsNode>[];
  void walk(SemanticsNode node) {
    out.add(node);
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(root);
  return out;
}

/// The column count the first badge grid is actually laid out with.
int _columnsOf(WidgetTester tester) {
  final grid = tester.widget<GridView>(find.byType(GridView).first);
  final delegate =
      grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
  return delegate.crossAxisCount;
}
