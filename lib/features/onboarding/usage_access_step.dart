import '../../core/localization/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/providers/usage_providers.dart';
import '../../core/services/permission_manager.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/app_list_disclosure.dart';
import '../../shared/widgets/icon_badge.dart';
import 'onboarding_chrome.dart';

/// The optional app-list disclosure at the end of first-run setup.
///
/// This step *is* the prominent disclosure Google Play's User Data policy asks
/// for: it says what is read, for which feature and when, in the normal flow
/// of the app, before anything is read. Its one primary action is the
/// affirmative consent — "Agree and allow" records the agreement and only then
/// opens Android's Usage access page — and "Not now" moves on with nothing
/// read and nothing granted.
///
/// Overlay and Accessibility are not asked for here; they are explained at
/// the point where the user turns on the feature that needs them.
class UsageAccessStep extends ConsumerStatefulWidget {
  const UsageAccessStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  ConsumerState<UsageAccessStep> createState() => _UsageAccessStepState();
}

class _UsageAccessStepState extends ConsumerState<UsageAccessStep>
    with WidgetsBindingObserver {
  static const _manager = PermissionManager();
  PermissionOutcome? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final status = await _manager
        .check(AppPermission.usageAccess)
        .timeout(
          const Duration(seconds: 4),
          onTimeout: () => PermissionOutcome.denied,
        );
    if (mounted) setState(() => _status = status);
  }

  /// The consent and the permission, in that order. The tap on the button
  /// beneath the disclosure is the agreement; the Android page that follows
  /// is a second, separate yes.
  Future<void> _allow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(appListConsentProvider.notifier).set(true);
      // Already on from an earlier visit to Android settings: the agreement
      // was the only missing piece, so there is no page to send them to.
      if (_status == PermissionOutcome.granted) return;
      final status = await _manager.request(AppPermission.usageAccess);
      if (!mounted) return;
      setState(() => _status = status);
      if (status == PermissionOutcome.openedSettings) {
        showAppSnack(
          context,
          tr("Choose FocusForge in Usage access, turn it on, then come back."),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final supported = _manager.supports(AppPermission.usageAccess);
    final consent = ref.watch(appListConsentProvider);
    final granted = _status == PermissionOutcome.granted;
    final done = !supported || (granted && consent);

    return StepScaffold(
      title: supported
          ? context.tr("Limit distracting apps")
          : context.tr("You are ready to focus"),
      eyebrow: context.tr("OPTIONAL ACCESS"),
      subtitle: supported
          ? null
          : context.tr("Your timer works without any extra device access."),
      primaryLabel: done
          ? context.tr("Continue")
          : consent
          ? context.tr("Allow usage access")
          : context.tr("Agree and allow"),
      onPrimary: done ? widget.onNext : _allow,
      primaryBusy: _busy,
      secondary: done
          ? null
          : TextButton(
              onPressed: _busy ? null : widget.onNext,
              child: Text(context.tr("Not now")),
            ),
      // No footnote: the disclosure's last point already says how to take
      // this back, and every line the footer takes is a line of the
      // disclosure pushed below the fold.
      children: [
        if (supported) ...[
          const _ScreenTimePreview(),
          const SizedBox(height: Gap.md),
          if (done)
            _StatusCard(
              icon: Icons.check_circle_outline_rounded,
              color: cs.tertiary,
              title: context.tr("Usage Access is on"),
              body: context.tr(
                "App detection and local screen-time totals are ready.",
              ),
            )
          else ...[
            DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(Radii.card),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: .7),
                ),
              ),
              child: const Padding(
                padding: EdgeInsets.all(Gap.lg),
                child: AppListDisclosureBody(),
              ),
            ),
            if (consent) ...[
              const SizedBox(height: Gap.md),
              _StatusCard(
                icon: Icons.settings_outlined,
                color: cs.primary,
                title: context.tr("Usage access"),
                body: context.tr(
                  "Choose FocusForge in Usage access, turn it on, then come back.",
                ),
              ),
            ],
          ],
        ],
      ],
    );
  }
}

/// What the access is for, drawn rather than described: three apps with a
/// day's time on them, the busiest one carrying a limit. Decorative — the
/// disclosure beneath it is the text that counts, so screen readers skip it.
class _ScreenTimePreview extends StatelessWidget {
  const _ScreenTimePreview();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = [
      (Icons.smart_display_rounded, cs.error, 72, true),
      (Icons.forum_rounded, cs.primary, 41, false),
      (Icons.menu_book_rounded, cs.tertiary, 18, false),
    ];
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: .7)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.lg,
            vertical: Gap.sm,
          ),
          child: Column(
            children: [
              for (final (icon, color, minutes, limited) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                  child: Row(
                    children: [
                      IconBadge(icon: icon, color: color, size: 30, radius: 9),
                      const SizedBox(width: Gap.md),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.pill),
                          child: Stack(
                            children: [
                              Container(
                                height: 8,
                                color: cs.surfaceContainerHighest,
                              ),
                              FractionallySizedBox(
                                widthFactor: minutes / 90,
                                child: Container(
                                  height: 8,
                                  color: color.withValues(alpha: .75),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: Gap.md),
                      SizedBox(
                        width: 56,
                        child: Text(
                          formatMinutes(minutes),
                          textAlign: TextAlign.end,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                      ),
                      const SizedBox(width: Gap.sm),
                      Icon(
                        limited
                            ? Icons.hourglass_bottom_rounded
                            : Icons.circle_outlined,
                        size: 16,
                        color: limited ? cs.error : cs.outlineVariant,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: .08),
          Theme.of(context).colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBadge(icon: icon, color: color, size: 40, radius: Radii.tile),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: Gap.xs),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
