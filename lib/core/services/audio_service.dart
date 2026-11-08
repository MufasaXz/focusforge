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
  AmbientMixer({AudioPlayer Function()? createPlayer})
    : _createPlayer = createPlayer ?? AudioPlayer.new;

  final AudioPlayer Function() _createPlayer;

  /// Where a track starts before anyone has moved its slider.
  ///
  /// Public because the mixer screen draws the same value: a slider that
  /// showed 50% while the player was at some other default would be the one
  /// control in the app that lies.
  static const double defaultVolume = 0.5;

  final Map<String, AudioPlayer> _players = {};
  final Map<String, double> _volumes = {};
  final Map<String, String> _assets = {};

  /// The latest start of each track. A track switched off, or switched on
  /// again, while an earlier start was still loading makes that start stale.
  final Map<String, int> _starts = {};

  /// Ids that should be playing. Kept separate from [_players] so a track that
  /// failed to load is not silently dropped from the user's selection.
  final Set<String> _active = {};

  bool _disposed = false;

  Set<String> get active => Set.unmodifiable(_active);
  bool get isPlaying => _active.isNotEmpty;

  double volumeOf(String id) => _volumes[id] ?? defaultVolume;

  /// Brings back the volumes the user chose, on launch.
  ///
  /// The selection is not brought back: nothing plays after a relaunch, and
  /// tiles lit with no sound would say otherwise and make the first tap a
  /// stop rather than a start.
  void restore({required Map<String, double> volumes}) {
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
    final start = (_starts[sound.id] ?? 0) + 1;
    _starts[sound.id] = start;
    bool stale() =>
        _disposed || !_active.contains(sound.id) || _starts[sound.id] != start;
    try {
      var player = _players[sound.id];
      if (player == null) {
        // Loading takes a moment, and the player is not known to [stop]
        // until it is registered: check again before it may play.
        final loading = _createPlayer();
        try {
          await loading.setAsset(sound.asset);
          await loading.setLoopMode(LoopMode.one);
        } catch (_) {
          await _release(loading);
          rethrow;
        }
        if (stale()) {
          await _release(loading);
          return;
        }
        player = loading;
        _players[sound.id] = player;
      }
      await player.setVolume(volumeOf(sound.id));
      if (stale()) return;
      unawaited(player.play());
    } catch (_) {
      // Codec missing, asset absent, or autoplay blocked. Leave the tile lit
      // and the timer running; the next gesture retries naturally.
    }
  }

  Future<void> stop(String id) async {
    _active.remove(id);
    final player = _players.remove(id);
    if (player != null) await _release(player);
  }

  Future<void> _release(AudioPlayer player) async {
    try {
      await player.stop();
      await player.dispose();
    } catch (_) {
      // Already gone.
    }
  }

  Future<void> stopAll() async {
    // Tracks still loading have no player yet; clearing the selection is
    // what stops them from playing once they load.
    _active.clear();
    for (final id in _players.keys.toList()) {
      await stop(id);
    }
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

  Future<void> dispose() async {
    _disposed = true;
    await stopAll();
    _players.clear();
  }
}
