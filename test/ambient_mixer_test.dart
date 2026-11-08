// The ambient mixer: a track switched off, or stopped with Stop all, while
// it is still loading must not start playing once it loads.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import 'package:focusforge/core/data/seed.dart';
import 'package:focusforge/core/services/audio_service.dart';

/// A player whose asset takes as long as [loaded] does to arrive.
class _SlowPlayer implements AudioPlayer {
  _SlowPlayer(this.loaded);
  final Completer<void> loaded;
  bool sounding = false;
  bool disposed = false;

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
  Future<void> play() async => sounding = true;
  @override
  Future<void> stop() async => sounding = false;
  @override
  Future<void> dispose() async => disposed = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final rain = SeedData.ambient.firstWhere((s) => s.id == 'rain');
  late Completer<void> loaded;
  late List<_SlowPlayer> players;
  late AmbientMixer mixer;

  setUp(() {
    loaded = Completer<void>();
    players = [];
    mixer = AmbientMixer(
      createPlayer: () {
        final player = _SlowPlayer(loaded);
        players.add(player);
        return player;
      },
    );
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
