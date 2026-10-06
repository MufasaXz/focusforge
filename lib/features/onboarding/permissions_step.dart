import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/services/permission_manager.dart';
import '../../shared/widgets/icon_badge.dart';
import '../../shared/widgets/stagger.dart';
import 'onboarding_chrome.dart';

/// Screen 7 — permissions.
///
/// The make-or-break screen of the plan: a permission the user does not
/// understand is a permission they deny. Every card says what the access is
/// for and what it explicitly does not touch.
///
/// Every button here opens the real thing — a system dialog where the platform
/// has one, and the relevant Settings page where it does not. Android gives
/// accessibility, usage access and overlay no dialog at all, so those three
/// send the user to Settings and are re-checked when the app is resumed. The
/// one thing this screen must never do is tick a box the operating system has
/// not ticked.
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
      next[permission] = await _manager.check(permission);
    }
    if (!mounted) return;
    setState(() => _status.addAll(next));
  }

  Future<void> _enable(AppPermission permission) async {
    final outcome = await _manager.request(permission);
    if (!mounted) return;
    setState(() => _status[permission] = outcome);

    // A settings page leaves the user somewhere that cannot explain itself.
    // Say what to do while they are still looking at this screen.
    if (outcome == PermissionOutcome.openedSettings) {
      showGlassSnack(
        context,
        'Find FocusForge in that list, turn it on, then come back here.',
      );
    }
  }

  Future<void> _openSettings() => _manager.openSettings();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return StepScaffold(
      title: 'Almost ready',
      subtitle:
          'FocusForge needs a few permissions to protect your focus. '
          'Here is exactly why, in plain language.',
      onPrimary: widget.onNext,
      footnote:
          'Nothing is granted until the system dialog says so — and you '
          'can change any of this later in Settings.',
      children: [
        for (var i = 0; i < _permissions.length; i++)
          Stagger(
            index: 2 + i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: Gap.md),
              child: _PermissionCard(
                permission: _permissions[i],
                status:
                    _status[_permissions[i].kind] ?? PermissionOutcome.denied,
                onEnable: () => _enable(_permissions[i].kind),
                onOpenSettings: _openSettings,
              ),
            ),
          ),
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
                  'Your data stays on this device. FocusForge does not upload '
                  'usage history, messages or personal data — ever.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
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
    required this.privacy,
    required this.platform,
  });

  final AppPermission kind;
  final String title;
  final IconData icon;
  final String why;
  final String privacy;
  final String platform;
}

const _permissions = <_Permission>[
  _Permission(
    kind: AppPermission.accessibility,
    title: 'Accessibility Service',
    icon: Icons.visibility_rounded,
    why:
        'Lets FocusForge see which app came to the foreground so it can hide '
        'the addictive parts — Reels, Shorts, the Watch tab — without blocking '
        'the whole app.',
    privacy:
        'We never read your messages, passwords or personal data. The '
        'service only checks which app is on screen.',
    platform: 'Android',
  ),
  _Permission(
    kind: AppPermission.notifications,
    title: 'Notifications',
    icon: Icons.notifications_active_rounded,
    why:
        'Reminds you when a focus block starts, and delivers your daily '
        'summary and streak alerts.',
    privacy:
        'Notifications are generated on-device. Nothing is pushed from a '
        'server.',
    platform: 'All platforms',
  ),
  _Permission(
    kind: AppPermission.usageAccess,
    title: 'Usage Access',
    icon: Icons.query_stats_rounded,
    why:
        'Reads screen time per app so the dashboard can show where your day '
        'actually went.',
    privacy: 'Usage history never leaves this device and is never uploaded.',
    platform: 'Android',
  ),
  _Permission(
    kind: AppPermission.overlay,
    title: 'Overlay',
    icon: Icons.layers_rounded,
    why:
        'Draws the Deep Breath Gate over an app you are about to open, so '
        'there is one calm moment before the scroll starts.',
    privacy:
        'The overlay only ever draws the gate. It cannot read what is '
        'behind it.',
    platform: 'Android',
  ),
  _Permission(
    kind: AppPermission.doNotDisturb,
    title: 'Do Not Disturb',
    icon: Icons.do_not_disturb_on_rounded,
    why:
        'Lets Strict Mode silence calls and notifications for the length of a '
        'session, so a deep-work block is not interrupted by a badge.',
    privacy:
        'FocusForge only turns DND on while a session is running, and always '
        'turns it back off.',
    platform: 'Android',
  ),
];

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.permission,
    required this.status,
    required this.onEnable,
    required this.onOpenSettings,
  });

  final _Permission permission;
  final PermissionOutcome status;
  final VoidCallback onEnable;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final granted = status == PermissionOutcome.granted;

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBadge(
                  icon: permission.icon,
                  color: granted ? cs.tertiary : cs.primary,
                  size: 40,
                  radius: Radii.tile,
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Text(
                    permission.title,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                  labelPadding: EdgeInsets.zero,
                  label: Text(
                    permission.platform,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.md),
            Text(
              permission.why,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Gap.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded, size: 13, color: cs.tertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    permission.privacy,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.tertiary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.md),
            _Action(
              status: status,
              title: permission.title,
              onEnable: onEnable,
              onOpenSettings: onOpenSettings,
            ),
          ],
        ),
      ),
    );
  }
}

/// The status line under a permission card.
///
/// Five outcomes, five different things to say — and the one thing none of
/// them may say is "done" before the operating system has said so.
class _Action extends StatelessWidget {
  const _Action({
    required this.status,
    required this.title,
    required this.onEnable,
    required this.onOpenSettings,
  });

  final PermissionOutcome status;
  final String title;
  final VoidCallback onEnable;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (status == PermissionOutcome.granted) {
      return Semantics(
        label: '$title granted',
        child: Row(
          children: [
            Icon(Icons.check_circle, size: 18, color: cs.tertiary),
            const SizedBox(width: Gap.sm),
            Text(
              'Granted',
              style: theme.textTheme.labelLarge?.copyWith(color: cs.tertiary),
            ),
          ],
        ),
      );
    }

    if (status == PermissionOutcome.unsupported) {
      return Row(
        children: [
          Icon(
            Icons.remove_circle_outline,
            size: 18,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              'Not available on this device',
              style: theme.textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }

    // A permanent refusal means the platform has stopped asking. Offering
    // "Enable" again would do nothing at all, so the button goes to the only
    // screen that can still change the answer.
    if (status == PermissionOutcome.permanentlyDenied) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'Turned off — only Settings can change it',
              style: theme.textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: onOpenSettings,
            child: const Text('Open Settings'),
          ),
        ],
      );
    }

    if (status == PermissionOutcome.openedSettings) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'Waiting for you to turn it on in Settings',
              style: theme.textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(onPressed: onEnable, child: const Text('Open again')),
        ],
      );
    }

    return Align(
      alignment: Alignment.centerRight,
      child: FilledButton.tonalIcon(
        onPressed: onEnable,
        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
        label: const Text('Enable'),
      ),
    );
  }
}
