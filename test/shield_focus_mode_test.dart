// The focus-only rule: an app that is closed while a block runs and free the
// rest of the day.
//
// WHAT INVARIANT: the engine is told *when* the window closes, not that one is
// open — the same deadline trick Strict Mode uses — and that instant comes
// from the timer, so a paused clock is not focusing. The rule travels as its
// own mode rather than as a block, and the YouTube switches can be armed the
// same way.
//
// WHY IT MATTERS: this rule is the difference between "keep this shut while I
// work" and "keep this shut", and only the second one is recoverable by the
// user when they get it wrong. A window that stayed armed after the block
// ended would close an app the user believes they have released.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/core/models/shield.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/parent_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/shield_service.dart';

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

  test('a focus-only app travels as its own mode, with the deadline', () {
    final config = ShieldConfig(
      whitelist: const [
        WhitelistEntry(
          id: 'pkg:com.instagram.android',
          name: 'Instagram',
          icon: Icons.apps_rounded,
          color: Colors.pink,
          tier: WhitelistTier.focusOnly,
          packageId: 'com.instagram.android',
        ),
      ],
      youtube: const YoutubeRules(shorts: true, feed: true, focusOnly: true),
    );

    final payload = config.toChannelPayload();
    final app = (payload['apps'] as Map)['com.instagram.android'] as Map;
    expect(app['mode'], 'focus');
    expect((payload['youtube'] as Map)['focusOnly'], true);
    // Nothing is running, so there is no window to arm.
    expect(payload['focusUntil'], isNull);
  });

  test('the window is the running block and nothing else', () {
    final container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    final timer = container.read(timerProvider.notifier);

    expect(focusWindowEnd(container.read(timerProvider)), isNull);

    timer.start();
    final running = focusWindowEnd(container.read(timerProvider));
    expect(running, isNotNull);
    expect(running!.isAfter(DateTime.now()), isTrue);

    // Paused is not focusing: the rules lift the moment the clock stops.
    timer.pause();
    expect(focusWindowEnd(container.read(timerProvider)), isNull);

    // And a break is not focusing either.
    timer.start();
    timer.skip();
    expect(container.read(timerProvider).phase, TimerPhase.shortBreak);
    expect(focusWindowEnd(container.read(timerProvider)), isNull);
  });

  test('starting a block arms the engine and pausing lifts it', () {
    final engine = RecordingShieldService();
    addTearDown(engine.dispose);
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        shieldServiceProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(container.dispose);

    // Reading the bridge is the launch push: the engine is told where things
    // stand before anything has changed.
    container.read(shieldSyncBridgeProvider);
    expect(engine.lastApplied, isNotNull);
    expect(engine.lastApplied!.focusUntil, isNull);

    container.read(timerProvider.notifier).start();
    expect(engine.lastApplied!.focusUntil, isNotNull);

    container.read(timerProvider.notifier).pause();
    expect(engine.lastApplied!.focusUntil, isNull);
  });
}
