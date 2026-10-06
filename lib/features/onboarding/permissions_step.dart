import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/providers/shield_providers.dart';
import '../../shared/widgets/glass_surface.dart';
import '../../shared/widgets/stagger.dart';
import 'onboarding_chrome.dart';

/// Screen 7 — permissions.
///
/// The make-or-break screen of the plan: a permission the user does not
/// understand is a permission they deny. Every card says what the access is
/// for and what it explicitly does not touch.
///
/// There is no native layer yet, so nothing here can actually be granted.
/// Tapping Enable asks the platform service and then records the card as
/// "set up later" — the one thing this screen must never do is tick a box the
/// operating system has not ticked.
class PermissionsStep extends ConsumerStatefulWidget {
  const PermissionsStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  ConsumerState<PermissionsStep> createState() => _PermissionsStepState();
}

class _PermissionsStepState extends ConsumerState<PermissionsStep> {
  final _deferred = <String>{};

  Future<void> _enable(_Permission permission) async {
    await ref.read(shieldServiceProvider).requestPermission();
    if (!mounted) return;
    setState(() => _deferred.add(permission.title));
  }

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
                deferred: _deferred.contains(_permissions[i].title),
                onEnable: () => _enable(_permissions[i]),
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
    required this.title,
    required this.icon,
    required this.why,
    required this.privacy,
    required this.platform,
  });

  final String title;
  final IconData icon;
  final String why;
  final String privacy;
  final String platform;
}

const _permissions = <_Permission>[
  _Permission(
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
    title: 'Usage Access',
    icon: Icons.query_stats_rounded,
    why:
        'Reads screen time per app so the dashboard can show where your day '
        'actually went.',
    privacy: 'Usage history never leaves this device and is never uploaded.',
    platform: 'Android',
  ),
  _Permission(
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
];

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.permission,
    required this.deferred,
    required this.onEnable,
  });

  final _Permission permission;
  final bool deferred;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GlassPanel(
      radius: Radii.card,
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassIconBadge(
                icon: permission.icon,
                color: cs.primary,
                size: 40,
                radius: Radii.tile,
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Text(permission.title, style: Theme.of(context).textTheme.titleMedium),
              ),
              GlassPill(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.sm + 2,
                  vertical: 4,
                ),
                child: Text(
                  permission.platform,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
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
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.tertiary),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          if (deferred)
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: Gap.sm),
                Text(
                  'Set up later',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            )
          else
            Align(
              alignment: Alignment.centerRight,
              child: GlassPill(
                accent: cs.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.lg,
                  vertical: Gap.sm + 2,
                ),
                onTap: onEnable,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Enable',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 15,
                      color: cs.primary,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
