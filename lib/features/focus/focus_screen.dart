import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell/app_shell.dart';
import '../../app/theme/app_theme.dart';
import '../../core/data/seed.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/study_providers.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/confetti_burst.dart';
import '../../shared/widgets/icon_badge.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/progress_ring.dart';
import '../../shared/widgets/stagger.dart';
import 'ambient_mixer.dart';
import 'custom_plan_sheet.dart';
import 'fullscreen_clock.dart';
import 'subject_picker.dart';
import 'widgets/clock_faces.dart';

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
  static const double _dockHeight = 78;

  /// How wide the dock and the completion banner are allowed to get.
  ///
  /// Both are pinned over the whole tab, and the tab is the width of a tablet
  /// once the rail is beside it — a stadium-shaped control a thousand pixels
  /// wide puts Reset and Skip a hand apart, and the banner reads as a bar
  /// rather than as a card. Centred, so the pair stays under the timer.
  static const double _dockWidth = 460;

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
    final face = ref.watch(clockFaceProvider);
    final presets = ref.watch(presetsProvider);
    final preset = presets[timer.presetIndex];
    final streak = ref.watch(currentStreakProvider);
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
                // No headline. The screen opens on the preset and the subject
                // tags and then the clock, which is what the tab is for; a
                // title over it only spent height on words the rail already
                // says. Stagger plays once per element lifetime, and this
                // branch is built the first time the tab is shown (go_router
                // does not preload branches) — so the entrance lands on first
                // visit, not on every timer rebuild.

                // Preset ------------------------------------------------------
                Stagger(
                  index: 0,
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
                Stagger(index: 1, child: SubjectPicker(accent: accent)),
                const SizedBox(height: Gap.xl),

                // Timer -------------------------------------------------------
                Stagger(
                  index: 2,
                  child: Column(
                    children: [
                      Center(
                        // The ring is the clock's own frame, so the gesture
                        // that opens it full screen belongs on the ring rather
                        // than on a button beside it. A single tap is left
                        // alone: nothing else on this screen wants it, and
                        // swallowing it would make the ring feel like a
                        // control the user has to be careful with.
                        child: GestureDetector(
                          onDoubleTap: () => showFullscreenClock(context),
                          // A double tap is not a gesture a screen reader can
                          // perform, so the same route is the clock's own
                          // action — the label says what it reads, the hint
                          // says what it does.
                          child: Semantics(
                            button: true,
                            label:
                                '${timer.phase.label}, $clock remaining, '
                                '${timer.running ? 'running' : 'paused'}',
                            hint: 'Opens the clock full screen',
                            onTap: () => showFullscreenClock(context),
                            // Two faces bring their own frame. The flip board
                            // is a wide rectangle and a dial around it both
                            // fights its shape and shrinks it; the analog face
                            // is a dial, and a ring outside a dial is a circle
                            // around a circle. Both take the width instead,
                            // and the ring stays with the faces that fit it.
                            child: ExcludeSemantics(
                              child: switch (face) {
                                ClockFace.flip => _FlipClock(
                                  remaining: timer.remaining,
                                  accent: accent,
                                  phase: timer.phase,
                                  segments: preset.segments,
                                  cycleDone: cycleDone,
                                  currentDot: currentDot,
                                ),
                                ClockFace.analog => _AnalogFace(
                                  remaining: timer.remaining,
                                  accent: accent,
                                  phase: timer.phase,
                                  segments: preset.segments,
                                  cycleDone: cycleDone,
                                  currentDot: currentDot,
                                  progress: timer.progressFor(preset),
                                ),
                                _ => ProgressRing(
                                  value: timer.progressFor(preset),
                                  size: 252,
                                  stroke: 12,
                                  ticks: 60,
                                  // The second horizon: how far through the set of
                                  // focus blocks this session is. The inner arc
                                  // answers "how much longer", which is a different
                                  // question from "how many more", and a timer that
                                  // shows only one of them makes the other a mental
                                  // sum.
                                  outer: preset.segments <= 0
                                      ? null
                                      : (timer.completedFocusSegments %
                                                preset.segments) /
                                            preset.segments,
                                  colors: [
                                    accent,
                                    Color.lerp(accent, t.secondary, 0.7)!,
                                  ],
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // The label carries the time for
                                      // screen readers, so the figures
                                      // themselves are silent.
                                      SizedBox(
                                        width: 214,
                                        height: 78,
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: ClockDisplay(
                                            remaining: timer.remaining,
                                            face: face,
                                            accent: accent,
                                            height: 72,
                                            progress: timer.progressFor(preset),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: Gap.xs),
                                      _ClockCaption(
                                        phase: timer.phase,
                                        accent: accent,
                                        segments: preset.segments,
                                        cycleDone: cycleDone,
                                        currentDot: currentDot,
                                      ),
                                    ],
                                  ),
                                ),
                              },
                            ),
                          ),
                        ),
                      ),
                      // The gesture is not visible, so it is said out loud
                      // once. It sits under the ring rather than inside it:
                      // the ring's own content is the clock, and a caption in
                      // there would have to shrink the figures to fit. The
                      // space above it is deliberate — butted against the
                      // ring's box the caption reads as part of the dial.
                      const SizedBox(height: Gap.md),
                      Text(
                        'Double-tap the clock for full screen',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 10.5,
                          color: t.onSurfaceVariant.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Gap.xl),

                // Ambient mixer ------------------------------------------------
                const Stagger(index: 3, child: AmbientMixerSection()),
                const SizedBox(height: Gap.xl),

                // Today --------------------------------------------------------
                const Stagger(
                  index: 4,
                  child: SectionHeader(
                    title: 'Today',
                    icon: Icons.today_outlined,
                  ),
                ),
                Stagger(
                  index: 5,
                  child: Row(
                    children: [
                      Expanded(
                        child: _InfoCapsule(
                          icon: Icons.local_fire_department_rounded,
                          color: t.tertiary,
                          value: 'Day $streak',
                          semanticLabel: 'Streak: $streak days',
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
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _dockWidth),
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
          ),
        ),

        // Pinned session dock --------------------------------------------------
        Positioned(
          left: Gap.lg + 4,
          right: Gap.lg + 4,
          bottom: dockBottom,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _dockWidth),
              child: Card.filled(
                color: t.surfaceContainerHigh,
                shape: const StadiumBorder(),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Gap.sm,
                    vertical: Gap.sm,
                  ),
                  // Centred rather than spread. The bar keeps its full width —
                  // it is a surface the thumb lands on, and a shrink-wrapped
                  // pill floating over the page reads as a tooltip — but the
                  // three controls sit together in the middle of it, because
                  // Reset and Skip are one gesture away from the play button,
                  // not a reach away from it.
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _DockAction(
                        icon: Icons.refresh_rounded,
                        label: 'Reset',
                        semanticLabel: 'Reset timer',
                        color: t.onSurfaceVariant,
                        onTap: () => ref.read(timerProvider.notifier).reset(),
                      ),
                      const SizedBox(width: Gap.sm),
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
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accent,
                            ),
                            child: Icon(
                              timer.running
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 27,
                              color: _onPhaseColor(t, timer.phase),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: Gap.sm),
                      _DockAction(
                        icon: Icons.skip_next_rounded,
                        label: 'Skip',
                        semanticLabel: 'Skip to next phase',
                        color: t.onSurfaceVariant,
                        onTap: () => ref.read(timerProvider.notifier).skip(),
                      ),
                    ],
                  ),
                ),
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
              // The rows are ListTiles, and a ListTile paints its ink on the
              // nearest Material ancestor. Without this one the nearest is
              // above the decorated container, so the splash lands under the
              // sheet's own background and never shows.
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(sheetContext)
                              .colorScheme
                              .onSurfaceVariant,
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
                    // The shipped presets, then the user's own plan as one row
                    // that both selects and edits it. The custom preset is
                    // deliberately not listed as an ordinary row as well: the
                    // same plan under two rows would leave the user guessing
                    // which one is the one they set.
                    for (var i = 0; i < SeedData.presets.length; i++)
                      _PresetRow(
                        preset: presets[i],
                        selected: i == current,
                        onTap: () {
                          ref.read(timerProvider.notifier).setPreset(i);
                          Navigator.of(sheetContext).pop();
                        },
                      ),
                    _CustomPlanRow(
                      plan: ref.read(customPlanProvider),
                      selected: current >= SeedData.presets.length,
                      onTap: () async {
                        final plan = await showCustomPlanSheet(sheetContext);
                        if (plan == null) return;
                        await ref.read(customPlanProvider.notifier).set(plan);
                        ref
                            .read(timerProvider.notifier)
                            .setPreset(ref.read(presetsProvider).length - 1);
                        if (sheetContext.mounted) {
                          Navigator.of(sheetContext).pop();
                        }
                      },
                    ),
                  ],
                ),
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

/// The flip board with the width to itself.
///
/// No dial. The board is a wide rectangle and the ring is a circle, so framing
/// one with the other left the figures smaller than they are on any other
/// face — the one face that reads best at size was the one drawn smallest. It
/// is sized from the width it is given instead, which on a phone is the whole
/// column.
class _FlipClock extends StatelessWidget {
  const _FlipClock({
    required this.remaining,
    required this.accent,
    required this.phase,
    required this.segments,
    required this.cycleDone,
    required this.currentDot,
  });

  final Duration remaining;
  final Color accent;
  final TimerPhase phase;
  final int segments;
  final int cycleDone;
  final int currentDot;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The board is about 2.8 figure-heights wide, so this is the tallest
        // it can stand and still fit the column it was handed. The bounds keep
        // it legible on the narrowest phone and from spilling off a tablet.
        final height = (constraints.maxWidth / 2.8).clamp(96.0, 168.0);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClockDisplay(
              remaining: remaining,
              face: ClockFace.flip,
              accent: accent,
              height: height,
            ),
            const SizedBox(height: Gap.lg),
            _ClockCaption(
              phase: phase,
              accent: accent,
              segments: segments,
              cycleDone: cycleDone,
              currentDot: currentDot,
            ),
          ],
        );
      },
    );
  }
}

/// The analog dial with the width to itself.
///
/// Same reasoning as the flip board: the ring is a circle drawn around the
/// dial's box, so the dial ends up the smallest circle inside the largest one
/// and the hands get whatever the ring, the ticks and the caption leave. The
/// dial takes the column instead, and carries the session on its own rim —
/// which is where a line belongs on a dial anyway.
class _AnalogFace extends StatelessWidget {
  const _AnalogFace({
    required this.remaining,
    required this.accent,
    required this.phase,
    required this.segments,
    required this.cycleDone,
    required this.currentDot,
    required this.progress,
  });

  final Duration remaining;
  final Color accent;
  final TimerPhase phase;
  final int segments;
  final int cycleDone;
  final int currentDot;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // A dial is square, so it is measured against the width it was handed
        // the way the board is. The bounds keep the hands legible on the
        // narrowest phone and stop it swallowing a tablet.
        final side = (constraints.maxWidth * 0.66).clamp(168.0, 264.0);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: side,
              height: side,
              child: ClockDisplay(
                remaining: remaining,
                face: ClockFace.analog,
                accent: accent,
                height: side,
                progress: progress,
              ),
            ),
            const SizedBox(height: Gap.lg),
            _ClockCaption(
              phase: phase,
              accent: accent,
              segments: segments,
              cycleDone: cycleDone,
              currentDot: currentDot,
            ),
          ],
        );
      },
    );
  }
}

/// The line under the clock: which segment is running, and how far through the
/// set of them the session is.
class _ClockCaption extends StatelessWidget {
  const _ClockCaption({
    required this.phase,
    required this.accent,
    required this.segments,
    required this.cycleDone,
    required this.currentDot,
  });

  final TimerPhase phase;
  final Color accent;
  final int segments;
  final int cycleDone;
  final int currentDot;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          phase.label,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: accent, fontSize: 12.5, letterSpacing: 0.3),
        ),
        const SizedBox(height: Gap.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < segments; i++) ...[
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
    );
  }
}

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

/// The user's own plan, as a row in the preset sheet.
///
/// It reads as a preset and behaves as an editor: the numbers it was built
/// from are not on the row, so there is nothing here to change except by
/// opening the sheet behind it.
class _CustomPlanRow extends StatelessWidget {
  const _CustomPlanRow({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  final CustomPlan? plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).colorScheme;
    final summary = plan == null
        ? 'Set your own goal and block length'
        : '${formatMinutes(plan!.goalMinutes)} goal · ${plan!.blocks} × '
              '${plan!.focusMinutes}m · ${plan!.shortBreak}m break';

    return Semantics(
      button: true,
      selected: selected,
      label: 'Custom plan. $summary. Opens the editor',
      excludeSemantics: true,
      onTap: onTap,
      child: ListTile(
        onTap: onTap,
        selected: selected,
        leading: IconBadge(
          icon: Icons.tune_rounded,
          color: t.primary,
          size: 38,
          radius: 11,
        ),
        title: const Text('Custom plan'),
        subtitle: Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: selected
            ? Icon(Icons.check_circle_rounded, size: 18, color: t.primary)
            : Icon(Icons.edit_outlined, size: 18, color: t.onSurfaceVariant),
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

/// Reset or Skip: a small icon-and-word target beside the play button.
///
/// A plain [TextButton] in an `Expanded` was the obvious thing and the wrong
/// one — it filled a third of the bar each, so the two labels sat a hand apart
/// with the play button marooned in the middle. These are the size of what
/// they do.
class _DockAction extends StatelessWidget {
  const _DockAction({
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String semanticLabel;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        scale: 0.94,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.sm + 2,
            vertical: Gap.sm + 2,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: color),
              const SizedBox(height: 3),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
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
