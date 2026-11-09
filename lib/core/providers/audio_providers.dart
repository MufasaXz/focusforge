import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/seed.dart';
import '../services/audio_service.dart';
import '../services/local_store.dart';
import 'app_providers.dart';

/// The mixer is a plain object with a lifecycle, so it lives in a [Provider]
/// that tears it down when the scope dies.
final ambientMixerProvider = Provider<AmbientMixer>((ref) {
  final mixer = AmbientMixer();
  ref.onDispose(mixer.dispose);
  return mixer;
});

final ambientCatalogueProvider = Provider<List<AmbientSound>>(
  (_) => SeedData.ambient,
);

/// Which tracks are selected. Follows the mixer, so it also changes when a
/// load finishes, the platform refuses a track, or Stop all completes after
/// another track was chosen.
class ActiveSoundsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    final mixer = ref.watch(ambientMixerProvider);
    void sync() => state = mixer.active;
    mixer.addListener(sync);
    ref.onDispose(() => mixer.removeListener(sync));
    return mixer.active;
  }

  /// Brings back the chosen volumes. Nothing plays after a relaunch, so no
  /// track starts out lit.
  void hydrate(Map<String, double> volumes) {
    if (volumes.isEmpty) return;
    ref.read(volumesProvider.notifier).hydrate(volumes);
    ref.read(ambientMixerProvider).restore(volumes: volumes);
  }

  Future<bool> toggle(AmbientSound sound) =>
      ref.read(ambientMixerProvider).toggle(sound);

  Future<void> retry(AmbientSound sound) =>
      ref.read(ambientMixerProvider).retry(sound);

  Future<void> clear() => ref.read(ambientMixerProvider).stopAll();
}

final activeSoundsProvider =
    NotifierProvider<ActiveSoundsNotifier, Set<String>>(
      ActiveSoundsNotifier.new,
    );

/// Whether each selected track is loading, playing or failed.
class TrackStatusNotifier extends Notifier<Map<String, TrackStatus>> {
  @override
  Map<String, TrackStatus> build() {
    final mixer = ref.watch(ambientMixerProvider);
    void sync() => state = mixer.statuses;
    mixer.addListener(sync);
    ref.onDispose(() => mixer.removeListener(sync));
    return mixer.statuses;
  }
}

final trackStatusProvider =
    NotifierProvider<TrackStatusNotifier, Map<String, TrackStatus>>(
      TrackStatusNotifier.new,
    );

class VolumesNotifier extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => const {};

  void hydrate(Map<String, double> stored) {
    if (stored.isNotEmpty) state = stored;
  }

  LocalStore get _store => ref.read(localStoreProvider);

  Future<void> set(String id, double value) async {
    state = {...state, id: value};
    await ref.read(ambientMixerProvider).setVolume(id, value);
    await _store.setDoubleMap(StoreKeys.ambientVolumes, state);
  }

  double of(String id) => state[id] ?? 0.5;
}

final volumesProvider = NotifierProvider<VolumesNotifier, Map<String, double>>(
  VolumesNotifier.new,
);
