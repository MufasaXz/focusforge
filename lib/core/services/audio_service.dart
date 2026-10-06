import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../models/study.dart';

/// Layers several looping ambience tracks on top of each other.
///
/// One [AudioPlayer] per active sound. Every track loops forever and carries
/// its own volume, so "rain at 40% under a café at 25%" is just two players
/// running at once — the platform mixes them for free.
///
/// Failures are swallowed on purpose. Audio is an enhancement to a focus
/// session, never a precondition for one: if a codec is missing, or the
/// browser blocks autoplay until the first gesture, the timer must keep
/// running and the UI must not throw.
class AmbientMixer {
  /// Where a track starts before anyone has moved its slider.
  ///
  /// Public because the mixer screen draws the same value: a slider that
  /// showed 50% while the player was at some other default would be the one
  /// control in the app that lies.
  static const double defaultVolume = 0.5;

  final Map<String, AudioPlayer> _players = {};
  final Map<String, double> _volumes = {};
  final Map<String, String> _assets = {};

  /// Ids that should be playing. Kept separate from [_players] so a track that
  /// failed to load is not silently dropped from the user's selection.
  final Set<String> _active = {};

  bool _disposed = false;

  Set<String> get active => Set.unmodifiable(_active);
  bool get isPlaying => _active.isNotEmpty;

  double volumeOf(String id) => _volumes[id] ?? defaultVolume;

  /// Restores a previously persisted selection without starting playback —
  /// used on launch so the tiles come back lit.
  void restore({
    required Set<String> active,
    required Map<String, double> volumes,
  }) {
    _active
      ..clear()
      ..addAll(active);
    _volumes
      ..clear()
      ..addAll(volumes);
  }

  /// Starts or stops one track. Returns the resulting on/off state.
  Future<bool> toggle(AmbientSound sound) async {
    if (_disposed) return false;
    if (_active.contains(sound.id)) {
      await stop(sound.id);
      return false;
    }
    _active.add(sound.id);
    _assets[sound.id] = sound.asset;
    await _start(sound);
    return true;
  }

  Future<void> _start(AmbientSound sound) async {
    try {
      var player = _players[sound.id];
      if (player == null) {
        player = AudioPlayer();
        await player.setAsset(sound.asset);
        await player.setLoopMode(LoopMode.one);
        _players[sound.id] = player;
      }
      await player.setVolume(volumeOf(sound.id));
      unawaited(player.play());
    } catch (_) {
      // Codec missing, asset absent, or autoplay blocked. Leave the tile lit
      // and the timer running; the next gesture retries naturally.
    }
  }

  Future<void> stop(String id) async {
    _active.remove(id);
    final player = _players.remove(id);
    if (player == null) return;
    try {
      await player.stop();
      await player.dispose();
    } catch (_) {
      // Already gone.
    }
  }

  Future<void> stopAll() async {
    for (final id in _players.keys.toList()) {
      await stop(id);
    }
    _active.clear();
  }

  /// Live volume change — cheap enough to call on every slider drag frame.
  Future<void> setVolume(String id, double value) async {
    final v = value.clamp(0.0, 1.0);
    _volumes[id] = v;
    final player = _players[id];
    if (player == null) return;
    try {
      await player.setVolume(v);
    } catch (_) {
      // Ignore.
    }
  }

  /// Re-applies the persisted selection, e.g. after a hot restart.
  Future<void> resumeAll(List<AmbientSound> catalogue) async {
    for (final id in _active.toList()) {
      final sound = catalogue.where((s) => s.id == id).firstOrNull;
      if (sound != null) await _start(sound);
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await stopAll();
    _players.clear();
  }
}
