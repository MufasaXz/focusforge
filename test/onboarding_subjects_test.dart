// Widget tests for the onboarding Subjects step
// (lib/features/onboarding/subjects_step.dart): which names may become
// subjects, and how a subject survives the step being disposed and rebuilt.
//
// WHAT INVARIANT: the picker's names and the store's ids are each unique, and
// a rejected name never reaches the store.
//
// WHY IT MATTERS: this is the only screen that creates subjects, and the
// store it writes is what the dashboard and the focus timer read. Two names
// that reduce to one slug id make `remove` and `setWeeklyTarget` hit several
// subjects at once; a rejected name that still reaches the store renders a
// chip the picker cannot rebuild from its template list. Both classes of bug
// are silent at runtime, so they are pinned here.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/glass_theme.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/features/onboarding/subjects_step.dart';
import 'package:focusforge/shared/widgets/glass_surface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStore store;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
  });

  ProviderContainer freshContainer() {
    final container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    return container;
  }

  Widget wrap(ProviderContainer container, Widget child) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: GlassTheme.light(),
          home: Scaffold(body: child),
        ),
      );

  /// Pumps past the stagger entrance, then settles the animations.
  ///
  /// [Stagger] schedules its entrance with a bare `Future.delayed`
  /// (lib/shared/widgets/stagger.dart:38). That timer schedules no frame, so
  /// `pumpAndSettle` alone returns with it still pending and the framework
  /// then fails the test with "A Timer is still pending even after the widget
  /// tree was disposed". Advancing past `Stagger.maxDelay` (420 ms) lets every
  /// scheduled entrance run before the test ends.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('Add custom'));
    await settle(tester);
    expect(find.text('Add a subject'), findsOneWidget, reason: 'dialog opens');
  }

  Future<void> submitName(WidgetTester tester, String name) async {
    await tester.enterText(find.byType(TextField), name);
    await tester.pump();
    await tester.tap(find.text('Add subject'));
    await settle(tester);
  }

  Future<void> addCustom(WidgetTester tester, String name) async {
    await openDialog(tester);
    await submitName(tester, name);
  }

  group('duplicate names are rejected inline', () {
    for (final (description, name) in <(String, String)>[
      ('an exact template name', 'Math'),
      ('a template name in another case', 'math'),
      ('a template name padded with whitespace', '  Math  '),
    ]) {
      testWidgets('$description is rejected without a store write', (
        tester,
      ) async {
        final container = freshContainer();
        await tester.pumpWidget(wrap(container, SubjectsStep(onNext: () {})));
        await settle(tester);

        final before = container.read(subjectsProvider);
        await addCustom(tester, name);

        expect(
          find.text('Add a subject'),
          findsOneWidget,
          reason: 'the dialog stays open so the user can correct the name',
        );
        expect(
          find.textContaining('already on your list'),
          findsOneWidget,
          reason: 'the reason is shown next to the field',
        );
        final after = container.read(subjectsProvider);
        expect(
          after.length,
          before.length,
          reason: 'a rejected name must not reach the store',
        );
        expect(
          after.where((s) => s.id == 'math').length,
          1,
          reason: 'the seed entry is untouched, with no shadow duplicate',
        );
      });
    }
  });

  group('slug collisions are rejected', () {
    testWidgets(
      'two names that reduce to one id — "Math 2" then "Math-2" — the second '
      'is rejected',
      (tester) async {
        final container = freshContainer();
        await tester.pumpWidget(wrap(container, SubjectsStep(onNext: () {})));
        await settle(tester);

        await addCustom(tester, 'Math 2');
        expect(
          container.read(subjectsProvider).where((s) => s.id == 'math-2'),
          hasLength(1),
        );

        await addCustom(tester, 'Math-2');

        expect(find.text('Add a subject'), findsOneWidget);
        expect(find.textContaining('too similar'), findsOneWidget);
        final stored = container.read(subjectsProvider);
        expect(
          stored.where((s) => s.id == 'math-2'),
          hasLength(1),
          reason: 'the colliding id must not be written twice',
        );
        expect(
          stored.where((s) => s.name == 'Math-2'),
          isEmpty,
          reason: 'the rejected name must not be stored under the taken id',
        );
      },
    );

    testWidgets(
      'punctuation-only names get distinct non-empty ids and are removed '
      'independently',
      (tester) async {
        final container = freshContainer();
        await tester.pumpWidget(wrap(container, SubjectsStep(onNext: () {})));
        await settle(tester);

        await addCustom(tester, '!!!');
        await addCustom(tester, '???');

        final stored = container
            .read(subjectsProvider)
            .where((s) => s.name == '!!!' || s.name == '???')
            .toList();
        expect(stored, hasLength(2), reason: 'both names are addable');
        expect(
          stored.map((s) => s.id).toSet(),
          hasLength(2),
          reason: 'names with no ASCII alphanumerics must not collapse onto '
              'one shared empty id',
        );
        expect(stored.every((s) => s.id.isNotEmpty), isTrue);

        // With a shared id, removing one would silently remove both.
        await tester.tap(find.widgetWithText(GlassPill, '!!!'));
        await settle(tester);
        final remaining = container.read(subjectsProvider);
        expect(remaining.any((s) => s.name == '!!!'), isFalse);
        expect(remaining.any((s) => s.name == '???'), isTrue);
      },
    );
  });

  group('custom subject lifecycle', () {
    testWidgets('a custom subject survives a step rebuild without duplicating', (
      tester,
    ) async {
      final container = freshContainer();
      await tester.pumpWidget(wrap(container, SubjectsStep(onNext: () {})));
      await settle(tester);

      await addCustom(tester, 'Thesis');

      expect(
        find.text('Add a subject'),
        findsNothing,
        reason: 'the dialog closes after a valid add',
      );
      final added = container
          .read(subjectsProvider)
          .where((s) => s.name == 'Thesis');
      expect(added, hasLength(1));
      expect(added.single.id, 'thesis');
      expect(find.text('Thesis'), findsWidgets, reason: 'the chip is rendered');

      // The onboarding PageView disposes an off-screen step and rebuilds it
      // fresh; the store, not the widget, is the source of truth.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(wrap(container, SubjectsStep(onNext: () {})));
      await settle(tester);

      expect(
        find.text('Thesis'),
        findsWidgets,
        reason: 'the custom chip is rebuilt from the store, not lost',
      );
      expect(
        container.read(subjectsProvider).where((s) => s.id == 'thesis'),
        hasLength(1),
        reason: 'the rebuild must not write a duplicate',
      );
    });
  });

  group('toggle and commit', () {
    testWidgets(
      'deselect removes, reselect restores, and Continue commits unique ids',
      (tester) async {
        final container = freshContainer();
        var nextCalls = 0;
        await tester.pumpWidget(
          wrap(container, SubjectsStep(onNext: () => nextCalls++)),
        );
        await settle(tester);

        expect(
          container.read(subjectsProvider).where((s) => s.id == 'physics'),
          hasLength(1),
          reason: 'a seeded subject matching a template starts selected',
        );

        await tester.tap(find.widgetWithText(GlassPill, 'Physics'));
        await settle(tester);
        expect(
          container.read(subjectsProvider).where((s) => s.id == 'physics'),
          isEmpty,
          reason: 'deselecting a subject removes it from the store',
        );

        await tester.tap(find.widgetWithText(GlassPill, 'Physics'));
        await settle(tester);
        expect(
          container.read(subjectsProvider).where((s) => s.id == 'physics'),
          hasLength(1),
          reason: 'reselecting re-adds exactly one, with no duplicate',
        );

        await tester.tap(find.textContaining('Continue with'));
        await settle(tester);
        expect(nextCalls, 1, reason: 'the primary action advances the flow');

        final subjects = container.read(subjectsProvider);
        final ids = subjects.map((s) => s.id).toList();
        expect(
          ids.toSet(),
          hasLength(ids.length),
          reason: 'commit must not write duplicate ids',
        );
        expect(
          subjects.every((s) => s.weekTarget > 0),
          isTrue,
          reason: 'commit persists a weekly target for every selected subject',
        );
      },
    );
  });
}
