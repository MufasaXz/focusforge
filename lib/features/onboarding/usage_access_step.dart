import '../../core/localization/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/services/permission_manager.dart';
import '../../shared/widgets/icon_badge.dart';
import 'onboarding_chrome.dart';

/// The optional Android usage disclosure shown at the end of first-run setup.
///
/// This is deliberately separate from the broader App Access screen: setup
/// only asks about Usage Access, while overlay and Accessibility are explained
/// at the point where the user turns on the feature that needs them.
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

  Future<void> _allow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
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
    final granted = _status == PermissionOutcome.granted;

    return StepScaffold(
      title: context.tr("Screen-time access"),
      eyebrow: context.tr("OPTIONAL ACCESS"),
      subtitle: supported
          ? context.tr(
              "Optional access for app boundaries and screen-time totals.",
            )
          : context.tr(
              "This device does not need any extra access for the focus timer.",
            ),
      primaryLabel: context.tr("Continue"),
      onPrimary: widget.onNext,
      primaryBusy: _busy,
      secondary: supported && !granted
          ? TextButton.icon(
              onPressed: _busy ? null : widget.onNext,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text(context.tr("Continue without access")),
            )
          : null,
      footnote: supported
          ? context.tr("Change this anytime in Android Settings.")
          : null,
      children: [
        if (supported) ...[
          _AccessPreview(
            icon: granted
                ? Icons.check_circle_outline_rounded
                : Icons.query_stats_rounded,
            color: granted ? cs.tertiary : cs.primary,
            title: granted
                ? context.tr("Usage Access is on")
                : context.tr("Recognize selected apps"),
            body: granted
                ? context.tr(
                    "App detection and local screen-time totals are ready.",
                  )
                : context.tr(
                    "Detect when a selected app is open and measure time spent in apps.",
                  ),
          ),
          const SizedBox(height: Gap.md),
          _PrivacyNote(color: cs.tertiary),
          const SizedBox(height: Gap.xl),
          FilledButton.icon(
            onPressed: _busy || granted ? null : _allow,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.settings_outlined),
            label: Text(
              granted
                  ? context.tr("Enabled")
                  : context.tr("Allow usage access"),
            ),
          ),
        ] else
          _AccessPreview(
            icon: Icons.check_circle_outline_rounded,
            color: cs.tertiary,
            title: context.tr("You are ready to focus"),
            body: context.tr(
              "Your timer works without any extra device access.",
            ),
          ),
      ],
    );
  }
}

class _AccessPreview extends StatelessWidget {
  const _AccessPreview({
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
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(Radii.card),
      border: Border.all(
        color: Theme.of(context).colorScheme.outlineVariant
            .withValues(alpha: .7),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(Gap.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, color: color, size: 44, radius: Radii.tile),
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
  );
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(Icons.lock_outline_rounded, size: 16, color: color),
      const SizedBox(width: Gap.sm),
      Expanded(
        child: Text(
          context.tr(
            "App names and time totals stay on this device. Message content is never read.",
          ),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ),
    ],
  );
}
