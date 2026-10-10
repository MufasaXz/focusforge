// The focus clock: the five faces it can be drawn in, and the preference that
// chooses between them.
//
// WHAT INVARIANT: every face renders the same value, none of them throws at
// any size, and the chosen face is the one a later launch reads back.
//
// WHY IT MATTERS: three of the five faces paint their figures rather than
// laying out text, so a mistake in them is invisible to the model tests and to
// `find.text` — it shows up as a blank rectangle on the timer, or as a layout
// exception only when the timer is at 100 minutes. The flip board in
// particular draws two halves of one card, and where those halves land is
// geometry no other test can see. The preference is read before the first
// frame, so an unreadable stored value has to land on the shipped face rather
// than on nothing.

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/utils/format.dart';
import 'package:focusforge/features/focus/widgets/clock_faces.dart';
import 'package:focusforge/features/settings/clock_face_screen.dart';

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
      expect(ClockFace.fromName(null), ClockFace.retro);
      expect(ClockFace.fromName(''), ClockFace.retro);
      expect(ClockFace.fromName('sundial'), ClockFace.retro);
      expect(
        ClockFace.fromName('digits'),
        ClockFace.retro,
        reason: 'a face that has been retired reads as the fallback',
      );
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

    testWidgets(
      'retro displays the engine time and current phase with bundled serif figures',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            const ClockDisplay(
              remaining: remaining,
              face: ClockFace.retro,
              accent: Colors.orange,
              height: 280,
              phaseLabel: 'BREAK',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('24:51'), findsOneWidget);
        expect(find.text('BREAK'), findsOneWidget);
        expect(find.text('REMAINING'), findsNothing);
        final text = tester.widget<Text>(find.text('24:51'));
        expect(text.style?.fontFamily, 'FocusDial');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('the faces that draw text show every figure', (tester) async {
      for (final face in [ClockFace.minimal, ClockFace.neon]) {
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

    testWidgets('the flip board stacks its halves instead of piling them up', (
      tester,
    ) async {
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

      // Each half is a clip the size of half a card. A Stack aligns whatever
      // is not positioned to its top-left, so if the halves are not anchored
      // both land in the top half and the card's bottom stays blank — which
      // is exactly what the eye reads as "the flip clock is broken".
      final clips = <Rect>[
        for (final box in tester.renderObjectList<RenderBox>(
          find.byType(ClipRRect),
        ))
          box.localToGlobal(Offset.zero) & box.size,
      ];
      expect(clips, isNotEmpty);

      // Grouped by column: one card is two clips, one above the other.
      final byColumn = <double, List<Rect>>{};
      for (final rect in clips) {
        byColumn.putIfAbsent(rect.left, () => []).add(rect);
      }

      for (final column in byColumn.values) {
        // A card at rest draws three: the top half, the bottom half, and the
        // half that does the flipping, parked exactly on top of the bottom
        // one so it can turn from there. Two distinct bands, then.
        final bands = column.toSet().toList()
          ..sort((a, b) => a.top.compareTo(b.top));
        expect(bands, hasLength(2), reason: 'a card is a top and a bottom');
        final card = bands.first.expandToInclude(bands.last);
        expect(
          bands.first.bottom,
          closeTo(card.center.dy, 0.5),
          reason: 'the top half has to stop at the hinge',
        );
        expect(
          bands.last.top,
          closeTo(card.center.dy, 0.5),
          reason: 'the bottom half has to start at the hinge',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('each half is a window on one full-height figure', (
      tester,
    ) async {
      const size = 48.0;
      await tester.pumpWidget(
        wrap(
          const ClockDisplay(
            remaining: remaining,
            face: ClockFace.flip,
            accent: Colors.orange,
            height: size,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A card is 0.98 of the face height, so its halves are windows 0.49
      // tall. The figure inside has to be laid out at the card's own height
      // and centred on the hinge — that is what makes each window show its
      // own half of the figure. Laid out at the window's height instead,
      // every window holds a complete figure and the card reads as two
      // stacked clocks, which is exactly the doubling the eye catches.
      final display = tester.getRect(find.byType(ClockDisplay));
      final hinge = display.center.dy;
      final card = size * 0.98;

      final glyphs = tester.renderObjectList<RenderBox>(find.text('2'));
      expect(glyphs, isNotEmpty, reason: 'the card draws its figure');
      for (final glyph in glyphs) {
        final rect = glyph.localToGlobal(Offset.zero) & glyph.size;
        expect(
          rect.center.dy,
          closeTo(hinge, 1.0),
          reason: 'the figure sits on the hinge, not on one half of it',
        );
      }

      final windows = tester.renderObjectList<RenderBox>(
        find.byType(ClipRRect),
      );
      expect(windows, isNotEmpty);
      for (final window in windows) {
        expect(
          window.size.height,
          closeTo(card / 2, 0.5),
          reason: 'a window is half a card',
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

    testWidgets('the analog face is a square dial, not a row of figures', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const ClockDisplay(
            remaining: Duration(minutes: 25),
            face: ClockFace.analog,
            accent: Colors.orange,
            height: 48,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final paint = tester.widget<CustomPaint>(
        find
            .descendant(
              of: find.byType(ClockDisplay),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      final size = paint.size;
      expect(size.width, size.height, reason: 'a dial is round');
      expect(
        size.width,
        greaterThan(48),
        reason: 'the hands need more room than the figures did',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the clock face page', () {
    /// The page reads the router for its back button, so it cannot be pumped
    /// on its own — the route is scaffolding and the page is the subject.
    Widget page(ProviderContainer container) {
      final router = GoRouter(
        initialLocation: '/clock',
        routes: [
          GoRoute(
            path: '/clock',
            builder: (context, state) => const ClockFaceScreen(),
          ),
        ],
      );
      addTearDown(router.dispose);
      return UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      );
    }

    ProviderContainer container() {
      final scope = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(scope.dispose);
      return scope;
    }

    testWidgets('every face is offered, and the running one is marked', (
      tester,
    ) async {
      await tester.pumpWidget(page(container()));
      await tester.pumpAndSettle();

      for (final face in ClockFace.values) {
        expect(
          find.text(face.label),
          findsOneWidget,
          reason: 'a face that is not on the page cannot be chosen',
        );
      }
      // The shipped face is the one the timer is wearing. Asked of the
      // semantics rather than of the check mark: the check is built into every
      // row and scaled away, so its presence finds all five.
      final chosen = [
        for (final face in ClockFace.values)
          if (tester
                  .getSemantics(find.text(face.label))
                  .getSemanticsData()
                  .flagsCollection
                  .isSelected ==
              Tristate.isTrue)
            face,
      ];
      expect(
        chosen,
        [ClockFace.retro],
        reason:
            'exactly one face is the current one, and a cold install '
            'wears the shipped one',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a face selects it and writes the choice', (
      tester,
    ) async {
      final scope = container();
      await tester.pumpWidget(page(scope));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text(ClockFace.segments.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ClockFace.segments.label));
      await tester.pumpAndSettle();

      expect(scope.read(clockFaceProvider), ClockFace.segments);
      expect(
        store.getString(StoreKeys.clockFace),
        'segments',
        reason: 'the choice has to survive the app being closed',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a preview draws the timer\'s own value, not a sample', (
      tester,
    ) async {
      final scope = container();
      await tester.pumpWidget(page(scope));
      await tester.pumpAndSettle();

      final timer = scope.read(timerProvider);
      final glyphs = formatClock(timer.remaining)
          .replaceAll(':', '')
          .split('')
          .toSet();

      for (final glyph in glyphs) {
        expect(
          find.text(glyph),
          findsWidgets,
          reason: 'the previews have to show what the timer would show',
        );
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
        ClockFace.retro,
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
      expect(reopened.read(clockFaceProvider), ClockFace.retro);
    });
  });
}
