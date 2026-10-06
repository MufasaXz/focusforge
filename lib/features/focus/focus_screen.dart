import '../../shared/widgets/app_page.dart';
import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell/app_shell.dart';
import '../../app/theme/app_theme.dart';
import '../../core/models/study.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/audio_providers.dart';
import '../../core/providers/study_providers.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/animated_digits.dart';
import '../../shared/widgets/confetti_burst.dart';
import '../../shared/widgets/icon_badge.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/progress_ring.dart';
import '../../shared/widgets/stagger.dart';

/// Tab 3 — the focus engine: Pomodoro, subject tagging, an ambient mixer and a
/// live session dock pinned above the navigation bar.
///
/// The screen is a projection, not an owner. [timerProvider] holds the
/// wall-clock target, the phase machine and the completion stream; nothing here
/// counts ticks. A timer that accumulates seconds in the widget loses time
/// every time the app is backgrounded, which is the one failure a focus app
/// cannot ship with.
class FocusScreen extends ConsumerStatefulWidget {
  const FocusScreen({super.key});

  @override
  ConsumerState<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends ConsumerState<FocusScreen> {
  /// Space the pinned dock occupies, plus the clearance above it.
  static const double _dockHeight = 96;

  StreamSubscription<int>? _completions;
  Timer? _celebrationTimer;

  /// Bumped per celebration so the banner's switcher key is always fresh.
  int _celebrationId = 0;
  _Completion? _celebration;

  @override
  void initState() {
    super.initState();
    // The stream only fires for finished focus blocks — exactly the event that
    // earns the celebration. Break ends are detected as phase changes below.
    _completions = ref
        .read(timerProvider.notifier)
        .completions
        .listen(_celebrate);
  }

  @override
  void dispose() {
    _completions?.cancel();
    _celebrationTimer?.cancel();
    super.dispose();
  }

  void _celebrate(int minutes) {
    if (!mounted) return;
    ConfettiBurst.fire(context);
    unawaited(HapticFeedback.heavyImpact());

    final subjectId = ref.read(timerProvider).subjectId;
    final subject = subjectId == null
        ? null
        : ref
              .read(subjectsProvider)
              .where((s) => s.id == subjectId)
              .firstOrNull;

    _celebrationTimer?.cancel();
    setState(() {
      _celebrationId++;
      _celebration = _Completion(minutes: minutes, subject: subject);
    });
    // Long enough to read and act on, short enough not to sit in the way.
    _celebrationTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _celebration = null);
    });
  }

  /// A finished break gets a soft haptic, never confetti. The contrast is the
  /// point: quiet recovery, loud achievement.
  void _onBreakFinished() {
    if (!mounted) return;
    unawaited(HapticFeedback.selectionClick());
  }

  void _dismissCelebration() {
    _celebrationTimer?.cancel();
    if (mounted) setState(() => _celebration = null);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).colorScheme;
    final timer = ref.watch(timerProvider);
    final presets = ref.watch(presetsProvider);
    final preset = presets[timer.presetIndex];
    final subjects = ref.watch(subjectsProvider);
    final catalogue = ref.watch(ambientCatalogueProvider);
    final active = ref.watch(activeSoundsProvider);
    final volumes = ref.watch(volumesProvider);
    final stats = ref.watch(statsProvider);
    final minutesToday = ref.watch(focusMinutesTodayProvider);
    final sessionsToday = ref
        .watch(sessionsProvider.notifier)
        .forDay(DateTime.now())
        .where((s) => s.completed)
        .length;

    final accent = _phaseColor(t, timer.phase);
    final clock = formatClock(timer.remaining);
    final phaseNoun = timer.phase == TimerPhase.focus ? 'focus' : 'break';
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    // The dock floats above the nav-bar band; the scroll view has to clear both,
    // plus the home-indicator inset the nav bar itself grows by.
    final dockBottom = kNavBarClearance + safeBottom;
    final listBottom = dockBottom + _dockHeight + Gap.lg;

    // The engine emits focus completions on the stream. A break ending is only
    // visible as a phase change, so it is recognised by the break's target
    // instant having passed — a skipped break still has its target in the
    // future, and a reset has no target at all.
    ref.listen<TimerState>(timerProvider, (previous, next) {
      if (previous == null) return;
      final target = previous.targetEnd;
      if (previous.phase.isBreak &&
          next.phase == TimerPhase.focus &&
          target != null &&
          !target.isAfter(DateTime.now())) {
        _onBreakFinished();
      }
    });

    final cycleDone = timer.phase == TimerPhase.longBreak
        ? preset.segments
        : timer.completedFocusSegments % preset.segments;
    final currentDot = timer.phase == TimerPhase.focus ? cycleDone : -1;

    // Start and pause are the same control, so both directions get the same
    // medium tap — the completion and break-end haptics above are deliberately
    // different weights.
    void toggleTimer() {
      unawaited(HapticFeedback.mediumImpact());
      ref.read(timerProvider.notifier).toggle();
    }

    return Stack(
      children: [
        Positioned.fill(
          // The entrance waits for the branch to be on screen; see
          // [_TabEntrance].
          child: _TabEntrance(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                Gap.lg + 4,
                MediaQuery.paddingOf(context).top + Gap.lg,
                Gap.lg + 4,
                listBottom,
              ),
              children: [
                // Stagger plays once per element lifetime, and this branch is
                // built the first time the tab is shown (go_router does not
                // preload branches) — so the entrance lands on first visit, not
                // on every timer rebuild.
                Stagger(
                  index: 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Focus Engine', style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 3),
                      Text(
                        'Deep work, measured',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: t.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Gap.xl),

                // Preset ------------------------------------------------------
                Stagger(
                  index: 1,
                  child: Center(
                    child: Semantics(
                      button: true,
                      label: 'Preset: ${preset.name}. Change preset',
                      excludeSemantics: true,
                      onTap: () => _showPresetSheet(context),
                      child: FilterChip(
                        onSelected: (_) => _showPresetSheet(context),
                        // A menu trigger, not a filter: a selected state and a
                        // checkmark would misstate what the chip does.
                        showCheckmark: false,
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(preset.icon, size: 15, color: accent),
                            const SizedBox(width: 7),
                            Text(preset.name),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.expand_more_rounded,
                              size: 16,
                              color: t.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Gap.lg),

                // Subject tags ------------------------------------------------
                Stagger(
                  index: 2,
                  child: EdgeFade(
                    trailing: 32,
                    child: SizedBox(
                      height: 48,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: subjects.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: Gap.sm),
                        itemBuilder: (context, i) {
                          final s = subjects[i];
                          final selected = timer.subjectId == s.id;
                          void toggle() => ref
                              .read(timerProvider.notifier)
                              .setSubject(selected ? null : s.id);
                          return Semantics(
                            button: true,
                            selected: selected,
                            label:
                                'Subject ${s.name}, '
                                '${selected ? 'selected' : 'not selected'}',
                            excludeSemantics: true,
                            onTap: toggle,
                            child: FilterChip(
                              selected: selected,
                              onSelected: (_) => toggle(),
                              // The subject dot is the leading glyph; a
                              // checkmark would replace it and drop the
                              // colour that identifies the subject.
                              showCheckmark: false,
                              selectedColor: s.color.withValues(alpha: 0.20),
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: s.color,
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Text(
                                    s.name,
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Gap.xl),

                // Timer -------------------------------------------------------
                Stagger(
                  index: 3,
                  child: Center(
                    child: ProgressRing(
                      value: timer.progressFor(preset),
                      size: 208,
                      stroke: 11,
                      ticks: 60,
                      colors: [
                        accent,
                        Color.lerp(accent, t.secondary, 0.7)!,
                      ],
                      semanticLabel:
                          '${timer.phase.label}, $clock remaining, '
                          '${timer.running ? 'running' : 'paused'}',
                      child: ExcludeSemantics(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // The ring label carries the time for screen
                            // readers, so the digits themselves are silent.
                            SizedBox(
                              width: 168,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: AnimatedDigits(
                                  text: clock,
                                  style: Theme.of(context).textTheme.displayLarge!
                                      .copyWith(
                                        fontSize: 52,
                                        height: 1.02,
                                        letterSpacing: -2.2,
                                      ),
                                ),
                              ),
                            ),
                            const SizedBox(height: Gap.xs),
                            Text(
                              timer.phase.label,
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: accent,
                                fontSize: 12.5,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: Gap.md),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                for (
                                  var i = 0;
                                  i < preset.segments;
                                  i++
                                ) ...[
                                  if (i > 0) const SizedBox(width: 6),
                                  _SegmentDot(
                                    done: i < cycleDone,
                                    current: i == currentDot,
                                    color: accent,
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Gap.xl),

                // Ambient mixer ------------------------------------------------
                Stagger(
                  index: 4,
                  child: SectionHeader(
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
                              label: const Text(
                                'Stop all',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                  ),
                ),
                Stagger(
                  index: 5,
                  child: Card.filled(
                    child: Padding(
                      padding: const EdgeInsets.all(Gap.md),
                      child: Column(
                        children: [
                          GridView.count(
                            crossAxisCount: 2,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: Gap.md,
                            crossAxisSpacing: Gap.md,
                            childAspectRatio: 2.5,
                            children: [
                              for (final sound in catalogue)
                                _AmbientTile(
                                  tile: sound,
                                  active: active.contains(sound.id),
                                  onTap: () => unawaited(
                                    ref
                                        .read(activeSoundsProvider.notifier)
                                        .toggle(sound),
                                  ),
                                ),
                            ],
                          ),
                          // Volume lives on the active tracks only: a slider for
                          // a silent track would be a control with nothing to
                          // control.
                          if (active.isNotEmpty) ...[
                            const SizedBox(height: Gap.sm),
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: t.outlineVariant,
                            ),
                            for (final sound in catalogue.where(
                              (s) => active.contains(s.id),
                            ))
                              _VolumeRow(
                                sound: sound,
                                value: (volumes[sound.id] ?? 0.5).clamp(
                                  0.0,
                                  1.0,
                                ),
                                onChanged: (v) => unawaited(
                                  ref
                                      .read(volumesProvider.notifier)
                                      .set(sound.id, v),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Gap.xl),

                // Today --------------------------------------------------------
                const Stagger(
                  index: 6,
                  child: SectionHeader(
                    title: 'Today',
                    icon: Icons.today_outlined,
                  ),
                ),
                Stagger(
                  index: 7,
                  child: Row(
                    children: [
                      Expanded(
                        child: _InfoCapsule(
                          icon: Icons.local_fire_department_rounded,
                          color: t.tertiary,
                          value: 'Day ${stats.currentStreak}',
                          semanticLabel: 'Streak: ${stats.currentStreak} days',
                        ),
                      ),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: _InfoCapsule(
                          icon: Icons.timer_rounded,
                          color: t.primary,
                          value: formatMinutes(minutesToday),
                          semanticLabel:
                              'Focus time today: ${formatMinutes(minutesToday)}',
                        ),
                      ),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: _InfoCapsule(
                          icon: Icons.check_circle_rounded,
                          color: t.tertiary,
                          value: '$sessionsToday today',
                          semanticLabel: 'Sessions today: $sessionsToday',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Completion banner ---------------------------------------------------
        Positioned(
          left: Gap.lg + 4,
          right: Gap.lg + 4,
          bottom: dockBottom + _dockHeight + Gap.sm,
          child: IgnorePointer(
            ignoring: _celebration == null,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 340),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.25),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: _celebration == null
                  ? const SizedBox.shrink(key: ValueKey('no-celebration'))
                  : KeyedSubtree(
                      key: ValueKey('celebration-$_celebrationId'),
                      child: _buildBanner(t, _celebration!),
                    ),
            ),
          ),
        ),

        // Pinned session dock --------------------------------------------------
        Positioned(
          left: Gap.lg + 4,
          right: Gap.lg + 4,
          bottom: dockBottom,
          child: Card.filled(
            color: t.surfaceContainerHigh,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.lg,
                vertical: Gap.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: 'Reset timer',
                      excludeSemantics: true,
                      onTap: () => ref.read(timerProvider.notifier).reset(),
                      child: TextButton.icon(
                        onPressed: () =>
                            ref.read(timerProvider.notifier).reset(),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Reset'),
                        style: TextButton.styleFrom(
                          foregroundColor: t.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: timer.running
                        ? 'Pause $phaseNoun timer'
                        : 'Start $phaseNoun timer',
                    excludeSemantics: true,
                    onTap: toggleTimer,
                    child: Pressable(
                      onTap: toggleTimer,
                      scale: 0.92,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent,
                        ),
                        child: Icon(
                          timer.running
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 32,
                          color: _onPhaseColor(t, timer.phase),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: 'Skip to next phase',
                      excludeSemantics: true,
                      onTap: () => ref.read(timerProvider.notifier).skip(),
                      child: TextButton.icon(
                        onPressed: () =>
                            ref.read(timerProvider.notifier).skip(),
                        icon: const Icon(Icons.skip_next_rounded, size: 16),
                        label: const Text('Skip'),
                        iconAlignment: IconAlignment.end,
                        style: TextButton.styleFrom(
                          foregroundColor: t.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBanner(ColorScheme t, _Completion completion) {
    final subject = completion.subject;
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Focus block complete. ${completion.minutes} XP earned.',
      child: Card.outlined(
        // Floats over the live screen, so it takes the higher tonal surface.
        color: t.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconBadge(
                    icon: Icons.bolt_rounded,
                    color: t.tertiary,
                    size: 38,
                    radius: 11,
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Focus block complete',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          subject == null
                              ? '${completion.minutes} minutes of deep work'
                              : '${subject.name} · ${completion.minutes} minutes',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: t.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  Text(
                    '+${completion.minutes} XP',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: t.tertiary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.md),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _dismissCelebration,
                      child: const Text('Take a break'),
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        ref.read(timerProvider.notifier).skip();
                        _dismissCelebration();
                      },
                      child: const Text('Keep going'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPresetSheet(BuildContext context) {
    final presets = ref.read(presetsProvider);
    final current = ref.read(timerProvider).presetIndex;

    showModalBottomSheet<void>(
      context: context,
      // Root navigator: the sheet has to float over the nav bar, not under it.
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          Gap.lg,
          Gap.lg,
          Gap.lg,
          Gap.lg + MediaQuery.paddingOf(sheetContext).bottom,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.hero),
          // One of the three sanctioned blur sites: a modal sheet floats over
          // the page it was opened from.
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              padding: const EdgeInsets.all(Gap.lg),
              decoration: BoxDecoration(
                color: Theme.of(sheetContext).colorScheme.surfaceContainerLow
                    .withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(Radii.hero),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          sheetContext,
                        ).colorScheme.onSurfaceVariant,
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                    ),
                  ),
                  const SizedBox(height: Gap.lg),
                  Text(
                    'Pomodoro presets',
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                  const SizedBox(height: Gap.sm),
                  for (var i = 0; i < presets.length; i++)
                    _PresetRow(
                      preset: presets[i],
                      selected: i == current,
                      onTap: () {
                        ref.read(timerProvider.notifier).setPreset(i);
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A finished focus block, captured at the moment the engine reports it.
class _Completion {
  const _Completion({required this.minutes, this.subject});

  final int minutes;
  final Subject? subject;
}

Color _phaseColor(ColorScheme t, TimerPhase phase) => switch (phase) {
  TimerPhase.focus => t.primary,
  TimerPhase.shortBreak => t.tertiary,
  TimerPhase.longBreak => t.secondary,
};

/// Ink for content sitting on [_phaseColor] — the scheme's own on-colour
/// pairing, so the start button stays legible in both themes.
Color _onPhaseColor(ColorScheme t, TimerPhase phase) => switch (phase) {
  TimerPhase.focus => t.onPrimary,
  TimerPhase.shortBreak => t.onTertiary,
  TimerPhase.longBreak => t.onSecondary,
};

class _SegmentDot extends StatelessWidget {
  const _SegmentDot({
    required this.done,
    required this.current,
    required this.color,
  });

  final bool done;
  final bool current;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: current ? 18 : 7,
      height: 7,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.pill),
        color: done || current ? color : t.surfaceContainerHighest,
      ),
    );
  }
}

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

    return Semantics(
      button: true,
      selected: active,
      label: '${tile.name} ambience, ${active ? 'on' : 'off'}',
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: Gap.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.tile),
            color: active
                ? tile.color.withValues(alpha: 0.20)
                : t.surfaceContainer,
            border: Border.all(
              color: active
                  ? tile.color.withValues(alpha: 0.72)
                  : t.outlineVariant,
              width: active ? 1.3 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                tile.icon,
                size: 17,
                color: active ? tile.color : t.onSurfaceVariant,
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  tile.name,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: active ? t.onSurface : t.onSurfaceVariant,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (active)
                Icon(Icons.graphic_eq_rounded, size: 14, color: tile.color),
            ],
          ),
        ),
      ),
    );
  }
}

/// Volume for one live track. Only rendered for sounds that are playing.
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
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              Icon(sound.icon, size: 16, color: sound.color),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Slider(
                  value: value,
                  onChanged: onChanged,
                  // The name is on the node's label; the formatter only has to
                  // describe the value, or it is announced twice.
                  semanticFormatterCallback: (v) =>
                      '${(v * 100).round()} percent',
                ),
              ),
              // The percentage is a visual echo of the slider's own value.
              ExcludeSemantics(
                child: SizedBox(
                  width: 36,
                  child: Text(
                    '$percent%',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: t.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final PomodoroPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${preset.name}, ${preset.focus} minute focus, '
          '${preset.shortBreak} minute break, ${preset.segments} segments',
      excludeSemantics: true,
      onTap: onTap,
      child: ListTile(
        onTap: onTap,
        selected: selected,
        leading: IconBadge(
          icon: preset.icon,
          color: t.primary,
          size: 38,
          radius: 11,
        ),
        title: Text(preset.name),
        subtitle: Text(
          '${preset.focus}m focus · ${preset.shortBreak}m break · '
          '${preset.segments} segments',
        ),
        trailing: selected
            ? Icon(Icons.check_circle_rounded, size: 18, color: t.primary)
            : null,
      ),
    );
  }
}

class _InfoCapsule extends StatelessWidget {
  const _InfoCapsule({
    required this.icon,
    required this.color,
    required this.value,
    required this.semanticLabel,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Card.outlined(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: Gap.md,
            horizontal: Gap.sm,
          ),
          child: Column(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(height: 5),
              Text(
                value,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Holds a screen's staggered entrance until its tab is actually on screen.
///
/// The shell keeps every visited tab mounted in an `IndexedStack`, and
/// go_router wraps the inactive branches in a disabled [TickerMode]. A
/// [Stagger] starts its delay clock in `initState`, so a tree that is built
/// before the branch is shown plays its entrance to an empty room and the user
/// sees nothing move when they switch in. Deferring the first build until the
/// ticker mode is enabled starts the clock on the frame the tab first appears;
/// the flag latches, so a later switch back does not replay the entrance.
class _TabEntrance extends StatefulWidget {
  const _TabEntrance({required this.child});

  final Widget child;

  @override
  State<_TabEntrance> createState() => _TabEntranceState();
}

class _TabEntranceState extends State<_TabEntrance> {
  bool _entered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `TickerMode.valuesOf` registers a dependency on the branch's on-stage
    // state, so this runs again the moment the tab is switched in. No setState:
    // the framework rebuilds immediately after this call.
    if (!_entered && TickerMode.valuesOf(context).enabled) _entered = true;
  }

  @override
  Widget build(BuildContext context) =>
      _entered ? widget.child : const SizedBox.shrink();
}