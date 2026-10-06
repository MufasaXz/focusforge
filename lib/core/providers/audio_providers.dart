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

final ambientCatalogueProvider =
    Provider<List<AmbientSound>>((_) => SeedData.ambient);

/// Which tracks are lit. Mirrors the mixer so the tiles rebuild instantly
/// without waiting for an audio call to resolve.
class ActiveSoundsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void hydrate(Set<String> stored, Map<String, double> volumes) {
    if (stored.isEmpty && volumes.isEmpty) return;
    state = stored;
    ref.read(volumesProvider.notifier).hydrate(volumes);
    // Re-arm the mixer in the background; failure is non-fatal by design.
    ref.read(ambientMixerProvider).restore(active: stored, volumes: volumes);
  }

  LocalStore get _store => ref.read(localStoreProvider);

  Future<void> _persist() => _store.setList(
        StoreKeys.ambientActive,
        state.map((id) => {'id': id}).toList(growable: false),
      );

  Future<void> toggle(AmbientSound sound) async {
    final on = await ref.read(ambientMixerProvider).toggle(sound);
    state = on ? {...state, sound.id} : (state.toSet()..remove(sound.id));
    await _persist();
  }

  Future<void> clear() async {
    await ref.read(ambientMixerProvider).stopAll();
    state = const {};
    await _persist();
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
