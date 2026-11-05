import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/shell/app_shell.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/study_providers.dart';
import '../../../core/services/local_store.dart';
import '../assistant_memory.dart';
import '../brain/assistant_brain.dart';
import '../brain/assistant_models.dart';
import '../brain/study_snapshot.dart';
import '../mascot/mascot.dart';
import '../mascot/mascot_life.dart';
import '../mascot/mascot_painter.dart';
import '../mascot/mascot_rig.dart';

/// Pip on the home screen, standing on the navigation pill.
///
/// Pip waves hello once per launch and stays mostly quiet after that: its
/// tips are rare by design — at most one a visit, never within three hours of
/// the last, and none at all with tips paused. Left alone, Pip sits down, has
/// a think, and falls asleep; any touch wakes it. Its eyes follow a finger,
/// and it ducks behind the bar while the page scrolls.
class PipDock extends ConsumerStatefulWidget {
  const PipDock({super.key, required this.child});

  /// The home screen Pip stands over.
  final Widget child;

  /// Pip's width on the home screen.
  static const double width = 58;

  /// Extra scroll room so the last card can rise above Pip.
  static const double clearance = 72;

  @override
  ConsumerState<PipDock> createState() => _PipDockState();
}

class _PipDockState extends ConsumerState<PipDock> with WidgetsBindingObserver {
  static const _sitAfter = Duration(seconds: 20);
  static const _thinkAfter = Duration(seconds: 36);
  static const _sleepAfter = Duration(seconds: 65);
  static const _tipCooldown = Duration(hours: 3);
  static const _greetAfterAway = Duration(minutes: 20);

  final _rig = MascotRig();
  late final _life = MascotLife(_rig);
  final _brain = const AssistantBrain();
  final _mascotKey = GlobalKey();
  final _timers = <Timer>{};
  Timer? _idle;
  Timer? _bubbleTimer;

  BuddyPrompt? _bubble;
  bool _typing = false;
  bool _ducked = false;
  bool _entered = false;
  bool _active = false;
  bool _foreground = true;
  bool _tipShown = false;
  int _rests = 0;
  DateTime _lastGaze = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _entered = true);
      _after(const Duration(milliseconds: 450), _hello);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _setActive(TickerMode.valuesOf(context).enabled && _foreground);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      unawaited(
        ref.read(assistantMemoryProvider.notifier).markSeen(DateTime.now()),
      );
    }
    if (mounted) {
      _setActive(TickerMode.valuesOf(context).enabled && _foreground);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final timer in _timers) {
      timer.cancel();
    }
    _idle?.cancel();
    _bubbleTimer?.cancel();
    _life.dispose();
    _rig.dispose();
    super.dispose();
  }

  /// Runs [action] after [delay], unless Pip has gone by then.
  void _after(Duration delay, void Function() action) {
    late final Timer timer;
    timer = Timer(delay, () {
      _timers.remove(timer);
      if (mounted) action();
    });
    _timers.add(timer);
  }

  void _setActive(bool active) {
    if (_active == active) return;
    _active = active;
    if (active) {
      _life.start();
      _restartIdle();
    } else {
      _life.stop();
      _idle?.cancel();
      _hideBubble();
    }
  }

  // -- Hello and tips ---------------------------------------------------------

  void _hello() {
    if (ref.read(assistantGreetedProvider)) {
      _rig.blink();
      return;
    }
    ref.read(assistantGreetedProvider.notifier).state = true;
    final s = StudySnapshot.capture(ref.read);
    final seen = s.memory.lastSeen;
    _rig.wave();
    final coachPending =
        !(ref.read(localStoreProvider).getBool(StoreKeys.coachSeen) ?? false);
    final away = seen == null ? null : s.now.difference(seen);
    if (!_quiet(s) &&
        !coachPending &&
        (away == null || away >= _greetAfterAway)) {
      _after(
        const Duration(milliseconds: 500),
        () => _show(_brain.greeting(s)),
      );
    }
    unawaited(ref.read(assistantMemoryProvider.notifier).markSeen(s.now));
  }

  bool _quiet(StudySnapshot s) =>
      s.memory.quiet || ref.read(timerProvider).running;

  /// Offers one useful observation, if Pip has not spoken in a while.
  void _maybeTip() {
    if (_tipShown || _bubble != null || !_active) return;
    final s = StudySnapshot.capture(ref.read);
    if (_quiet(s)) return;
    final last = s.memory.lastTipAt;
    if (last != null && s.now.difference(last) < _tipCooldown) return;
    final tips = _brain.homeTips(s);
    if (tips.isEmpty) return;
    _tipShown = true;
    unawaited(ref.read(assistantMemoryProvider.notifier).markTipShown(s.now));
    _show(tips.first);
  }

  void _show(BuddyPrompt prompt) {
    if (!_active || _rig.sleeping) return;
    _bubbleTimer?.cancel();
    final typing = !MediaQuery.disableAnimationsOf(context);
    setState(() {
      _bubble = prompt;
      _typing = typing;
    });
    _rig.presenting = true;
    if (typing) {
      _bubbleTimer = Timer(const Duration(milliseconds: 750), () {
        if (!mounted) return;
        setState(() => _typing = false);
        _rig.talk();
        _bubbleTimer = Timer(const Duration(milliseconds: 6500), _hideBubble);
      });
    } else {
      _bubbleTimer = Timer(const Duration(seconds: 8), _hideBubble);
    }
  }

  void _hideBubble() {
    _bubbleTimer?.cancel();
    _rig.presenting = false;
    if (_bubble == null || !mounted) return;
    setState(() => _bubble = null);
  }

  // -- Idle -------------------------------------------------------------------

  void _restartIdle() {
    _idle?.cancel();
    final rest = ++_rests;
    if (!_active) return;
    // Counted in ticks rather than read off the wall clock, so a paused tab
    // does not come back to a Pip that "slept" while nobody was looking.
    var quiet = Duration.zero;
    var thought = false;
    void next() {
      _idle = Timer(const Duration(seconds: 1), () {
        if (!mounted || !_active) return;
        quiet += const Duration(seconds: 1);
        if (quiet >= _sleepAfter) {
          if (!_rig.sleeping) {
            _hideBubble();
            _rig.thinking = false;
            _rig.fallAsleep();
          }
          return;
        }
        if (quiet >= _thinkAfter && !thought) {
          // One think per quiet stretch. A tip only follows if the user is
          // still leaving Pip alone when the thought is done.
          thought = true;
          _rig.thinking = true;
          _after(const Duration(milliseconds: 1600), () {
            if (rest != _rests) return;
            _rig.thinking = false;
            _maybeTip();
          });
        } else if (quiet >= _sitAfter && !_rig.sitting && _bubble == null) {
          _rig.sitDown();
        }
        next();
      });
    }

    next();
  }

  /// Any touch or scroll on the home screen.
  void _poke() {
    if (_rig.sleeping) {
      _rig.wake();
      _after(const Duration(milliseconds: 650), _rig.standUp);
    } else if (_rig.sitting) {
      _rig.standUp();
    }
    _rig.thinking = false;
    _restartIdle();
  }

  void _lookToward(Offset global) {
    final box = _mascotKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || _rig.sleeping) return;
    final now = DateTime.now();
    if (now.difference(_lastGaze) < const Duration(milliseconds: 60)) return;
    _lastGaze = now;
    final eye = box.localToGlobal(
      Offset(
        box.size.width * MascotPainter.eyeFraction.dx,
        box.size.height * MascotPainter.eyeFraction.dy,
      ),
    );
    final d = global - eye;
    final reach = math.max(d.distance, 140.0);
    _life.holdGaze = true;
    _rig.lookAt(d.dx / reach, d.dy / reach);
  }

  void _releaseGaze() {
    _after(const Duration(milliseconds: 1200), () {
      _life.holdGaze = false;
      if (!_rig.thinking) _rig.lookAhead();
    });
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification is ScrollUpdateNotification &&
        (notification.scrollDelta ?? 0).abs() > 0.5) {
      _poke();
      _hideBubble();
      if (!_ducked) setState(() => _ducked = true);
    } else if (notification is ScrollEndNotification && _ducked) {
      _after(const Duration(milliseconds: 650), () {
        if (_ducked) setState(() => _ducked = false);
      });
    }
    return false;
  }

  // -- Opening the chat -------------------------------------------------------

  void _open([AssistantAction? action]) {
    unawaited(HapticFeedback.lightImpact());
    _hideBubble();
    _rig.standUp();
    _rig.cheer();
    _after(const Duration(milliseconds: 180), () {
      context.push(AppRoutes.paths[AppRoutes.assistant]!, extra: action);
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final cs = Theme.of(context).colorScheme;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final pill = media.size.width < AppShell.railBreakpoint;
    // The pill's top edge, measured up from the bottom of the page: the
    // shell reports the bar's whole height as bottom padding, and the bar
    // keeps 8 dp of air above the pill.
    final floor = pill
        ? math.max(media.padding.bottom - 8, 0.0)
        : media.padding.bottom + Gap.lg;
    const width = PipDock.width;
    final height = Mascot.heightFor(width);
    final belowFloor = height * (1 - MascotPainter.floorFraction);
    final right = pill ? 16.0 + 22 : Gap.xl;
    final bubble = _bubble;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _poke();
        _lookToward(event.position);
      },
      onPointerMove: (event) => _lookToward(event.position),
      onPointerUp: (_) => _releaseGaze(),
      onPointerCancel: (_) => _releaseGaze(),
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: Stack(
          children: [
            widget.child,
            Positioned(
              right: right,
              bottom: floor - belowFloor,
              child: AnimatedSlide(
                offset: !_entered
                    ? const Offset(0, 0.7)
                    : (_ducked ? const Offset(0, 0.62) : Offset.zero),
                duration: reduce
                    ? Duration.zero
                    : Duration(milliseconds: _entered && !_ducked ? 460 : 220),
                curve: _ducked ? Curves.easeOutCubic : Curves.easeOutBack,
                child: AnimatedOpacity(
                  opacity: _entered ? 1 : 0,
                  duration: reduce ? Duration.zero : Motion.base,
                  child: Semantics(
                    button: true,
                    label: context.tr(
                      '{0}, your study buddy. Opens the chat.',
                      [kBuddyName],
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _open,
                      child: SizedBox(
                        key: const ValueKey('pip-dock'),
                        width: math.max(width, 48),
                        height: height,
                        child: Mascot(key: _mascotKey, rig: _rig, width: width),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: right + width - 6,
              bottom: floor + height * 0.5,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.max(
                    120.0,
                    math.min(260.0, media.size.width - right - width - 32),
                  ),
                ),
                child: AnimatedSwitcher(
                  duration: reduce
                      ? Duration.zero
                      : const Duration(milliseconds: 260),
                  reverseDuration: reduce ? Duration.zero : Motion.quick,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      alignment: Alignment.bottomRight,
                      scale: Tween<double>(
                        begin: 0.86,
                        end: 1,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: bubble == null
                      ? const SizedBox.shrink()
                      : _SpeechBubble(
                          key: ValueKey(bubble.copy),
                          text: bubble.copy.of(context),
                          typing: _typing,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? cs.surfaceContainerHighest
                              : cs.surfaceContainerLowest,
                          onTap: () => _open(bubble.action),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What Pip is saying, with a tail toward Pip's head.
class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({
    super.key,
    required this.text,
    required this.typing,
    required this.color,
    required this.onTap,
  });

  final String text;
  final bool typing;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(18),
        topRight: Radius.circular(18),
        bottomLeft: Radius.circular(18),
        bottomRight: Radius.circular(5),
      ),
    );
    return Semantics(
      button: true,
      label: context.tr('{0} says: {1}', [kBuddyName, text]),
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: shape,
          shadows: [
            BoxShadow(
              color: cs.shadow.withValues(alpha: dark ? 0.4 : 0.12),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: color,
          shape: shape.copyWith(
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48, minWidth: 64),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: AnimatedSize(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.bottomRight,
                  child: typing
                      ? const TypingDots()
                      : Text(
                          text,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: cs.onSurface, height: 1.35),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three dots that rise in turn while Pip composes a line.
///
/// Shown only for as long as a line takes to arrive, so the loop always ends.
/// With reduce motion on, the dots sit still.
class TypingDots extends StatefulWidget {
  const TypingDots({super.key, this.size = 7});

  final double size;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      height: widget.size * 3.4,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : widget.size * 0.6),
                child: Transform.translate(
                  offset: Offset(
                    0,
                    -widget.size *
                        0.7 *
                        math.max(
                          0,
                          math.sin(
                            2 * math.pi * (_controller.value - i * 0.16),
                          ),
                        ),
                  ),
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.75),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
