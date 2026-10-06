// The focus clock: the four faces it can be drawn in, and the preference that
// chooses between them.
//
// WHAT INVARIANT: every face renders the same value, none of them throws at
// any size, and the chosen face is the one a later launch reads back.
//
// WHY IT MATTERS: two of the four faces paint their figures rather than
// laying out text, so a mistake in them is invisible to the model tests and to
// `find.text` — it shows up as a blank rectangle on the timer, or as a layout
// exception only when the timer is at 100 minutes. The preference is read
// before the first frame, so an unreadable stored value has to land on the
// shipped face rather than on nothing.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/features/focus/widgets/clock_faces.dart';

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

  Widget wrap(Widget child, {ProviderContainer? container}) {
    final scope = container ?? ProviderContainer();
    addTearDown(scope.dispose);
    return UncontrolledProviderScope(
      container: scope,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  group('ClockFace', () {
    test('an unknown or missing name falls back to the shipped face', () {
      expect(ClockFace.fromName(null), ClockFace.digits);
      expect(ClockFace.fromName(''), ClockFace.digits);
      expect(ClockFace.fromName('sundial'), ClockFace.digits);
    });

    test('round-trips by name', () {
      for (final face in ClockFace.values) {
        expect(ClockFace.fromName(face.name), face);
      }
      expect(
        ClockFace.values.map((f) => f.name).toSet(),
        hasLength(ClockFace.values.length),
        reason: 'stored by name, so the names have to be distinct',
      );
    });
  });

  group('ClockDisplay', () {
    const remaining = Duration(minutes: 24, seconds: 51);

    testWidgets('the faces that draw text show every figure', (tester) async {
      for (final face in [ClockFace.digits, ClockFace.minimal]) {
        await tester.pumpWidget(
          wrap(
            ClockDisplay(
              remaining: remaining,
              face: face,
              accent: Colors.orange,
              height: 48,
              progress: 0.4,
            ),
          ),
        );
        await tester.pumpAndSettle();
        // The rolling text is one Text per glyph, not one per string — that is
        // what lets a single figure animate on its own.
        for (final glyph in ['2', '4', '5', '1']) {
          expect(
            find.text(glyph),
            findsWidgets,
            reason: '${face.name} renders the engine\'s time',
          );
        }
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('the flip board holds one card per figure', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ClockDisplay(
            remaining: remaining,
            face: ClockFace.flip,
            accent: Colors.orange,
            height: 48,
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final glyph in ['2', '4', '5', '1']) {
        expect(
          find.text(glyph),
          findsWidgets,
          reason: 'each figure is its own card',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a figure that changes flips and lands on the new one', (
      tester,
    ) async {
      Widget board(Duration d) => wrap(
        ClockDisplay(
          remaining: d,
          face: ClockFace.flip,
          accent: Colors.orange,
          height: 48,
        ),
      );

      await tester.pumpWidget(board(const Duration(minutes: 24, seconds: 51)));
      await tester.pumpAndSettle();
      expect(find.text('9'), findsNothing);

      // One second later the tens-of-seconds card goes 5 → 9.
      await tester.pumpWidget(board(const Duration(minutes: 24, seconds: 59)));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.takeException(),
        isNull,
        reason: 'the flip runs mid-flight without a layout error',
      );
      await tester.pumpAndSettle();
      expect(find.text('9'), findsWidgets);
    });

    testWidgets('every face lays out at a small and a large size', (
      tester,
    ) async {
      for (final face in ClockFace.values) {
        for (final height in [26.0, 96.0]) {
          await tester.pumpWidget(
            wrap(
              ClockDisplay(
                remaining: const Duration(hours: 1, minutes: 5, seconds: 9),
                face: face,
                accent: Colors.orange,
                height: height,
                progress: 0.5,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${face.name} at ${height.toInt()}dp',
          );
        }
      }
    });
  });

  group('the clock face preference', () {
    testWidgets('a chosen face is written and read back', (tester) async {
      final container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      expect(
        container.read(clockFaceProvider),
        ClockFace.digits,
        reason: 'a cold install gets the face the app shipped with',
      );

      await container.read(clockFaceProvider.notifier).set(ClockFace.flip);
      expect(container.read(clockFaceProvider), ClockFace.flip);
      expect(store.getString(StoreKeys.clockFace), 'flip');

      // A later launch reads the stored name; an unreadable one falls back.
      final reopened = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(reopened.dispose);
      reopened
          .read(clockFaceProvider.notifier)
          .hydrate(store.getString(StoreKeys.clockFace));
      expect(reopened.read(clockFaceProvider), ClockFace.flip);

      reopened.read(clockFaceProvider.notifier).hydrate('sundial');
      expect(reopened.read(clockFaceProvider), ClockFace.digits);
    });
  });
}
