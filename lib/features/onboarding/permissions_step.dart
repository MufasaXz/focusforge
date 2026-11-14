import '../../core/localization/app_strings.dart';
import '../../shared/widgets/glass_surface.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/services/permission_manager.dart';
import '../../shared/widgets/icon_badge.dart';
import '../../shared/widgets/accessibility_disclosure.dart';
import '../../shared/widgets/app_list_disclosure.dart';
import '../../shared/widgets/stagger.dart';
import 'onboarding_chrome.dart';

/// Optional access management, opened from Profile after setup.
///
/// The make-or-break screen of the plan: a permission the user does not
/// understand is a permission they deny. Every card says what the access is
/// for and what it explicitly does not touch.
///
/// Every button here opens the real thing — a system dialog where the platform
/// has one, and the relevant Settings page where it does not. Android gives
/// accessibility and usage access no dialog at all, so those two send the user
/// to Settings and are re-checked when the app is resumed. The one thing this
/// screen must never do is tick a box the operating system has not ticked.
class PermissionsStep extends ConsumerStatefulWidget {
  const PermissionsStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  ConsumerState<PermissionsStep> createState() => _PermissionsStepState();
}

class _PermissionsStepState extends ConsumerState<PermissionsStep>
    with WidgetsBindingObserver {
  static const _manager = PermissionManager();

  final _status = <AppPermission, PermissionOutcome>{};
  AppPermission? _requesting;

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

  /// The only moment the answer to a Settings-page permission can be learned.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final next = <AppPermission, PermissionOutcome>{};
    for (final permission in AppPermission.values) {
      next[permission] = await _manager
          .check(permission)
          .timeout(
            const Duration(seconds: 4),
            onTimeout: () => PermissionOutcome.denied,
          );
    }
    if (!mounted) return;
    setState(() => _status.addAll(next));
  }

  Future<void> _enable(AppPermission permission) async {
    if (_requesting != null) return;
    if (permission == AppPermission.accessibility &&
        !await confirmShieldAccess(context)) {
      return;
    }
    if (!mounted) return;
    if (permission == AppPermission.usageAccess &&
        !await confirmAppListAccess(context, ref)) {
      return;
    }
    if (!mounted) return;
    showAppSnack(context, switch (permission) {
      AppPermission.accessibility => tr(
        "Choose FocusForge in Accessibility, then allow access.",
      ),
      AppPermission.usageAccess => tr(
        "Choose FocusForge, then allow usage access.",
      ),
      AppPermission.overlay => tr(
        "Allow FocusForge to display over other apps.",
      ),
      AppPermission.notifications => tr(
        "Allow notifications to keep your timer visible.",
      ),
    });
    setState(() => _requesting = permission);
    final outcome = await _manager.request(permission);
    if (!mounted) return;
    setState(() {
      _status[permission] = outcome;
      _requesting = null;
    });

    // A settings page leaves the user somewhere that cannot explain itself.
    // Say what to do while they are still looking at this screen.
    if (outcome == PermissionOutcome.openedSettings) {
      showAppSnack(
        context,
        tr("Find FocusForge in that list, turn it on, then come back here."),
      );
    }
  }

  Future<void> _openSettings() => _manager.openSettings();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final permissions = _permissions
        .where((p) => _manager.supports(p.kind))
        .toList();
    final granted = permissions
        .where((p) => _status[p.kind] == PermissionOutcome.granted)
        .length;

    return StepScaffold(
      title: context.tr("Make room for focus"),
      subtitle: context.tr(
        "Enable the features you want. The focus timer works without these, and you can return to permissions later.",
      ),
      onPrimary: widget.onNext,
      primaryEnabled: _requesting == null,
      primaryLabel: permissions.isEmpty || granted == permissions.length
          ? context.tr("Done")
          : context.tr("Continue for now"),
      footnote: context.tr(
        "Optional. Access is confirmed by your device, and you can revoke it in system settings.",
      ),
      children: [
        if (permissions.isEmpty)
          Text(context.tr("No extra permissions are needed on this device."))
        else ...[
          Semantics(
            liveRegion: true,
            child: Text(
              context.tr("{0} of {1} enabled", [granted, permissions.length]),
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: cs.primary),
            ),
          ),
          const SizedBox(height: Gap.lg),
        ],
        if (permissions.isNotEmpty)
          Stagger(
            index: 2,
            // One grouped list, the way a phone's own settings app asks: a
            // row per permission with its state at the end, instead of a
            // card of paragraphs each.
            child: ContentCard(
              child: Column(
                children: [
                  for (var i = 0; i < permissions.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        indent: Gap.lg + 40 + Gap.md,
                        color: cs.outlineVariant.withValues(alpha: .4),
                      ),
                    _PermissionRow(
                      permission: permissions[i],
                      status: _status[permissions[i].kind],
                      busy: _requesting == permissions[i].kind,
                      onEnable: _requesting == null
                          ? () => _enable(permissions[i].kind)
                          : null,
                      onOpenSettings: _openSettings,
                    ),
                  ],
                ],
              ),
            ),
          ),
        const SizedBox(height: Gap.lg),
        const SizedBox(height: Gap.xs),
        Stagger(
          index: 6,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline_rounded, size: 15, color: cs.tertiary),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  context.tr(
                    "Your detailed study log and installed app list stay on this device. Optional study groups share only the totals and timer status you choose.",
                  ),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Permission {
  const _Permission({
    required this.kind,
    required this.title,
    required this.icon,
    required this.why,
  });

  final AppPermission kind;
  final String title;
  final IconData icon;

  /// One line: what turning it on gives the user.
  final String why;
}

final _permissions = <_Permission>[
  _Permission(
    kind: AppPermission.overlay,
    title: tr("Show app pause screens"),
    icon: Icons.layers_outlined,
    why: tr("Shows a pause screen over the apps you choose."),
  ),
  _Permission(
    kind: AppPermission.notifications,
    title: tr("Keep your timer in view"),
    icon: Icons.notifications_active_outlined,
    why: tr("Keeps your running timer in a quiet notification."),
  ),
  _Permission(
    kind: AppPermission.usageAccess,
    title: tr("Understand your screen time"),
    icon: Icons.query_stats_rounded,
    why: tr("Shows your screen time and spots the apps you limit."),
  ),
];

/// One permission: icon, name, one line of reason and its state at the end.
///
/// The state is what the operating system says, never a guess: "Allow" until
/// it is granted, a tick after, and a way to Settings once Android has
/// stopped asking.
class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.permission,
    required this.status,
    required this.onEnable,
    required this.onOpenSettings,
    required this.busy,
  });

  final _Permission permission;
  final PermissionOutcome? status;
  final VoidCallback? onEnable;
  final VoidCallback onOpenSettings;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final granted = status == PermissionOutcome.granted;

    // The line under the title changes with the state, so a row that is
    // waiting on Settings says so where the reason was.
    final line = switch (status) {
      _ when busy => context.tr("Opening permission…"),
      null => context.tr("Checking access…"),
      PermissionOutcome.openedSettings => context.tr(
        "Waiting for you to turn it on in Settings",
      ),
      PermissionOutcome.permanentlyDenied => context.tr(
        "Turned off — only Settings can change it",
      ),
      PermissionOutcome.unsupported => context.tr(
        "Not available on this device",
      ),
      _ => permission.why,
    };

    final Widget action = switch (status) {
      _ when busy || status == null => const SizedBox.square(
        dimension: 48,
        child: Center(
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      PermissionOutcome.granted => Semantics(
        label: context.tr("{0} granted", [permission.title]),
        excludeSemantics: true,
        child: SizedBox(
          height: 48,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, size: 20, color: cs.tertiary),
              const SizedBox(width: Gap.xs),
              Text(
                context.tr("Granted"),
                style: theme.textTheme.labelLarge?.copyWith(color: cs.tertiary),
              ),
            ],
          ),
        ),
      ),
      PermissionOutcome.unsupported => const SizedBox.shrink(),
      PermissionOutcome.permanentlyDenied => TextButton(
        onPressed: onOpenSettings,
        child: Text(context.tr("Open Settings")),
      ),
      PermissionOutcome.openedSettings => TextButton(
        onPressed: onEnable,
        child: Text(context.tr("Open again")),
      ),
      _ => FilledButton.tonal(
        onPressed: onEnable,
        style: FilledButton.styleFrom(
          minimumSize: const Size(72, 40),
          tapTargetSize: MaterialTapTargetSize.padded,
          padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
        ),
        child: Text(context.tr("Allow")),
      ),
    };

    final icon = IconBadge(
      icon: permission.icon,
      color: granted ? cs.tertiary : cs.primary,
      size: 40,
      radius: Radii.tile,
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(permission.title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 2),
        Text(
          line,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        Gap.lg,
        Gap.md,
        Gap.md,
        Gap.md,
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          // Side by side while the action fits beside a readable title; on a
          // narrow phone with large text it drops under the reason instead
          // of squeezing the title to a word per line.
          final roomy =
              box.maxWidth >= 250 &&
              MediaQuery.textScalerOf(context).scale(14) <= 18;
          if (roomy) {
            return Row(
              children: [
                icon,
                const SizedBox(width: Gap.md),
                Expanded(child: text),
                const SizedBox(width: Gap.sm),
                action,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  icon,
                  const SizedBox(width: Gap.md),
                  Expanded(child: text),
                ],
              ),
              Align(alignment: AlignmentDirectional.centerEnd, child: action),
            ],
          );
        },
      ),
    );
  }
}
