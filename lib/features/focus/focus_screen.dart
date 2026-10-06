import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/color_tokens.dart';
import '../../app/theme/glass_theme.dart';
import '../../core/data/mock_data.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/glass_nav_bar.dart';
import '../../shared/widgets/glass_surface.dart';
import '../../shared/widgets/progress_ring.dart';
import '../../shared/widgets/segmented_control.dart';

enum _Phase { focus, shortBreak, longBreak }

/// Tab 3 — the focus engine: Pomodoro / Countdown / Stopwatch, subject tagging,
/// an ambient mixer and a live session dock.
///
/// The timer is real: it ticks, advances segments, rolls into breaks and
/// completes a cycle. The dock is pinned above the navigation bar rather than
/// scrolling with the content, so the primary action is always reachable.
///
/// Audio playback lands in Phase 3 of the master plan, so the ambient tiles
/// currently only mix state.
class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key});

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> {
  int _mode = 0; // 0 pomodoro, 1 countdown, 2 stopwatch
  int _preset = 0;
  int _subject = 0;
  int _segment = 0;
  _Phase _phase = _Phase.focus;
  bool _running = false;
  Duration _remaining = const Duration(minutes: 25);
  Duration _elapsed = Duration.zero;
  Timer? _ticker;
  final Set<int> _ambient = {0};

  static const double _dockHeight = 90;

  PomodoroPreset get _p => DemoData.presets[_preset];

  Duration get _phaseTotal => switch (_phase) {
        _Phase.focus => Duration(minutes: _p.focus),
        _Phase.shortBreak => Duration(minutes: _p.shortBreak),
        _Phase.longBreak => Duration(minutes: _p.longBreak),
      };

  @override
  void initState() {
    super.initState();
    _remaining = Duration(minutes: _p.focus);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _toggle() {
    setState(() => _running = !_running);
    if (_running) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } else {
      _ticker?.cancel();
    }
  }

  void _tick() {
    if (!mounted) return;
    setState(() {
      if (_mode == 2) {
        _elapsed += const Duration(seconds: 1);
        return;
      }
      if (_remaining.inSeconds <= 1) {
        _advancePhase();
      } else {
        _remaining -= const Duration(seconds: 1);
      }
    });
  }

  /// Pomodoro rolls focus → break → focus, promoting to a long break after the
  /// last segment in the cycle.
  void _advancePhase() {
    if (_mode == 1) {
      _running = false;
      _ticker?.cancel();
      _remaining = Duration.zero;
      return;
    }
    if (_phase == _Phase.focus) {
      final last = _segment >= _p.segments - 1;
      _phase = last ? _Phase.longBreak : _Phase.shortBreak;
      _remaining = Duration(minutes: last ? _p.longBreak : _p.shortBreak);
    } else {
      _segment = (_segment + 1) % _p.segments;
      _phase = _Phase.focus;
      _remaining = Duration(minutes: _p.focus);
    }
  }

  void _reset() {
    _ticker?.cancel();
    setState(() {
      _running = false;
      _phase = _Phase.focus;
      _segment = 0;
      _remaining = Duration(minutes: _p.focus);
      _elapsed = Duration.zero;
    });
  }

  void _skip() => setState(_advancePhase);

  void _selectPreset(int i) {
    _ticker?.cancel();
    setState(() {
      _preset = i;
      _running = false;
      _phase = _Phase.focus;
      _segment = 0;
      _remaining = Duration(minutes: _p.focus);
    });
  }

  Color _phaseColor(GlassTokens t) => switch (_phase) {
        _Phase.focus => t.accentPrimary,
        _Phase.shortBreak => t.success,
        _Phase.longBreak => t.accentSecondary,
      };

  String get _phaseLabel => switch (_phase) {
        _Phase.focus => 'Focus Time',
        _Phase.shortBreak => 'Short Break',
        _Phase.longBreak => 'Long Break',
      };

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final accent = _phaseColor(t);
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    final shown = _mode == 2 ? _elapsed : _remaining;
    final total = _mode == 2 ? const Duration(minutes: 60) : _phaseTotal;
    final progress = _mode == 2
        ? (_elapsed.inSeconds / total.inSeconds).clamp(0.0, 1.0)
        : 1 - (_remaining.inSeconds / total.inSeconds).clamp(0.0, 1.0);

    final dockBottom =
        GlassNavBar.height + GlassNavBar.bottomInset + 10 + safeBottom;

    return Stack(
      children: [
        Positioned.fill(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              Gap.lg + 4,
              MediaQuery.paddingOf(context).top + Gap.lg,
              Gap.lg + 4,
              dockBottom + _dockHeight + Gap.lg,
            ),
            children: [
              Text('Focus Engine', style: context.type.headlineMedium),
              const SizedBox(height: 3),
              Text(
                'Deep work, measured',
                style: context.type.bodySmall?.copyWith(color: t.textTertiary),
              ),
              const SizedBox(height: Gap.xl),

              SegmentedControl(
                options: const ['Pomodoro', 'Countdown', 'Stopwatch'],
                index: _mode,
                onChanged: (i) {
                  _reset();
                  setState(() => _mode = i);
                },
              ),
              const SizedBox(height: Gap.lg),

              if (_mode != 2)
                Center(
                  child: GlassPill(
                    onTap: () => _showPresetSheet(context),
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.lg,
                      vertical: Gap.sm,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_p.icon, size: 14, color: accent),
                        const SizedBox(width: 7),
                        Text(_p.name),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.expand_more_rounded,
                          size: 16,
                          color: t.textTertiary,
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: Gap.lg),

              // Subject tags --------------------------------------------------
              EdgeFade(
                trailing: 32,
                child: SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: DemoData.subjects.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(width: Gap.sm),
                    itemBuilder: (context, i) {
                      if (i == DemoData.subjects.length) {
                        return const GlassPill(
                          padding: EdgeInsets.symmetric(
                            horizontal: Gap.md,
                            vertical: 8,
                          ),
                          child: Text('+ Add', style: TextStyle(fontSize: 12.5)),
                        );
                      }
                      final s = DemoData.subjects[i];
                      return GlassPill(
                        selected: i == _subject,
                        accent: s.color,
                        onTap: () => setState(() => _subject = i),
                        padding: const EdgeInsets.symmetric(
                          horizontal: Gap.md,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: s.color,
                                boxShadow: [
                                  BoxShadow(
                                    color: s.color.withValues(alpha: 0.7),
                                    blurRadius: 7,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              s.name,
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: Gap.xl),

              // Timer ---------------------------------------------------------
              Center(
                child: ProgressRing(
                  value: progress,
                  size: 208,
                  stroke: 11,
                  ticks: 60,
                  colors: [
                    accent,
                    Color.lerp(accent, t.accentSecondary, 0.7)!,
                  ],
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatClock(shown),
                        style: context.type.displayLarge?.copyWith(
                          fontSize: 52,
                          height: 1.02,
                          letterSpacing: -2.2,
                        ),
                      ),
                      const SizedBox(height: Gap.xs),
                      Text(
                        _phaseLabel,
                        style: context.type.labelLarge?.copyWith(
                          color: accent,
                          fontSize: 12.5,
                          letterSpacing: 0.3,
                        ),
                      ),
                      if (_mode == 0) ...[
                        const SizedBox(height: Gap.md),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < _p.segments; i++) ...[
                              if (i > 0) const SizedBox(width: 6),
                              _SegmentDot(
                                done: i < _segment,
                                current: i == _segment && _phase == _Phase.focus,
                                color: accent,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Gap.xl),

              // Ambient mixer --------------------------------------------------
              const SectionHeader(
                title: 'Ambient mix',
                icon: Icons.graphic_eq_rounded,
              ),
              GlassPanel(
                radius: Radii.card,
                padding: const EdgeInsets.all(Gap.md),
                child: GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: Gap.md,
                  crossAxisSpacing: Gap.md,
                  childAspectRatio: 2.5,
                  children: [
                    for (var i = 0; i < DemoData.ambient.length; i++)
                      _AmbientTile(
                        tile: DemoData.ambient[i],
                        active: _ambient.contains(i),
                        onTap: () => setState(() {
                          if (!_ambient.remove(i)) _ambient.add(i);
                        }),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.lg),

              // Session strip ---------------------------------------------------
              Row(
                children: [
                  Expanded(
                    child: _InfoCapsule(
                      icon: Icons.local_fire_department_rounded,
                      color: t.gold,
                      value: 'Day ${DemoData.streakDays}',
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: _InfoCapsule(
                      icon: Icons.timer_rounded,
                      color: t.accentPrimary,
                      value: formatMinutes(DemoData.focusMinutesToday),
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: _InfoCapsule(
                      icon: Icons.check_circle_rounded,
                      color: t.success,
                      value: '${DemoData.sessionCountToday} today',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Pinned session dock --------------------------------------------------
        Positioned(
          left: Gap.lg + 4,
          right: Gap.lg + 4,
          bottom: dockBottom,
          child: GlassPanel(
            radius: Radii.pill,
            blur: 18,
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.lg,
              vertical: Gap.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Pressable(
                    onTap: _reset,
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.refresh_rounded,
                            size: 16,
                            color: t.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Reset',
                            style: context.type.labelLarge?.copyWith(
                              color: t.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Pressable(
                  onTap: _toggle,
                  scale: 0.92,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          accent,
                          Color.lerp(accent, t.accentSecondary, 0.7)!,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.50),
                          blurRadius: 28,
                          spreadRadius: -3,
                        ),
                        BoxShadow(
                          color: accent.withValues(alpha: 0.22),
                          blurRadius: 52,
                          spreadRadius: -6,
                        ),
                      ],
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.42),
                        width: 1.2,
                      ),
                    ),
                    child: Icon(
                      _running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 32,
                      color: const Color(0xFF08101F),
                    ),
                  ),
                ),
                Expanded(
                  child: Pressable(
                    onTap: _mode == 0 ? _skip : null,
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Skip',
                            style: context.type.labelLarge?.copyWith(
                              color: _mode == 0
                                  ? t.textSecondary
                                  : t.textTertiary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.skip_next_rounded,
                            size: 16,
                            color: _mode == 0
                                ? t.textSecondary
                                : t.textTertiary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showPresetSheet(BuildContext context) {
    final t = context.glass;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: GlassPanel(
          radius: Radii.hero,
          blur: 24,
          padding: const EdgeInsets.all(Gap.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.textTertiary,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                ),
              ),
              const SizedBox(height: Gap.lg),
              Text('Pomodoro presets', style: context.type.titleMedium),
              const SizedBox(height: Gap.sm),
              for (var i = 0; i < DemoData.presets.length; i++)
                Pressable(
                  onTap: () {
                    _selectPreset(i);
                    Navigator.of(context).pop();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Gap.md),
                    child: Row(
                      children: [
                        GlassIconBadge(
                          icon: DemoData.presets[i].icon,
                          color: t.accentPrimary,
                          size: 38,
                          radius: 11,
                          glow: i == _preset ? 0.6 : 0,
                        ),
                        const SizedBox(width: Gap.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                DemoData.presets[i].name,
                                style: context.type.titleSmall,
                              ),
                              const SizedBox(height: 1),
                              Text(
                                '${DemoData.presets[i].focus}m focus · '
                                '${DemoData.presets[i].shortBreak}m break · '
                                '${DemoData.presets[i].segments} segments',
                                style: context.type.labelSmall,
                              ),
                            ],
                          ),
                        ),
                        if (i == _preset)
                          Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: t.accentPrimary,
                          ),
                      ],
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
    final t = context.glass;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: current ? 18 : 7,
      height: 7,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.pill),
        color: done || current ? color : t.track,
        boxShadow: current
            ? [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 10)]
            : null,
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

  final AmbientTile tile;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.glass;

    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: Gap.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.tile),
          color: active
              ? tile.color.withValues(alpha: 0.20)
              : t.glassL2At(0.55),
          border: Border.all(
            color: active ? tile.color.withValues(alpha: 0.72) : t.glassL2Border,
            width: active ? 1.3 : 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: tile.color.withValues(alpha: 0.34),
                    blurRadius: 20,
                    spreadRadius: -4,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              tile.icon,
              size: 17,
              color: active ? tile.color : t.textTertiary,
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(
                tile.name,
                style: context.type.labelMedium?.copyWith(
                  color: active ? t.textPrimary : t.textSecondary,
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
    );
  }
}

class _InfoCapsule extends StatelessWidget {
  const _InfoCapsule({
    required this.icon,
    required this.color,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String value;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      level: 2,
      radius: Radii.item,
      sheen: false,
      padding: const EdgeInsets.symmetric(vertical: Gap.md, horizontal: Gap.sm),
      child: Column(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(height: 5),
          Text(
            value,
            style: context.type.labelMedium?.copyWith(
              color: context.glass.textPrimary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
