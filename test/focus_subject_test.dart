// The focus tab's subject picker (lib/features/focus/subject_picker.dart) and
// the sheet that adds a subject (lib/features/focus/subject_sheet.dart).
//
// WHAT INVARIANT: a subject created from the focus tab is written to the same
// store the onboarding picker writes to, is tagged onto the timer in the same
// breath, and is refused by the same naming rules — including a name the
// onboarding picker is already offering.
//
// WHY IT MATTERS: this is a second door into the subject store. A rule that
// lived only in the onboarding step would let this one create a subject whose
// id collides with an existing one, and `remove`/`setWeeklyTarget` would then
// hit both at once. The tagging half is just as load-bearing: a subject added
// mid-session that arrives unselected would log the block that prompted it
// against nothing.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/study.dart';
import 'package:focusforge/core/models/subject_naming.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/features/focus/subject_picker.dart';

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
          theme: AppTheme.light(),
          home: Scaffold(body: child),
        ),
      );

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
  }

  Future<void> addSubject(WidgetTester tester, String name) async {
    await tester.tap(find.text('New'));
    await settle(tester);
    expect(find.text('New subject'), findsOneWidget, reason: 'the sheet opens');
    await tester.enterText(find.byType(TextField), name);
    await tester.pump();
    await tester.tap(find.text('Add subject'));
    await settle(tester);
  }

  group('SubjectNaming', () {
    test('names that reduce to nothing still get distinct ids', () {
      expect(SubjectNaming.slug('Math'), 'math');
      expect(SubjectNaming.slug('  Deep  Work '), 'deep-work');
      expect(SubjectNaming.slug('!!!'), isNot(SubjectNaming.slug('???')));
      expect(SubjectNaming.slug('!!!'), isNotEmpty);
    });

    test('a name already in the store is refused, whatever its case', () {
      const existing = [
        Subject(
          id: 'math',
          name: 'Math',
          icon: Icons.square_foot_rounded,
          color: Colors.blue,
        ),
      ];
      expect(
        SubjectNaming.reasonUnavailable('math', existing: existing),
        contains('already on your list'),
      );
      expect(
        SubjectNaming.reasonUnavailable('Physics', existing: existing),
        isNull,
      );
    });

    test('a name only reserved by the picker is refused too', () {
      expect(
        SubjectNaming.reasonUnavailable(
          'Chemistry',
          existing: const [],
          reserved: const ['Chemistry'],
        ),
        contains('already on your list'),
      );
      // Different name, same id — the collision that makes `remove` ambiguous.
      expect(
        SubjectNaming.reasonUnavailable(
          'Math-2',
          existing: const [
            Subject(
              id: 'math-2',
              name: 'Math 2',
              icon: Icons.square_foot_rounded,
              color: Colors.blue,
            ),
          ],
        ),
        contains('too similar'),
      );
    });
  });

  group('SubjectPicker', () {
    testWidgets('the row lists every subject and the chip that adds one', (
      tester,
    ) async {
      final container = freshContainer();
      await tester.pumpWidget(
        wrap(container, const SubjectPicker(accent: Colors.blue)),
      );
      await settle(tester);

      expect(find.text('Studying'), findsOneWidget);
      expect(
        find.text('Not tagged'),
        findsOneWidget,
        reason: 'nothing is tagged until the user picks something',
      );
      for (final subject in container.read(subjectsProvider)) {
        expect(
          find.text(subject.name),
          findsWidgets,
          reason: '${subject.name} is on the device and has to be offered',
        );
      }
      expect(find.text('New'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a subject added here is stored and tagged onto the timer', (
      tester,
    ) async {
      final container = freshContainer();
      await tester.pumpWidget(
        wrap(container, const SubjectPicker(accent: Colors.blue)),
      );
      await settle(tester);

      await addSubject(tester, 'Thesis');

      final added = container
          .read(subjectsProvider)
          .where((s) => s.name == 'Thesis')
          .toList();
      expect(added, hasLength(1));
      expect(added.single.id, 'thesis');
      expect(
        added.single.weekTarget,
        greaterThan(0),
        reason: 'a subject with no target would be the only one without a goal',
      );
      expect(
        container.read(timerProvider).subjectId,
        'thesis',
        reason: 'the session that prompted the add is logged against it',
      );
      expect(find.text('Thesis'), findsWidgets);
      expect(find.text('Not tagged'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a name the store already holds is refused in place', (
      tester,
    ) async {
      final container = freshContainer();
      await tester.pumpWidget(
        wrap(container, const SubjectPicker(accent: Colors.blue)),
      );
      await settle(tester);

      final before = container.read(subjectsProvider).length;
      await addSubject(tester, 'Math');

      expect(
        find.text('New subject'),
        findsOneWidget,
        reason: 'the sheet stays open so the name can be corrected',
      );
      expect(find.textContaining('already on your list'), findsOneWidget);
      expect(container.read(subjectsProvider), hasLength(before));
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping the tagged subject again clears the tag', (
      tester,
    ) async {
      final container = freshContainer();
      await tester.pumpWidget(
        wrap(container, const SubjectPicker(accent: Colors.blue)),
      );
      await settle(tester);

      // The chip and the "Studying" label both read "Math", so the tap has to
      // name the one it means: the chip in the row.
      final chip = find.descendant(
        of: find.byType(ListView),
        matching: find.text('Math'),
      );
      await tester.tap(chip);
      await settle(tester);
      expect(container.read(timerProvider).subjectId, 'math');

      await tester.tap(chip);
      await settle(tester);
      expect(
        container.read(timerProvider).subjectId,
        isNull,
        reason: 'the same chip that selects it lets it go',
      );
      expect(tester.takeException(), isNull);
    });
  });
}
