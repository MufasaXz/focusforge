import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../models/study.dart';

/// Where one selected track is: on its way, audible, or refused by the
/// platform. A track that is not selected has no status.
enum TrackStatus { loading, playing, failed }

/// Layers several looping ambience tracks on top of each other.
///
/// One [AudioPlayer] per active sound. Every track loops forever and carries
/// its own volume, so "rain at 40% under a café at 25%" is just two players
/// running at once — the platform mixes them for free.
///
/// Failures never throw. Audio is an enhancement to a focus session, never a
/// precondition for one: if a codec is missing, or the browser blocks
/// autoplay until the first gesture, the timer keeps running and the track
/// is marked [TrackStatus.failed] so the screen can offer a retry.
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
  final Map<String, TrackStatus> _status = {};
  final List<void Function()> _listeners = [];

  bool _disposed = false;

  Set<String> get active => Set.unmodifiable(_active);
  bool get isPlaying => _active.isNotEmpty;

  /// The status of every selected track.
  Map<String, TrackStatus> get statuses => Map.unmodifiable(_status);

  /// Called after every change to [active] or [statuses], including ones
  /// that arrive later than the call that caused them: a load finishing or
  /// the platform refusing to play.
  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _changed() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

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
  ///
  /// A track that failed is started again rather than stopped: it is not
  /// playing, so a tap on it means "try again".
  Future<bool> toggle(AmbientSound sound) async {
    if (_disposed) return false;
    if (_active.contains(sound.id) && _status[sound.id] != TrackStatus.failed) {
      await stop(sound.id);
      return false;
    }
    await retry(sound);
    return true;
  }

  /// Starts [sound], or starts it again after a failure.
  Future<void> retry(AmbientSound sound) async {
    if (_disposed) return;
    _active.add(sound.id);
    _assets[sound.id] = sound.asset;
    await _start(sound);
  }

  Future<void> _start(AmbientSound sound) async {
    final id = sound.id;
    final start = (_starts[id] ?? 0) + 1;
    _starts[id] = start;
    bool stale() => _disposed || !_active.contains(id) || _starts[id] != start;
    _status[id] = TrackStatus.loading;
    _changed();
    try {
      var player = _players[id];
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
        _players[id] = player;
      }
      await player.setVolume(volumeOf(id));
      if (stale()) return;
      _status[id] = TrackStatus.playing;
      _changed();
      final playing = player;
      // A looping track's play() only completes when it stops, so it is not
      // awaited; a refusal arrives through it later.
      unawaited(
        Future.sync(playing.play).then<void>(
          (_) {},
          onError: (Object _) {
            // Only this start's own player may mark the track: a refusal
            // from a player since stopped or replaced is not news.
            if (stale() || _players[id] != playing) return;
            _players.remove(id);
            unawaited(_release(playing));
            _status[id] = TrackStatus.failed;
            _changed();
          },
        ),
      );
    } catch (_) {
      // Codec missing or asset absent. Keep the selection and the timer;
      // the screen offers a retry.
      if (stale()) return;
      _status[id] = TrackStatus.failed;
      _changed();
    }
  }

  Future<void> stop(String id) async {
    _active.remove(id);
    _status.remove(id);
    final player = _players.remove(id);
    _changed();
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

  /// Stops every track selected now. A track chosen while these are still
  /// being torn down is a new selection and keeps playing.
  Future<void> stopAll() async {
    // Tracks still loading have no player yet; clearing the selection is
    // what stops them from playing once they load.
    final players = _players.values.toList();
    _players.clear();
    _active.clear();
    _status.clear();
    _changed();
    for (final player in players) {
      await _release(player);
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
    _listeners.clear();
    await stopAll();
  }
}
