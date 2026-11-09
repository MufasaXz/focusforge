// The ambient mixer: a track switched off, or stopped with Stop all, while
// it is still loading must not start playing once it loads.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import 'package:focusforge/core/data/seed.dart';
import 'package:focusforge/core/providers/audio_providers.dart';
import 'package:focusforge/core/services/audio_service.dart';

/// A player whose asset takes as long as [loaded] does to arrive.
class _SlowPlayer implements AudioPlayer {
  _SlowPlayer(this.loaded);
  final Completer<void> loaded;
  bool sounding = false;
  bool disposed = false;

  /// When set, stopping waits for it, like a slow platform teardown.
  Completer<void>? stopping;

  /// When set, play() is refused this way, later, as a platform would.
  Completer<void>? refusal;

  @override
  Future<Duration?> setAsset(
    String assetPath, {
    String? package,
    bool preload = true,
    Duration? initialPosition,
    dynamic tag,
  }) async {
    await loaded.future;
    return null;
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> play() async {
    sounding = true;
    if (refusal != null) {
      try {
        await refusal!.future;
      } catch (_) {
        sounding = false;
        rethrow;
      }
    }
  }

  @override
  Future<void> stop() async {
    await stopping?.future;
    sounding = false;
  }

  @override
  Future<void> dispose() async => disposed = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final rain = SeedData.ambient.firstWhere((s) => s.id == 'rain');
  final cafe = SeedData.ambient.firstWhere((s) => s.id != 'rain');
  late Completer<void> loaded;
  late List<_SlowPlayer> players;
  late AmbientMixer mixer;

  /// Set before a track starts to make its player slow to stop or refuse
  /// to play.
  Completer<void>? nextStopping;
  Completer<void>? nextPlaying;

  setUp(() {
    loaded = Completer<void>();
    players = [];
    nextStopping = null;
    nextPlaying = null;
    mixer = AmbientMixer(
      createPlayer: () {
        final player = _SlowPlayer(loaded)
          ..stopping = nextStopping
          ..refusal = nextPlaying;
        players.add(player);
        return player;
      },
    );
  });

  ProviderContainer scope() {
    final container = ProviderContainer(
      overrides: [ambientMixerProvider.overrideWithValue(mixer)],
    );
    addTearDown(container.dispose);
    // Listened, as the screen does, so the notifiers stay alive.
    container.listen(activeSoundsProvider, (_, _) {});
    container.listen(trackStatusProvider, (_, _) {});
    return container;
  }

  test('a track chosen while Stop all tears down keeps its controls', () async {
    final container = scope();
    final notifier = container.read(activeSoundsProvider.notifier);
    loaded.complete();
    nextStopping = Completer<void>();
    await notifier.toggle(rain);
    nextStopping = null;
    final stopping = notifier.clear();
    await notifier.toggle(cafe);
    players.first.stopping!.complete();
    await stopping;
    expect(container.read(activeSoundsProvider), {cafe.id});
    expect(container.read(trackStatusProvider), {cafe.id: TrackStatus.playing});
    expect(players.last.sounding, isTrue);
  });

  test('a track chosen again during Stop all plays once more', () async {
    final container = scope();
    final notifier = container.read(activeSoundsProvider.notifier);
    loaded.complete();
    nextStopping = Completer<void>();
    await notifier.toggle(rain);
    nextStopping = null;
    final stopping = notifier.clear();
    await notifier.toggle(rain);
    players.first.stopping!.complete();
    await stopping;
    expect(container.read(activeSoundsProvider), {rain.id});
    expect(players.first.disposed, isTrue);
    expect(players.last.sounding, isTrue);
  });

  test('a refused play is caught, shown, and can be retried', () async {
    final container = scope();
    final notifier = container.read(activeSoundsProvider.notifier);
    loaded.complete();
    nextPlaying = Completer<void>();
    await notifier.toggle(rain);
    expect(container.read(trackStatusProvider)[rain.id], TrackStatus.playing);
    // Left uncaught, this error would fail the test on its own.
    players.single.refusal!.completeError(StateError('platform refused'));
    await pumpEventQueue();
    expect(container.read(activeSoundsProvider), {rain.id});
    expect(container.read(trackStatusProvider)[rain.id], TrackStatus.failed);
    expect(players.single.disposed, isTrue);

    nextPlaying = null;
    // A tap on a failed track tries again rather than switching it off.
    expect(await notifier.toggle(rain), isTrue);
    expect(container.read(trackStatusProvider)[rain.id], TrackStatus.playing);
    expect(players.last.sounding, isTrue);
  });

  test('a stopped player\'s late refusal leaves a newer start alone', () async {
    final container = scope();
    final notifier = container.read(activeSoundsProvider.notifier);
    loaded.complete();
    nextPlaying = Completer<void>();
    await notifier.toggle(rain);
    final first = players.single;
    nextPlaying = null;
    await notifier.toggle(rain);
    await notifier.toggle(rain);
    first.refusal!.completeError(StateError('late refusal'));
    await pumpEventQueue();
    expect(container.read(trackStatusProvider)[rain.id], TrackStatus.playing);
    expect(players.last.sounding, isTrue);
  });

  test('switching a track off while it loads keeps it silent', () async {
    final on = mixer.toggle(rain);
    await mixer.toggle(rain);
    loaded.complete();
    await on;
    expect(mixer.active, isEmpty);
    expect(players.single.sounding, isFalse);
    expect(players.single.disposed, isTrue);
  });

  test('Stop all while a track loads keeps it silent', () async {
    final on = mixer.toggle(rain);
    await mixer.stopAll();
    loaded.complete();
    await on;
    expect(mixer.isPlaying, isFalse);
    expect(players.single.sounding, isFalse);
  });

  test('a track that loads normally plays', () async {
    final on = mixer.toggle(rain);
    loaded.complete();
    expect(await on, isTrue);
    expect(players.single.sounding, isTrue);
  });
}
