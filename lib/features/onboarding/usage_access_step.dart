import '../../core/localization/app_strings.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/providers/usage_providers.dart';
import '../../core/services/permission_manager.dart';
import '../../shared/widgets/app_list_disclosure.dart';
import '../../shared/widgets/settings_guide.dart';
import 'onboarding_chrome.dart';

/// The optional permissions step at the end of first-run setup.
///
/// A short checklist, taken one row at a time: the row to do next carries an
/// Allow button, rows after it wait, and finished rows show a tick. Usage
/// access first shows the app-list disclosure — what is read, why, where it
/// goes — and records the agreement before anything is read. Usage access and
/// overlay then show a guide of the Android page they open, since Android
/// offers no dialog for either. Notifications use Android's own prompt.
///
/// Accessibility is never asked for here; it is explained and requested when
/// the user turns on a YouTube filter. "Continue without app blocking" moves on
/// with nothing agreed and nothing opened.
class UsageAccessStep extends ConsumerStatefulWidget {
  const UsageAccessStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  ConsumerState<UsageAccessStep> createState() => _UsageAccessStepState();
}

class _UsageAccessStepState extends ConsumerState<UsageAccessStep>
    with WidgetsBindingObserver {
  static const _manager = PermissionManager();
  static const _order = [
    AppPermission.usageAccess,
    AppPermission.overlay,
    AppPermission.notifications,
  ];

  final _status = <AppPermission, PermissionOutcome>{};
  final _timers = <Timer>{};
  AppPermission? _busy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final timer in _timers) {
      timer.cancel();
    }
    super.dispose();
  }

  /// [PermissionManager.check], answered as denied after four seconds. The
  /// fallback timer is cancelled with the screen, so a platform that never
  /// answers leaves nothing running behind it.
  Future<PermissionOutcome> _check(AppPermission permission) {
    final answer = Completer<PermissionOutcome>();
    late final Timer timer;
    timer = Timer(const Duration(seconds: 4), () {
      _timers.remove(timer);
      if (!answer.isCompleted) answer.complete(PermissionOutcome.denied);
    });
    _timers.add(timer);
    _manager.check(permission).then((outcome) {
      timer.cancel();
      _timers.remove(timer);
      if (!answer.isCompleted) answer.complete(outcome);
    });
    return answer.future;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final answers = await Future.wait(_order.map(_check));
    if (!mounted) return;
    setState(() {
      for (final (index, permission) in _order.indexed) {
        _status[permission] = answers[index];
      }
    });
  }

  bool _done(AppPermission permission) {
    final granted = _status[permission] == PermissionOutcome.granted;
    // Usage access only counts once the app-list agreement is recorded too.
    return permission == AppPermission.usageAccess
        ? granted && ref.read(appListConsentProvider)
        : granted;
  }

  Future<void> _allow(AppPermission permission) async {
    if (_busy != null) return;
    setState(() => _busy = permission);
    try {
      if (permission == AppPermission.usageAccess) {
        // The disclosure and its agreement come before anything is read.
        if (!await confirmAppListAccess(context, ref) || !mounted) return;
        if (_status[permission] == PermissionOutcome.granted) return;
      }
      if (permission == AppPermission.notifications) {
        final outcome = await _manager.request(permission);
        if (outcome == PermissionOutcome.permanentlyDenied) {
          await _manager.openSettings();
        }
        return;
      }
      final guide = SettingsGuide.forPermission(permission);
      if (guide != null && !await showSettingsGuide(context, guide)) return;
      if (!mounted) return;
      await _manager.request(permission);
    } finally {
      if (mounted) setState(() => _busy = null);
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final supported = _manager.supports(AppPermission.usageAccess);
    // Rebuild when the agreement changes, since it completes the first row.
    ref.watch(appListConsentProvider);

    if (!supported) {
      return StepScaffold(
        title: context.tr("You are ready to focus"),
        subtitle: context.tr(
          "Your timer works without any extra device access.",
        ),
        onPrimary: widget.onNext,
        children: const [],
      );
    }

    final blockingReady =
        _done(AppPermission.usageAccess) && _done(AppPermission.overlay);
    final current = _order.where((p) => !_done(p)).firstOrNull;

    return StepScaffold(
      title: context.tr("Limit distracting apps"),
      subtitle: context.tr(
        "Allow these so Shield can pause the apps you choose.",
      ),
      primaryLabel: context.tr("Continue"),
      primaryEnabled: blockingReady,
      onPrimary: widget.onNext,
      secondary: blockingReady
          ? null
          : TextButton(
              onPressed: _busy == null ? widget.onNext : null,
              child: Text(context.tr("Continue without app blocking")),
            ),
      children: [
        for (final (index, permission) in _order.indexed) ...[
          if (index > 0) const Divider(height: 1),
          _PermissionRow(
            permission: permission,
            done: _done(permission),
            current: permission == current,
            onAllow: _busy == null ? () => _allow(permission) : null,
          ),
        ],
        const SizedBox(height: Gap.xl),
        const _WhyLink(),
      ],
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.permission,
    required this.done,
    required this.current,
    required this.onAllow,
  });

  final AppPermission permission;
  final bool done;
  final bool current;
  final VoidCallback? onAllow;

  static (String, String) copy(AppPermission permission) =>
      switch (permission) {
        AppPermission.usageAccess => (
          'Usage access',
          'See which app is open and how long you used it today.',
        ),
        AppPermission.overlay => (
          'Display over other apps',
          'Show the pause screen over the apps you block.',
        ),
        AppPermission.notifications => (
          'Notifications',
          'Timer alerts, and a Stop button while Shield runs.',
        ),
        AppPermission.accessibility => ('', ''),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final (title, body) = copy(permission);
    final waiting = !done && !current;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.base;

    return Semantics(
      container: true,
      label: done ? context.tr("{0}, allowed", [context.tr(title)]) : null,
      child: AnimatedOpacity(
        duration: duration,
        opacity: waiting ? .42 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.lg),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr(title),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!waiting) ...[
                      const SizedBox(height: 2),
                      Text(
                        context.tr(body),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: Gap.md),
              AnimatedSwitcher(
                duration: duration,
                child: done
                    ? Container(
                        key: const ValueKey('done'),
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: .14),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.check_rounded, color: cs.primary),
                      )
                    : current
                    ? FilledButton(
                        key: const ValueKey('allow'),
                        onPressed: onAllow,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(88, 44),
                        ),
                        child: Text(context.tr("Allow")),
                      )
                    : const SizedBox(key: ValueKey('wait'), width: 36),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Why does FocusForge need these?" and the sheet it opens.
class _WhyLink extends StatelessWidget {
  const _WhyLink();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: cs.primary.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(Radii.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.pill),
        onTap: () => _showWhy(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.lg,
            vertical: Gap.md,
          ),
          child: Row(
            children: [
              Icon(Icons.help_outline_rounded, color: cs.primary),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Text(
                  context.tr("Why does FocusForge need these?"),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: cs.primary,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _showWhy(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (context) {
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
                Text(
                  context.tr("Why FocusForge asks for these"),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: Gap.lg),
                for (final permission in const [
                  AppPermission.usageAccess,
                  AppPermission.overlay,
                  AppPermission.notifications,
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr(_PermissionRow.copy(permission).$1),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.tr(_PermissionRow.copy(permission).$2),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                Text(
                  context.tr(
                    "Each one is optional, and you can turn it off anytime in Android settings. Your app list and usage stay on this phone.",
                  ),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: Gap.xl),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.tr("Got it")),
                ),
              ],
            ),
          );
        },
      );
}
