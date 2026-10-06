import '../../app/theme/app_theme.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/shield.dart';
import '../../core/providers/shield_providers.dart';
import '../../shared/widgets/glass_page.dart';
import '../../shared/widgets/glass_surface.dart';
import '../../shared/widgets/glass_toggle.dart';
import 'settings_support.dart';

/// Strict Mode — the commitment device.
///
/// Everything on this screen exists to make the decision expensive at the
/// moment it matters: the window is chosen up front, the exits are named, and
/// both starting and stopping require typing the commitment phrase. The slider
/// only commits on release so a drag does not write to disk thirty times.
class StrictModeScreen extends ConsumerStatefulWidget {
  const StrictModeScreen({super.key});

  @override
  ConsumerState<StrictModeScreen> createState() => _StrictModeScreenState();
}

class _StrictModeScreenState extends ConsumerState<StrictModeScreen> {
  /// Live slider position while a drag is in flight; null when idle.
  double? _draggingHours;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final config = ref.watch(strictModeProvider);
    final hours = _draggingHours ?? config.durationMinutes / 60;

    return GlassPage(
      title: 'Strict Mode',
      subtitle: config.enabled ? 'Locked in' : 'Not active',
      trailing: GlassPill(
        selected: config.enabled,
        accent: config.enabled ? cs.error : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Text(
          config.enabled ? 'Active' : 'Off',
          style: const TextStyle(fontSize: 12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _WarningPanel(),
          const SizedBox(height: Gap.xl),
          GlassSection(
            title: 'Duration',
            footnote: 'The lock holds for the whole window once it starts.',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Gap.md,
                  Gap.md,
                  Gap.md,
                  Gap.xs,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text('Lock length', style: Theme.of(context).textTheme.bodyMedium),
                        const Spacer(),
                        Text(
                          _formatWindow(hours),
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: cs.error,
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: cs.error,
                        thumbColor: cs.error,
                        inactiveTrackColor: cs.surfaceContainerHighest,
                        overlayColor: cs.error.withValues(alpha: 0.14),
                      ),
                      child: Slider(
                        value: hours.clamp(
                          StrictModeConfig.minHours,
                          StrictModeConfig.maxHours,
                        ),
                        min: StrictModeConfig.minHours,
                        max: StrictModeConfig.maxHours,
                        // 31 steps of 15 minutes covers the full 15m–8h range.
                        divisions: 31,
                        label: _formatWindow(hours),
                        onChanged: (v) => setState(() => _draggingHours = v),
                        onChangeEnd: _commitDuration,
                      ),
                    ),
                    Row(
                      children: [
                        Text('15 min', style: Theme.of(context).textTheme.labelSmall),
                        const Spacer(),
                        Text('8 h', style: Theme.of(context).textTheme.labelSmall),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          GlassSection(
            title: 'Emergency unlock',
            footnote: 'The window is the commitment; this is the way out.',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Gap.md,
                  Gap.sm,
                  Gap.md,
                  Gap.md,
                ),
                child: Column(
                  children: [
                    _Step(
                      number: 1,
                      text:
                          'Type “${config.commitmentPhrase}” to unlock the '
                          'next step.',
                    ),
                    _Step(
                      number: 2,
                      text:
                          'Wait ${config.cooldownSeconds} seconds without '
                          'touching the screen.',
                    ),
                    const _Step(
                      number: 3,
                      text:
                          'Confirm a second time. Only then does the lock '
                          'release.',
                    ),
                  ],
                ),
              ),
            ],
          ),
          GlassSection(
            title: 'Always allowed',
            footnote: 'These stay reachable even while Strict Mode is on.',
            children: [
              _AllowRow(
                title: 'Phone calls',
                subtitle: 'Incoming and outgoing',
                icon: Icons.call_rounded,
                value: config.allowCalls,
                onChanged: (v) => _write(config.copyWith(allowCalls: v)),
              ),
              _AllowRow(
                title: 'Emergency services',
                subtitle: 'Always reachable, whatever the mode',
                icon: Icons.health_and_safety_rounded,
                value: config.allowEmergency,
                onChanged: (v) => _write(config.copyWith(allowEmergency: v)),
              ),
              _AllowRow(
                title: 'Maps and navigation',
                subtitle: 'Directions while you are out',
                icon: Icons.map_rounded,
                value: config.allowMaps,
                onChanged: (v) => _write(config.copyWith(allowMaps: v)),
                showDivider: false,
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          GlassActionButton(
            label: config.enabled ? 'End Strict Mode' : 'Activate Strict Mode',
            icon: config.enabled ? Icons.lock_open_rounded : Icons.lock_rounded,
            destructive: config.enabled,
            onTap: () => _confirmToggle(config),
          ),
        ],
      ),
    );
  }

  void _commitDuration(double hours) {
    setState(() => _draggingHours = null);
    ref.read(strictModeProvider.notifier).setDuration((hours * 60).round());
  }

  void _write(StrictModeConfig next) =>
      ref.read(strictModeProvider.notifier).update(next);

  /// Runs the three-step commitment flow in one modal and only writes when the
  /// final confirm comes back true. The phrase gate alone was theatre: the
  /// cooldown is enforced inside the sheet, so a user who types the phrase and
  /// confirms immediately still has to sit through it.
  Future<void> _confirmToggle(StrictModeConfig config) async {
    final activating = !config.enabled;
    final window = _formatWindow(config.durationMinutes / 60);

    final confirmed = await showGlassDialog<bool>(
      context: context,
      // Dismissal is the escape hatch. Leaving the sheet at any point is a
      // cancel, and a cancel never touches the stored config.
      barrierDismissible: true,
      builder: (_) => _StrictCommitmentSheet(
        config: config,
        activating: activating,
        window: window,
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref.read(strictModeProvider.notifier).setEnabled(activating);
    if (!mounted) return;
    showGlassSnack(
      context,
      activating ? 'Strict Mode is on for $window.' : 'Strict Mode ended.',
    );
  }
}

/// The three-step commitment sheet.
///
/// One modal for all three steps so the user never loses the thread between
/// them: type the phrase, wait out a countdown the sheet actually enforces,
/// then confirm. Nothing is persisted until the sheet returns true — every
/// exit path (Cancel, barrier tap, route pop) disposes the sheet, which
/// cancels the ticker and leaves the config untouched.
class _StrictCommitmentSheet extends StatefulWidget {
  const _StrictCommitmentSheet({
    required this.config,
    required this.activating,
    required this.window,
  });

  final StrictModeConfig config;
  final bool activating;
  final String window;

  @override
  State<_StrictCommitmentSheet> createState() => _StrictCommitmentSheetState();
}

enum _CommitmentStage { phrase, cooldown, ready }

class _StrictCommitmentSheetState extends State<_StrictCommitmentSheet> {
  final _controller = TextEditingController();
  Timer? _timer;
  DateTime? _deadline;
  _CommitmentStage _stage = _CommitmentStage.phrase;
  Duration _remaining = Duration.zero;

  Duration get _cooldown => Duration(seconds: widget.config.cooldownSeconds);

  /// Trimmed and case-insensitive: the friction is meant to be the wait and
  /// the intent, not a spelling test.
  bool get _phraseMatches =>
      _controller.text.trim().toLowerCase() ==
      widget.config.commitmentPhrase.trim().toLowerCase();

  @override
  void dispose() {
    // Popping the route is a cancel path, so the ticker must die here or a
    // dismissed sheet keeps rebuilding off-screen.
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startCooldown() {
    final total = _cooldown;
    FocusScope.of(context).unfocus();
    setState(() {
      _stage = _CommitmentStage.cooldown;
      _remaining = total;
    });
    _deadline = DateTime.now().add(total);
    // Deadline-based rather than decrementing a counter: a late tick (jank, a
    // backgrounded app) then corrects instead of stretching the wait.
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  void _tick() {
    final left = _deadline!.difference(DateTime.now());
    if (left > Duration.zero) {
      setState(() => _remaining = left);
      return;
    }
    _timer?.cancel();
    _timer = null;
    setState(() {
      _remaining = Duration.zero;
      _stage = _CommitmentStage.ready;
    });
  }

  void _dismiss() {
    _timer?.cancel();
    _timer = null;
    Navigator.of(context).pop(false);
  }

  int get _secondsLeft => (_remaining.inMilliseconds / 1000).ceil();

  String get _confirmLabel => switch (_stage) {
    _CommitmentStage.phrase => 'Continue',
    _CommitmentStage.cooldown => 'Wait ${_secondsLeft}s',
    _CommitmentStage.ready => widget.activating ? 'Lock it in' : 'End the lock',
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Ending early is the destructive direction — the commitment being broken
    // — so the accent swaps with the verb, matching the page button.
    final accent = widget.activating ? cs.primary : cs.error;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            GlassIconBadge(
              icon: widget.activating
                  ? Icons.lock_rounded
                  : Icons.lock_open_rounded,
              color: accent,
              size: 40,
              radius: 12,
              glow: 0.3,
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(
                widget.activating ? 'Start Strict Mode?' : 'End Strict Mode?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.md),
        Text(
          widget.activating
              ? 'Focus is locked for ${widget.window}. Blocks cannot be '
                    'changed and the app cannot be uninstalled until the '
                    'window ends.'
              : 'Ending early is the emergency unlock. The lock releases only '
                    'after all three steps are done.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: Gap.lg),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: switch (_stage) {
            _CommitmentStage.phrase => _PhraseStep(
              key: const ValueKey('phrase'),
              controller: _controller,
              phrase: widget.config.commitmentPhrase,
              accent: accent,
              onChanged: () => setState(() {}),
            ),
            _CommitmentStage.cooldown => _CooldownStep(
              key: const ValueKey('cooldown'),
              remaining: _remaining,
              total: _cooldown,
              accent: accent,
            ),
            _CommitmentStage.ready => _ReadyStep(
              key: const ValueKey('ready'),
              accent: accent,
              activating: widget.activating,
            ),
          },
        ),
        const SizedBox(height: Gap.xl),
        Row(
          children: [
            Expanded(
              child: _SheetButton(
                label: 'Cancel',
                accent: cs.onSurfaceVariant,
                onTap: _dismiss,
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: _SheetButton(
                label: _confirmLabel,
                accent: accent,
                filled: true,
                // Disabled through the whole cooldown — the final confirm is
                // the only path that returns true, and so the only path that
                // reaches setEnabled.
                onTap: switch (_stage) {
                  _CommitmentStage.phrase =>
                    _phraseMatches ? _startCooldown : null,
                  _CommitmentStage.cooldown => null,
                  _CommitmentStage.ready => () => Navigator.of(
                    context,
                  ).pop(true),
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PhraseStep extends StatelessWidget {
  const _PhraseStep({
    super.key,
    required this.controller,
    required this.phrase,
    required this.accent,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String phrase;
  final Color accent;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Step 1 of 3 — type “$phrase” to continue.',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: Gap.sm),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.item),
            color: cs.surfaceContainer.withValues(alpha: 0.5),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onChanged: (_) => onChanged(),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 15),
            cursorColor: accent,
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: 'Type the phrase',
              hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: Gap.md,
                vertical: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CooldownStep extends StatelessWidget {
  const _CooldownStep({
    super.key,
    required this.remaining,
    required this.total,
    required this.accent,
  });

  final Duration remaining;
  final Duration total;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Step 2 of 3 — wait without touching the screen.',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: Gap.lg),
        _CooldownRing(remaining: remaining, total: total, color: accent),
        const SizedBox(height: Gap.lg),
        Text(
          'The confirm unlocks when the ring empties. Dismissing this sheet '
          'cancels it.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ReadyStep extends StatelessWidget {
  const _ReadyStep({super.key, required this.accent, required this.activating});

  final Color accent;
  final bool activating;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassIconBadge(
          icon: Icons.check_rounded,
          color: accent,
          size: 48,
          radius: 14,
          glow: 0.3,
        ),
        const SizedBox(height: Gap.md),
        Text(
          'Step 3 of 3 — the wait is done. Confirm to '
          '${activating ? 'start the lock' : 'release the lock'}.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

/// Depleting countdown ring with the remaining seconds in the middle.
class _CooldownRing extends StatelessWidget {
  const _CooldownRing({
    required this.remaining,
    required this.total,
    required this.color,
  });

  final Duration remaining;
  final Duration total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fraction = total <= Duration.zero
        ? 0.0
        : (remaining.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final seconds = (remaining.inMilliseconds / 1000).ceil();

    return Semantics(
      label: 'Cooldown',
      value: '$seconds seconds remaining',
      child: ExcludeSemantics(
        child: SizedBox(
          width: 128,
          height: 128,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _CooldownRingPainter(
                    fraction: fraction,
                    track: cs.surfaceContainerHighest,
                    color: color,
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$seconds',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontSize: 34,
                      height: 1.1,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'seconds',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
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
}

class _CooldownRingPainter extends CustomPainter {
  const _CooldownRingPainter({
    required this.fraction,
    required this.track,
    required this.color,
  });

  /// 1 = full ring, 0 = empty.
  final double fraction;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final arcRect = (Offset.zero & size).deflate(stroke / 2);

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, base);

    if (fraction <= 0) return;

    final sweep = math.pi * 2 * fraction;
    // A blurred copy under the arc gives the ring the same bloom the rest of
    // the glass system uses for accents.
    final bloom = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 3 / 2,
        colors: [color, color.withValues(alpha: 0.55)],
      ).createShader(arcRect);

    canvas.drawArc(arcRect, -math.pi / 2, sweep, false, bloom);
    canvas.drawArc(arcRect, -math.pi / 2, sweep, false, arc);
  }

  @override
  bool shouldRepaint(_CooldownRingPainter old) =>
      old.fraction != fraction || old.track != track || old.color != color;
}

/// Dialog-sized action button. Mirrors the shared dialog button in
/// `settings_support.dart`, which is private to that file.
class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.accent,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final Color accent;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onTap != null;

    return Pressable(
      onTap: onTap,
      scale: 0.96,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.pill),
          color: filled
              ? accent.withValues(alpha: enabled ? 0.22 : 0.08)
              : cs.surfaceContainer.withValues(alpha: 0.5),
          border: Border.all(
            color: filled
                ? accent.withValues(alpha: enabled ? 0.62 : 0.20)
                : cs.outlineVariant,
          ),
        ),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontSize: 13.5,
              color: filled
                  ? (enabled ? accent : cs.onSurfaceVariant)
                  : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _WarningPanel extends StatelessWidget {
  const _WarningPanel();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassPanel(
      radius: Radii.card,
      accent: cs.error,
      glowStrength: 0.35,
      padding: const EdgeInsets.all(Gap.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassIconBadge(
            icon: Icons.warning_amber_rounded,
            color: cs.error,
            size: 42,
            radius: 12,
            glow: 0.35,
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Strict Mode locks your phone during focus.',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  'You can’t change blocks or uninstall FocusForge until the '
                  'timer expires.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.error.withValues(alpha: 0.16),
              border: Border.all(color: cs.error.withValues(alpha: 0.5)),
            ),
            child: Text(
              '$number',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontSize: 11.5,
                color: cs.error,
              ),
            ),
          ),
          const SizedBox(width: Gap.md),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _AllowRow extends StatelessWidget {
  const _AllowRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
    this.showDivider = true,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassRow(
      title: title,
      subtitle: subtitle,
      icon: icon,
      showDivider: showDivider,
      trailing: GlassToggle(
        value: value,
        accent: cs.tertiary,
        semanticLabel: title,
        onChanged: onChanged,
      ),
    );
  }
}

/// "15 min", "2 h", "2 h 30 min" — minutes only when they are the whole story.
String _formatWindow(double hours) {
  final total = (hours * 60).round();
  final h = total ~/ 60;
  final m = total % 60;
  if (h == 0) return '$m min';
  if (m == 0) return '$h h';
  return '$h h $m min';
}
