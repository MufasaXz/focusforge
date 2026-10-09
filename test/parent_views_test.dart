// The parent's views of a child: their page, the Shield tab's child list, the
// dashboard card, and the role split on Parent control.
//
// WHAT INVARIANT: a read that fails draws a state instead of throwing out of
// the build; a parent's Shield tab lists the child's apps and writes blocks to
// the child's record; the dashboard leads with the selected child's day and
// week; the child's page shows the same two windows; and a student's Parent
// control page has no children section, because a student has no children to
// add.
//
// WHY IT MATTERS: a parent tapping a linked child used to get a blank screen.
// The cause was `AsyncValue.value`, which *throws* when a stream is in error —
// and the parent's reads are the ones that fail first, because they are the
// ones the security rules have to allow across two accounts. Every one of
// these screens reads somebody else's documents, so every one of them has to
// survive the read being refused.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/parent.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/parent_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/providers/usage_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/parent_service.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/features/dashboard/dashboard_screen.dart';
import 'package:focusforge/features/parent/child_dashboard_screen.dart';
import 'package:focusforge/features/parent/parent_control_screen.dart';
import 'package:focusforge/features/shield/shield_screen.dart';

/// A paired parent with two children, and switches for making reads fail.
class FakeParent implements ParentService {
  FakeParent({this.failing = false, this.childrenFailing = false});

  /// True while the child's documents answer with an error, which is what a
  /// denied read looks like from the app's side. The list of children is
  /// separate: the parent's own list is readable even when the child's tree
  /// is not.
  bool failing;

  /// True while the parent's own list of children cannot be read.
  bool childrenFailing;

  RemoteBlocks blocks = const RemoteBlocks(
    apps: [RemoteBlock(packageId: 'com.instagram.android', name: 'Instagram')],
  );

  /// What the Shield tab has written, so a test can assert the rule left the
  /// parent's device.
  final published = <RemoteBlocks>[];

  static const children = [
    ChildLink(uid: 'child-1', name: 'Ravi'),
    ChildLink(uid: 'child-2', name: 'Meera'),
  ];

  @override
  bool get available => true;

  @override
  String? get uid => 'parent-1';

  @override
  Stream<List<ChildLink>> watchChildren(String parentUid) => childrenFailing
      ? Stream.error(StateError('denied'))
      : Stream.value(children);

  @override
  Stream<GuardianLink?> watchGuardian(String uid) =>
      Stream.value(const GuardianLink(uid: 'parent-1', name: 'Amma'));

  @override
  Stream<ChildProgress?> watchProgress(String childUid) => failing
      ? Stream.error(StateError('denied'))
      : Stream.value(
          ChildProgress(
            minutes: 45,
            sessions: 2,
            goalMinutes: 120,
            streak: 3,
            topSubject: 'Maths',
            day: _todayKey(),
            updatedAt: DateTime.now(),
            weekMinutes: 300,
            weekSessions: 6,
            weekDays: const [30, 0, 60, 45, 90, 30, 45],
          ),
        );

  @override
  Stream<RemoteBlocks?> watchBlocks(String childUid) =>
      failing ? Stream.error(StateError('denied')) : Stream.value(blocks);

  @override
  Stream<List<CatalogApp>> watchCatalog(String childUid) => failing
      ? Stream.error(StateError('denied'))
      : Stream.value([
          const CatalogApp(
            packageId: 'com.instagram.android',
            name: 'Instagram',
          ),
          const CatalogApp(packageId: 'com.tiktok', name: 'TikTok'),
        ]);

  @override
  Future<PairCode> mintPairCode({required String childName}) async => PairCode(
    code: '123456',
    expiresAt: DateTime.now().add(PairCode.lifetime),
  );

  @override
  Future<ChildLink> linkChild(
    String code, {
    required String parentName,
  }) async => const ChildLink(uid: 'child-3', name: 'New');

  @override
  Future<void> unlink(String uid) async {}

  @override
  Future<void> publishProgress(String uid, ChildProgress progress) async {}

  @override
  Future<void> publishBlocks(String childUid, RemoteBlocks next) async {
    blocks = next;
    published.add(next);
  }

  @override
  Future<void> publishCode(String childUid, ParentCode? code) async {}

  @override
  Future<void> publishCatalog(String uid, List<CatalogApp> apps) async {}

  @override
  void dispose() {}
}

String _todayKey() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

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

  /// A tall phone viewport: these are long scroll views, and a card below the
  /// fold is not built at all.
  void useTallPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  ProviderContainer parentDevice(FakeParent parent) {
    final engine = RecordingShieldService();
    addTearDown(engine.dispose);
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        shieldServiceProvider.overrideWithValue(engine),
        parentServiceProvider.overrideWithValue(parent),
        installedAppsProvider.overrideWith((ref) async => const []),
        appUsageTodayProvider.overrideWith((ref) async => const {}),
        usageAccessProvider.overrideWith((ref) async => false),
        shieldEnabledProvider.overrideWith((ref) async => false),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(userProvider.notifier)
        .save(
          const UserProfile(
            uid: 'parent-1',
            displayName: 'Amma',
            persona: Persona.parent,
            onboardingComplete: true,
            isGuardian: true,
          ),
        );
    return container;
  }

  Widget wrap(
    ProviderContainer container,
    Widget child, {
    double textScale = 1,
  }) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(body: child),
    ),
  );

  /// Pumps past the stagger entrances and the tab fade.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  testWidgets('a refused read draws a state, not a blank screen', (
    tester,
  ) async {
    useTallPhone(tester);
    final parent = FakeParent(failing: true);
    final container = parentDevice(parent);

    await tester.pumpWidget(
      wrap(container, const ChildDashboardScreen(childUid: 'child-1')),
    );
    await settle(tester);

    expect(tester.takeException(), isNull);
    // The child is on the list even when their documents cannot be read.
    expect(find.text('Ravi'), findsOneWidget);
    expect(find.text('Can\'t read their summary'), findsOneWidget);
    expect(find.text('Can\'t read their block list'), findsOneWidget);
  });

  testWidgets(
    'a failed child-list read does not claim the child was unlinked',
    (tester) async {
      useTallPhone(tester);
      final parent = FakeParent(childrenFailing: true);
      final container = parentDevice(parent);

      await tester.pumpWidget(
        wrap(container, const ChildDashboardScreen(childUid: 'child-1')),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Connection could not be checked'), findsOneWidget);
    },
  );

  testWidgets('the child\'s page shows their day and their week', (
    tester,
  ) async {
    useTallPhone(tester);
    final container = parentDevice(FakeParent());

    await tester.pumpWidget(
      wrap(container, const ChildDashboardScreen(childUid: 'child-1')),
    );
    await settle(tester);

    expect(tester.takeException(), isNull);
    // `formatHoursShort`: 45 minutes is 0.8h, not a rounded-away "0h".
    expect(find.text('0.8h'), findsOneWidget);
    expect(find.text('of a 2h goal'), findsOneWidget);
    expect(find.text('2 sessions'), findsOneWidget);
    // The week: the strip and its headline, from the same summary.
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('5h · 6 sessions'), findsOneWidget);
    expect(find.text('A code is set for Ravi'), findsNothing);
    expect(find.text('Set a four-digit code'), findsOneWidget);
  });

  testWidgets('parent Shield fits a narrow phone with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = parentDevice(FakeParent());
    await tester.pumpWidget(
      wrap(container, const ShieldScreen(), textScale: 2),
    );
    await settle(tester);
    expect(find.text('Ravi'), findsOneWidget);
    expect(find.text('Meera'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the parent\'s shield lists the child\'s apps and blocks one', (
    tester,
  ) async {
    useTallPhone(tester);
    final parent = FakeParent();
    final container = parentDevice(parent);

    await tester.pumpWidget(wrap(container, const ShieldScreen()));
    await settle(tester);

    // Whose apps these are — the two children, as chips in the header — and
    // the rule already set for one of the apps.
    expect(find.text('Ravi'), findsOneWidget);
    expect(find.text('Meera'), findsOneWidget);
    expect(find.text('Their apps'), findsOneWidget);
    expect(find.text('Instagram'), findsOneWidget);
    expect(find.text('TikTok'), findsOneWidget);
    expect(find.text('Closes when opened'), findsOneWidget);

    // Blocking a second app writes the rule the child's phone picks up.
    final toggle = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Block TikTok',
    );
    expect(toggle, findsOneWidget);
    await tester.tap(toggle);
    await tester.pump();

    expect(parent.published, isNotEmpty);
    expect(
      parent.published.last.apps.map((a) => a.packageId),
      containsAll(['com.instagram.android', 'com.tiktok']),
    );
    // A block is meant to close the app, so it turns enforcement on with it.
    expect(parent.published.last.enforced, isTrue);
  });

  testWidgets('switching the child switches whose apps are listed', (
    tester,
  ) async {
    useTallPhone(tester);
    final container = parentDevice(FakeParent());

    await tester.pumpWidget(wrap(container, const ShieldScreen()));
    await settle(tester);

    expect(find.text('Instagram'), findsOneWidget);

    // The chips ride in the pinned header, one per child.
    await tester.tap(find.text('Meera'));
    await tester.pumpAndSettle();

    expect(container.read(activeChildProvider)?.uid, 'child-2');
    // The list is re-read for the new child; the fake serves the same one, so
    // the point is that the header moved with the choice.
    expect(find.text('Their apps'), findsOneWidget);
  });

  testWidgets('a student\'s Parent control page has no children section', (
    tester,
  ) async {
    useTallPhone(tester);
    final container = parentDevice(FakeParent());
    container
        .read(userProvider.notifier)
        .save(
          const UserProfile(
            uid: 'parent-1',
            displayName: 'Ravi',
            persona: Persona.student,
            onboardingComplete: true,
          ),
        );

    await tester.pumpWidget(wrap(container, const ParentControlScreen()));
    await settle(tester);

    // Section headings are drawn in small caps by `AppSection`.
    expect(find.text('This device'), findsOneWidget);
    expect(find.text('Children'), findsNothing);
    expect(find.text('Add a child'), findsNothing);
  });

  testWidgets('a parent\'s Parent control page has the children', (
    tester,
  ) async {
    useTallPhone(tester);
    final container = parentDevice(FakeParent());

    await tester.pumpWidget(wrap(container, const ParentControlScreen()));
    await settle(tester);

    expect(find.text('Children'), findsOneWidget);
    expect(find.text('Ravi'), findsOneWidget);
    expect(find.text('Meera'), findsOneWidget);
    // The code is set on the child's own page, not on this list.
    expect(find.text('Set a security code'), findsNothing);
    expect(find.text('This device'), findsNothing);
  });

  testWidgets('the dashboard leads with the selected child\'s study', (
    tester,
  ) async {
    useTallPhone(tester);
    final container = parentDevice(FakeParent());

    await tester.pumpWidget(wrap(container, const DashboardScreen()));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Their study'), findsOneWidget);
    expect(find.text('Ravi'), findsWidgets);
    expect(find.text('0.8h'), findsWidgets);
    expect(find.text('This week'), findsOneWidget);
  });
}
