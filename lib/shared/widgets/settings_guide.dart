import '../../core/localization/app_strings.dart';

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../core/services/permission_manager.dart';
import 'app_mark.dart';

/// What one Android settings page looks like, for the guide shown before it.
class SettingsGuide {
  const SettingsGuide._({
    required this.why,
    required this.listTitle,
    required this.toggleLabel,
    required this.steps,
    this.listSection,
    this.recording,
    this.still,
  });

  /// One sentence on what the access is for.
  final String why;

  /// The title of Android's list page, as drawn in the illustration.
  final String listTitle;

  /// An optional section label above the app list (Accessibility groups
  /// downloaded services under one).
  final String? listSection;

  /// The switch label on FocusForge's own page.
  final String toggleLabel;

  /// Three short steps, in order.
  final List<String> steps;

  /// A screen recording of the real Android pages, played in place of the
  /// sketch when there is one, and its last frame for reduced motion.
  final String? recording;
  final String? still;

  static const usageAccess = SettingsGuide._(
    why: 'Shield uses this to see which app is open and how long you used it today.',
    listTitle: 'Usage access',
    toggleLabel: 'Permit usage access',
    steps: [
      'Find FocusForge in the list and tap it',
      'Turn on Permit usage access',
      'Come back to FocusForge',
    ],
  );

  static const overlay = SettingsGuide._(
    why: 'Shield uses this to show its pause screen over the apps you block.',
    listTitle: 'Display over other apps',
    toggleLabel: 'Allow display over other apps',
    steps: [
      'Find FocusForge in the list and tap it',
      'Turn on Allow display over other apps',
      'Come back to FocusForge',
    ],
  );

  static const accessibility = SettingsGuide._(
    why: 'Shield uses this only to close YouTube Shorts and the home feed.',
    listTitle: 'Accessibility',
    listSection: 'Downloaded apps',
    toggleLabel: 'Use FocusForge',
    steps: [
      'Open Downloaded apps and tap FocusForge',
      'Turn on Use FocusForge, then tap Allow',
      'Come back to FocusForge',
    ],
    recording: 'assets/guides/accessibility.webp',
    still: 'assets/guides/accessibility_still.webp',
  );

  /// The guide for [permission], or null when it opens no settings list.
  static SettingsGuide? forPermission(AppPermission permission) =>
      switch (permission) {
        AppPermission.usageAccess => usageAccess,
        AppPermission.overlay => overlay,
        AppPermission.accessibility => accessibility,
        AppPermission.notifications => null,
      };
}

/// Shows how to switch the access on before Android's settings open.
///
/// Android has no dialog for these: people land in a long list and have to
/// find the app themselves. A short animation of exactly that — tap
/// FocusForge, turn on the switch — removes the guesswork. True when the user
/// taps Open settings; false when they close the sheet.
Future<bool> showSettingsGuide(
  BuildContext context,
  SettingsGuide guide,
) async =>
    await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => _GuideSheet(guide: guide),
    ) ??
    false;

class _GuideSheet extends StatelessWidget {
  const _GuideSheet({required this.guide});

  final SettingsGuide guide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        Gap.xl,
        0,
        Gap.xl,
        Gap.xl + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              context.tr("Turn on {0}", [context.tr(guide.listTitle)]),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: Gap.xs),
          Text(
            context.tr(guide.why),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Gap.lg),
          ExcludeSemantics(
            child: guide.recording == null
                ? _SettingsDemo(guide: guide)
                : _Recording(guide: guide),
          ),
          const SizedBox(height: Gap.lg),
          for (final (index, step) in guide.steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${index + 1}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: cs.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        context.tr(step),
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: Gap.sm),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr("Open settings")),
          ),
          const SizedBox(height: Gap.xs),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr("Not now")),
          ),
        ],
      ),
    );
  }
}

/// The recorded walk through Android's own pages, in a phone-shaped frame.
class _Recording extends StatelessWidget {
  const _Recording({required this.guide});

  final SettingsGuide guide;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final still = MediaQuery.disableAnimationsOf(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 380),
        child: AspectRatio(
          aspectRatio: 480 / 782,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(Radii.card),
              border: Border.all(color: cs.outlineVariant, width: 3),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.card - 3),
              child: Image.asset(
                still ? guide.still ?? guide.recording! : guide.recording!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A looping sketch of the two Android screens: the app list, where a finger
/// taps FocusForge, then FocusForge's page, where it turns the switch on.
/// With reduced motion it holds on the finished second screen.
class _SettingsDemo extends StatefulWidget {
  const _SettingsDemo({required this.guide});

  final SettingsGuide guide;

  @override
  State<_SettingsDemo> createState() => _SettingsDemoState();
}

class _SettingsDemoState extends State<_SettingsDemo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5200),
  );

  static const _plays = 3;
  int _played = 0;

  @override
  void initState() {
    super.initState();
    // Three plays, then it rests on the finished switch; a tap replays it.
    _loop.addStatusListener((status) {
      if (status != AnimationStatus.completed || !mounted) return;
      _played++;
      if (_played < _plays) {
        _loop.forward(from: 0);
      } else {
        _loop.value = 0.92;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _loop
        ..stop()
        ..value = 0.92;
    } else if (_played == 0 && !_loop.isAnimating) {
      _loop.forward(from: 0);
    }
  }

  void _replay() {
    if (MediaQuery.disableAnimationsOf(context)) return;
    _played = _plays - 1;
    _loop.forward(from: 0);
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: _replay,
      child: AspectRatio(
        aspectRatio: 1.35,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(Radii.card),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.card),
            child: AnimatedBuilder(
              animation: _loop,
              builder: (context, _) {
                final t = _loop.value;
                final secondScreen = t >= 0.5;
                return LayoutBuilder(
                  builder: (context, box) => Stack(
                    children: [
                      Positioned.fill(
                        child: secondScreen
                            ? _TogglePage(guide: widget.guide, on: t >= 0.78)
                            : _ListPage(
                                guide: widget.guide,
                                pressed: t >= 0.3 && t < 0.42,
                              ),
                      ),
                      Positioned(
                        top: Gap.sm,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: _StepPill(step: secondScreen ? 2 : 1),
                        ),
                      ),
                      _Finger(t: t, size: box.biggest),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _StepPill extends StatelessWidget {
  const _StepPill({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 4),
      decoration: BoxDecoration(
        color: cs.inverseSurface,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        context.tr("Step {0}", [step]),
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: cs.onInverseSurface, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ListPage extends StatelessWidget {
  const _ListPage({required this.guide, required this.pressed});

  final SettingsGuide guide;
  final bool pressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    Widget row(Widget icon, String label, {bool ours = false}) => Container(
      margin: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 7),
      decoration: BoxDecoration(
        color: ours && pressed ? cs.primary.withValues(alpha: .18) : null,
        borderRadius: BorderRadius.circular(Radii.tile),
      ),
      child: Row(
        children: [
          SizedBox.square(dimension: 24, child: icon),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: ours ? FontWeight.w600 : null,
              ),
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: cs.outline),
        ],
      ),
    );
    Widget placeholder(Color color) => DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
    );
    // A sketch, not a list: rows past the frame are clipped, never scrolled.
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageBar(title: context.tr(guide.listTitle)),
          if (guide.listSection != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, 2),
              child: Text(
                context.tr(guide.listSection!),
                style: theme.textTheme.labelSmall?.copyWith(color: cs.primary),
              ),
            ),
          row(placeholder(const Color(0xFF7FA9FF)), 'Calendar'),
          row(const AppMark(size: 24), 'FocusForge', ours: true),
          row(placeholder(const Color(0xFF9CCB7A)), 'Gallery'),
          row(placeholder(const Color(0xFFFFB37F)), 'Notes'),
        ],
      ),
    );
  }
}

class _TogglePage extends StatelessWidget {
  const _TogglePage({required this.guide, required this.on});

  final SettingsGuide guide;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PageBar(title: 'FocusForge'),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: Gap.md),
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.sm, Gap.sm),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(Radii.card),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.tr(guide.toggleLabel),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _MockSwitch(on: on),
            ],
          ),
        ),
      ],
    );
  }
}

class _PageBar extends StatelessWidget {
  const _PageBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Gap.md, 40, Gap.md, Gap.sm),
    child: Row(
      children: [
        Icon(
          Icons.arrow_back_rounded,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _MockSwitch extends StatelessWidget {
  const _MockSwitch({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: Motion.quick,
      width: 44,
      height: 26,
      padding: const EdgeInsets.all(3),
      alignment: on ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(
        color: on ? cs.primary : cs.outlineVariant,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: on ? cs.onPrimary : cs.surface,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// The pointing finger: glides to FocusForge's row, taps, then glides to the
/// switch and taps again.
class _Finger extends StatelessWidget {
  const _Finger({required this.t, required this.size});

  final double t;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final start = Offset(size.width * .72, size.height * .95);
    final row = Offset(size.width * .38, size.height * .53);
    final toggle = Offset(size.width * .87, size.height * .35);
    double ease(double a, double b) =>
        Curves.easeInOut.transform(((t - a) / (b - a)).clamp(0.0, 1.0));
    final Offset at;
    final bool tapping;
    if (t < 0.5) {
      at = Offset.lerp(start, row, ease(0.05, 0.28))!;
      tapping = t >= 0.3 && t < 0.42;
    } else {
      at = Offset.lerp(start, toggle, ease(0.55, 0.74))!;
      tapping = t >= 0.76 && t < 0.86;
    }
    return Positioned(
      left: at.dx - 6,
      top: at.dy - 4,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: tapping ? .86 : 1,
        child: Icon(
          Icons.touch_app_rounded,
          size: 34,
          color: Theme.of(context).colorScheme.onSurface,
          shadows: const [Shadow(blurRadius: 6, color: Colors.black26)],
        ),
      ),
    );
  }
}
