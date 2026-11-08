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

/// Which tracks are lit. Mirrors the mixer so the tiles rebuild instantly
/// without waiting for an audio call to resolve.
class ActiveSoundsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  /// Brings back the chosen volumes. Nothing plays after a relaunch, so no
  /// track starts out lit.
  void hydrate(Map<String, double> volumes) {
    if (volumes.isEmpty) return;
    ref.read(volumesProvider.notifier).hydrate(volumes);
    ref.read(ambientMixerProvider).restore(volumes: volumes);
  }

  Future<void> toggle(AmbientSound sound) async {
    final mixer = ref.read(ambientMixerProvider);
    await mixer.toggle(sound);
    // The mixer's selection, not this toggle's result: another toggle or
    // Stop all may have landed while this one was loading.
    state = mixer.active;
  }

  Future<void> clear() async {
    await ref.read(ambientMixerProvider).stopAll();
    state = const {};
  }
}

final activeSoundsProvider =
    NotifierProvider<ActiveSoundsNotifier, Set<String>>(
      ActiveSoundsNotifier.new,
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
