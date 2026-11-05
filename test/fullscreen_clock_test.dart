// The full-screen clock's controls and captions.
//
// WHAT INVARIANT: a tap anywhere starts or pauses the timer and never closes
// the screen; only the corner button closes it; the screen names a tagged
// subject, names nothing for an untagged block, and shows no time caption
// of its own under the clock.
//
// WHY IT MATTERS: a clock propped on a desk is reached for to pause it. When
// a tap closed the screen, the same reach threw the user out of the session.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/study.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/features/focus/fullscreen_clock.dart';

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

  /// Pushes the clock over a home page, the way the Focus tab opens it.
  Future<void> openClock(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showFullscreenClock(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(FullscreenClock), findsOneWidget);
  }

  testWidgets('a tap starts and pauses the timer without closing', (
    tester,
  ) async {
    final container = freshContainer();
    await openClock(tester, container);
    expect(find.text('Tap anywhere to start'), findsOneWidget);

    await tester.tapAt(const Offset(210, 820));
    await tester.pump(const Duration(seconds: 1));
    expect(container.read(timerProvider).running, isTrue);
    expect(find.byType(FullscreenClock), findsOneWidget);
    expect(find.text('Tap anywhere to pause'), findsOneWidget);

    await tester.tapAt(const Offset(210, 820));
    await tester.pump(const Duration(seconds: 1));
    expect(container.read(timerProvider).running, isFalse);
    expect(find.byType(FullscreenClock), findsOneWidget);
    expect(find.text('Tap anywhere to resume'), findsOneWidget);

    container.read(timerProvider.notifier).reset();
  });

  testWidgets('the corner button closes the clock', (tester) async {
    final container = freshContainer();
    await openClock(tester, container);

    await tester.tap(find.byIcon(Icons.close_fullscreen_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(FullscreenClock), findsNothing);
    expect(container.read(timerProvider).running, isFalse);
  });

  testWidgets('a tagged subject is named, with no time caption', (
    tester,
  ) async {
    final container = freshContainer();
    await container
        .read(subjectsProvider.notifier)
        .add(
          const Subject(
            id: 'math',
            name: 'Algebra',
            icon: Icons.book,
            color: Colors.blue,
          ),
        );
    container.read(timerProvider.notifier).setSubject('math');
    await openClock(tester, container);

    expect(find.text('Algebra'), findsOneWidget);
    expect(find.textContaining('Paused at'), findsNothing);
    expect(find.textContaining('left'), findsNothing);
  });

  testWidgets('an untagged block names no subject', (tester) async {
    final container = freshContainer();
    await openClock(tester, container);

    expect(find.text('25:00'), findsOneWidget);
    expect(find.text('Not tagged'), findsNothing);
    expect(find.textContaining('·'), findsNothing);
  });
}
