import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/study.dart';
import '../../core/providers/audio_providers.dart';
import '../../core/services/audio_service.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/pressable.dart';

/// The ambient layer: what is playing under the session, and how loud.
///
/// Two things happen here and they are deliberately separated. The grid is the
/// choice — six tracks, any number of them at once — and the level list is the
/// mix, one row per track that is actually playing. A slider for a silent
/// track would be a control with nothing to control, so the list only exists
/// while something is in it, and it grows in rather than appearing.
class AmbientMixerSection extends ConsumerWidget {
  const AmbientMixerSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).colorScheme;
    final catalogue = ref.watch(ambientCatalogueProvider);
    final active = ref.watch(activeSoundsProvider);
    final volumes = ref.watch(volumesProvider);

    final playing = catalogue.where((s) => active.contains(s.id)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Ambient mix',
          icon: Icons.graphic_eq_outlined,
          trailing: active.isEmpty
              ? null
              : Semantics(
                  button: true,
                  label: 'Stop all ambient sounds',
                  excludeSemantics: true,
                  onTap: () => unawaited(
                    ref.read(activeSoundsProvider.notifier).clear(),
                  ),
                  child: FilterChip(
                    onSelected: (_) => unawaited(
                      ref.read(activeSoundsProvider.notifier).clear(),
                    ),
                    showCheckmark: false,
                    avatar: Icon(
                      Icons.stop_circle_outlined,
                      size: 15,
                      color: t.onSurfaceVariant,
                    ),
                    label: Text('Stop all', style: TextStyle(fontSize: 12)),
                  ),
                ),
        ),
        const SizedBox(height: Gap.md),
        Card.filled(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, Gap.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // A row of small pills rather than a grid of cards. Six sounds
                // is a short list and each one is one bit of state, so a
                // labelled tile per sound was six cards of furniture around
                // six taps. The name is not gone — it is on the tile's
                // semantics, and on the level slider the moment it is playing.
                Wrap(
                  spacing: Gap.sm,
                  runSpacing: Gap.sm,
                  children: [
                    for (final sound in catalogue)
                      _AmbientTile(
                        tile: sound,
                        active: active.contains(sound.id),
                        onTap: () {
                          unawaited(HapticFeedback.selectionClick());
                          unawaited(
                            ref
                                .read(activeSoundsProvider.notifier)
                                .toggle(sound),
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: Gap.md),
                // The instruction is the empty state: it says what the grid
                // does, and it leaves the moment there is a mix to look at.
                AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : Motion.base,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: playing.isEmpty
                      ? Row(
                          key: const ValueKey('ambient-hint'),
                          children: [
                            Icon(
                              Icons.layers_outlined,
                              size: 14,
                              color: t.onSurfaceVariant,
                            ),
                            const SizedBox(width: Gap.sm),
                            Expanded(
                              child: Text(
                                'Tap to layer sounds under your session. '
                                'They keep playing while the timer runs.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: t.onSurfaceVariant),
                              ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(key: ValueKey('ambient-no-hint')),
                ),
                // The mix. Sized rather than switched, so adding a second
                // track slides the card open instead of jumping.
                AnimatedSize(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : Motion.base,
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: playing.isEmpty
                      ? const SizedBox(width: double.infinity)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: Gap.md),
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: t.outlineVariant,
                            ),
                            const SizedBox(height: Gap.md),
                            Row(
                              children: [
                                Text(
                                  'Levels',
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: t.onSurfaceVariant,
                                        letterSpacing: 1.1,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const Spacer(),
                                Text(
                                  playing.length == 1
                                      ? '1 playing'
                                      : '${playing.length} playing',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(color: t.onSurfaceVariant),
                                ),
                              ],
                            ),
                            for (final sound in playing)
                              _VolumeRow(
                                sound: sound,
                                value:
                                    (volumes[sound.id] ??
                                            AmbientMixer.defaultVolume)
                                        .clamp(0.0, 1.0),
                                onChanged: (v) => unawaited(
                                  ref
                                      .read(volumesProvider.notifier)
                                      .set(sound.id, v),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One track. A stadium the size of its icon: the whole thing is the target,
/// and its state is carried by the colour, the border and the meter.
///
/// The corners are half-circles rather than a fixed radius, which is what
/// [StadiumBorder] means and what makes a shape this short read as a capsule
/// instead of a rounded rectangle — at this height a 12dp radius is most of
/// the tile, and the two look different.
class _AmbientTile extends StatelessWidget {
  const _AmbientTile({
    required this.tile,
    required this.active,
    required this.onTap,
  });

  final AmbientSound tile;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).colorScheme;
    final color = harmonize(tile.color, t.primary);
    final ink = active ? color : t.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: active,
      // The name lives here now that it is not on the tile: a screen reader
      // still has to be able to tell the six of them apart.
      label: '${tile.name} ambience, ${active ? 'on' : 'off'}',
      excludeSemantics: true,
      onTap: onTap,
      // The tile has no room for its name, so the name is one long press away
      // — and on the web, one hover. A row of six unlabelled glyphs is fine
      // once you know them and a guessing game before that.
      child: Tooltip(
        message: tile.name,
        waitDuration: const Duration(milliseconds: 420),
        child: Pressable(
          onTap: onTap,
          scale: 0.92,
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : Motion.base,
            curve: Curves.easeOutCubic,
            width: active ? 74 : 52,
            height: 48,
            decoration: ShapeDecoration(
              shape: StadiumBorder(
                side: BorderSide(
                  color: active
                      ? color.withValues(alpha: 0.72)
                      : t.outlineVariant,
                  width: active ? 1.3 : 1,
                ),
              ),
              color: active
                  ? color.withValues(alpha: 0.20)
                  : t.surfaceContainer,
            ),
            child: Center(
              child: active
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(tile.icon, size: 16, color: ink),
                        const SizedBox(width: 6),
                        _Equalizer(color: color),
                      ],
                    )
                  : Icon(tile.icon, size: 18, color: ink),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three bars that move while the track is playing.
///
/// Built only for tracks that are on, so there are never more of these than
/// there are sounds in the mix, and they stop existing the moment the track is
/// switched off.
class _Equalizer extends StatefulWidget {
  const _Equalizer({required this.color});

  final Color color;

  @override
  State<_Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<_Equalizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _pulse.stop();
      _pulse.value = 0;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  /// Each bar's phase offset, so the three do not move as one block.
  static const _offsets = [0.0, 0.45, 0.2];
  static const _heights = [0.55, 1.0, 0.75];

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 16,
    height: 14,
    child: AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: 3,
              // A sine per bar, offset so the three do not move as one block.
              height:
                  14 *
                  _heights[i] *
                  (0.42 +
                      0.58 *
                          (0.5 +
                              0.5 *
                                  math.sin(
                                    2 * math.pi * (_pulse.value + _offsets[i]),
                                  ))),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
            ),
        ],
      ),
    ),
  );
}

/// One live track's level.
///
/// The name sits above the slider rather than beside it: a row of icon, name,
/// slider and percentage on a phone leaves the slider about 90dp wide, which
/// is not enough to mix with. Stacking gives it the full width of the card.
class _VolumeRow extends StatelessWidget {
  const _VolumeRow({
    required this.sound,
    required this.value,
    required this.onChanged,
  });

  final AmbientSound sound;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).colorScheme;
    final percent = (value * 100).round();

    return MergeSemantics(
      child: Semantics(
        label: '${sound.name} volume',
        child: Padding(
          padding: const EdgeInsets.only(top: Gap.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(sound.icon, size: 15, color: sound.color),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(
                      sound.name,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: t.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // The percentage is a visual echo of the slider's own value.
                  ExcludeSemantics(
                    child: Text(
                      '$percent%',
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: t.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 7,
                  ),
                ),
                child: Slider(
                  value: value,
                  activeColor: sound.color,
                  inactiveColor: t.surfaceContainerHighest,
                  onChanged: onChanged,
                  // The name is on the node's label; the formatter only has to
                  // describe the value, or it is announced twice.
                  semanticFormatterCallback: (v) =>
                      '${(v * 100).round()} percent',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
