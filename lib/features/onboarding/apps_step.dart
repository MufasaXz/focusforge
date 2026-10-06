import '../../shared/widgets/app_page.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/data/seed.dart';
import '../../core/providers/shield_providers.dart';
import '../../shared/widgets/icon_badge.dart';
import '../../shared/widgets/stagger.dart';
import 'onboarding_chrome.dart';
import 'onboarding_state.dart';

/// Screen 5 — what to block during a focus session.
///
/// Only apps with a row in the shield catalogue are offered as toggles, and
/// arming one here is the same act as arming that row on the Shield screen.
/// The rest of the device scan is still shown, marked as not yet supported,
/// and kept out of `blockedAppsProvider`: the completion summary counts that
/// provider, and a count that includes apps with no shield row would promise
/// something the engine cannot deliver.
class AppsStep extends ConsumerStatefulWidget {
  const AppsStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  ConsumerState<AppsStep> createState() => _AppsStepState();
}

class _AppsStepState extends ConsumerState<AppsStep> {
  /// Package id to feed-shield row id. Only the apps the shield catalogue
  /// actually carries appear here.
  static const _feedShieldFor = <String, String>{
    'com.instagram.android': 'instagram_reels',
    'com.facebook.katana': 'facebook_watch',
    'com.google.android.youtube': 'youtube_shorts',
    'com.zhiliaoapp.musically': 'tiktok_feed',
    'com.twitter.android': 'twitter_trending',
  };

  static const _tierSubtitle = <int, String>{
    0: 'Feeds and endless scroll',
    1: 'Messaging and chat',
    2: 'Kept available during focus',
  };

  @override
  void initState() {
    super.initState();
    _reconcile();
  }

  /// Makes the selection agree with the engine before the first frame.
  ///
  /// `feedGroupsProvider` is the persisted truth — it is what the Shield tab
  /// renders and what the native config is built from — so the toggles start
  /// from it rather than from the notifier's cold-install defaults. Without
  /// this pass a relaunch would show every high-distraction app armed again,
  /// and the selection would include packages (Snapchat, Reddit, the whole
  /// messaging tier) that have no row to arm.
  void _reconcile() {
    final armed = {
      for (final group in ref.read(feedGroupsProvider))
        for (final row in group.rows)
          if (row.enabled) row.id,
    };
    final notifier = ref.read(blockedAppsProvider.notifier);
    for (final entry in _feedShieldFor.entries) {
      notifier.toggle(entry.key, armed.contains(entry.value));
    }
    for (final app in SeedData.detectableApps) {
      if (_feedShieldFor.containsKey(app.packageId)) continue;
      notifier.toggle(app.packageId, false);
    }
  }

  Future<void> _set(DetectableApp app, bool value) async {
    ref.read(blockedAppsProvider.notifier).toggle(app.packageId, value);
    final rowId = _feedShieldFor[app.packageId];
    if (rowId != null) {
      await ref.read(feedGroupsProvider.notifier).toggle(rowId, value);
    }
  }

  /// The final write-through before the flow moves on.
  ///
  /// Toggles already reach the shield catalogue one tap at a time and
  /// [_reconcile] starts the selection from it, but this pass guarantees the
  /// two agree at the moment of Continue — which is what makes the number the
  /// Complete step shows the number of armed rows.
  Future<void> _commit() async {
    final selected = ref.read(blockedAppsProvider);
    final notifier = ref.read(feedGroupsProvider.notifier);
    for (final entry in _feedShieldFor.entries) {
      await notifier.toggle(entry.value, selected.contains(entry.key));
    }
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).colorScheme;
    final blocked = ref.watch(blockedAppsProvider);

    return StepScaffold(
      title: 'Choose apps to block',
      subtitle:
          'These are the feeds FocusForge can shield today. Apps marked '
          '"Not yet supported" are coming later and stay untouched. Blocking '
          'only applies while a focus session is running.',
      onPrimary: _commit,
      footnote: blocked.isEmpty
          ? 'Nothing blocked — you can still block apps any time from Shield.'
          : '${blocked.length} apps will be paused while you focus.',
      children: [
        for (final tier in const [0, 1, 2]) ...[
          Stagger(
            index: 2 + tier,
            child: SectionHeader(
              title: _titleFor(tier),
              icon: _iconFor(tier),
              trailing: Text(
                _trailingFor(tier),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: _colorFor(tier, t),
                ),
              ),
            ),
          ),
          Stagger(
            index: 3 + tier,
            child: Padding(
              padding: const EdgeInsets.only(bottom: Gap.lg),
              child: Card.filled(
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                  child: Column(
                    children: [
                      for (final app in SeedData.detectableApps.where(
                        (a) => a.tier == tier,
                      ))
                        _AppRow(
                          app: app,
                          subtitle: _tierSubtitle[tier] ?? '',
                          selected: blocked.contains(app.packageId),
                          // Productive apps are never blocked; everything else
                          // without a feed-shield row has nothing to arm yet.
                          onChanged:
                              tier == 0 &&
                                  _feedShieldFor.containsKey(app.packageId)
                              ? (value) => unawaited(_set(app, value))
                              : null,
                          unsupported:
                              tier != 2 &&
                              !_feedShieldFor.containsKey(app.packageId),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _titleFor(int tier) => switch (tier) {
    0 => 'High distraction',
    1 => 'Moderate',
    _ => 'Productive',
  };

  static IconData _iconFor(int tier) => switch (tier) {
    0 => Icons.bolt_rounded,
    1 => Icons.chat_bubble_outline_rounded,
    _ => Icons.verified_rounded,
  };

  static String _trailingFor(int tier) => switch (tier) {
    0 => 'Selected for you',
    1 => 'Coming soon',
    _ => 'Never blocked',
  };

  static Color _colorFor(int tier, ColorScheme t) => switch (tier) {
    0 => t.error,
    1 => t.tertiary,
    _ => t.tertiary,
  };
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.app,
    required this.subtitle,
    required this.selected,
    this.onChanged,
    this.unsupported = false,
  });

  final DetectableApp app;
  final String subtitle;
  final bool selected;

  /// Null makes the row informational — there is no shield to toggle.
  final ValueChanged<bool>? onChanged;

  /// True when the shield catalogue has no row for this package yet. The row
  /// must not read as something the user can turn on today.
  final bool unsupported;

  void _toggle() {
    final onChanged = this.onChanged;
    if (onChanged == null) return;
    // A flip is a commitment — the tap that made it should be felt, not just
    // seen.
    HapticFeedback.lightImpact();
    onChanged(!selected);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).colorScheme;

    return ListTile(
      leading: IconBadge(
        icon: app.icon,
        color: unsupported ? t.onSurfaceVariant : app.color,
        size: 36,
        radius: Radii.tile,
      ),
      title: Text(
        app.name,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: unsupported ? t.onSurfaceVariant : null,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: t.onSurfaceVariant,
        ),
      ),
      trailing: onChanged != null
          // The switch's own semantics are excluded so a screen reader hears
          // one labelled switch, not a bare "switch, on" in a list of twenty.
          ? Semantics(
              toggled: selected,
              enabled: true,
              label: 'Block ${app.name} during focus',
              onTap: _toggle,
              excludeSemantics: true,
              child: Switch.adaptive(
                value: selected,
                onChanged: (_) => _toggle(),
              ),
            )
          : _StatusNote(
              icon: unsupported
                  ? Icons.construction_rounded
                  : Icons.check_circle_rounded,
              label: unsupported ? 'Not yet supported' : 'Allowed',
              color: unsupported ? t.onSurfaceVariant : t.tertiary,
            ),
    );
  }
}

/// The trailing note on an informational row. A row without a toggle has to
/// say *why* it has none — otherwise "allowed by design" and "cannot be
/// blocked yet" look identical.
class _StatusNote extends StatelessWidget {
  const _StatusNote({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
      ],
    );
  }
}
