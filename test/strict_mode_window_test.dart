// Strict Mode's window: when it is open, and what can change while it is.
//
// WHAT INVARIANT: a window is open from the moment it is turned on until
// `enabledAt + duration`, and its length cannot be changed while it is open.
//
// WHY IT MATTERS: the end of the window is counted from its length. A length
// that could be dragged down mid-window would end the commitment on release,
// skipping the phrase and the cooldown the emergency unlock exists to ask for.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/shield.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/providers/usage_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/features/settings/strict_mode_screen.dart';

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
        appBlockingRunningProvider.overrideWith((ref) async => false),
        appBlockingPausedProvider.overrideWith((ref) async => false),
        overlayAccessProvider.overrideWith((ref) async => false),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('the window', () {
    final opened = DateTime(2026, 11, 5, 9);

    StrictModeConfig window({bool enabled = true}) => StrictModeConfig(
      enabled: enabled,
      enabledAtMillis: opened.millisecondsSinceEpoch,
      durationMinutes: 120,
    );

    test('is open from activation until its length has passed', () {
      expect(window().isActiveAt(opened), isTrue);
      expect(
        window().isActiveAt(opened.add(const Duration(minutes: 119))),
        isTrue,
      );
      expect(
        window().isActiveAt(opened.add(const Duration(minutes: 120))),
        isFalse,
      );
    });

    test('is closed when Strict Mode is off', () {
      expect(window(enabled: false).isActiveAt(opened), isFalse);
      expect(const StrictModeConfig().isActive, isFalse);
    });
  });

  group('the length', () {
    test('cannot be shortened while a window is open', () async {
      final container = freshContainer();
      final strict = container.read(strictModeProvider.notifier);
      // Opened 20 minutes ago: a 15-minute length would already be over.
      await strict.update(
        StrictModeConfig(
          enabled: true,
          enabledAtMillis: DateTime.now()
              .subtract(const Duration(minutes: 20))
              .millisecondsSinceEpoch,
          durationMinutes: 120,
        ),
      );

      await strict.setDuration(15);

      final config = container.read(strictModeProvider);
      expect(config.durationMinutes, 120);
      expect(config.isActive, isTrue);
    });

    test('can be changed while no window is open', () async {
      final container = freshContainer();
      await container.read(strictModeProvider.notifier).setDuration(45);
      expect(container.read(strictModeProvider).durationMinutes, 45);
    });

    testWidgets('slider is disabled while a window is open', (tester) async {
      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final container = freshContainer();
      await container
          .read(strictModeProvider.notifier)
          .update(
            StrictModeConfig(
              enabled: true,
              enabledAtMillis: DateTime.now().millisecondsSinceEpoch,
            ),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: StrictModeScreen()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.onChanged, isNull);
      expect(slider.onChangeEnd, isNull);
    });
  });
}
