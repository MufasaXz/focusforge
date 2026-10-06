import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/shield.dart';
import '../../core/providers/shield_providers.dart';
import '../../core/providers/usage_providers.dart';
import '../../core/services/app_catalog.dart';
import '../../shared/widgets/app_icon_avatar.dart';
import '../../shared/widgets/icon_badge.dart';
import '../../shared/widgets/stagger.dart';
import 'onboarding_chrome.dart';

/// Screen 5 — the apps to close.
///
/// The list is the device's own, read from the platform, because a fixed
/// catalogue can only ever offer the apps its author thought of: the app that
/// actually costs this user their evening is very often not on anyone's list
/// of famous distractions. A switch here writes the same rule the Shield tab
/// writes, so the two can never disagree about what is armed.
///
/// Blocking is not tied to a session. The user asked for the app to close, and
/// a rule that only applies while a timer runs is a rule they would have to
/// remember to arm.
class AppsStep extends ConsumerStatefulWidget {
  const AppsStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  ConsumerState<AppsStep> createState() => _AppsStepState();
}

class _AppsStepState extends ConsumerState<AppsStep> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Arms or disarms one package.
  ///
  /// Removing rather than moving to "always allowed" on the way off: the user
  /// turning a switch off here means "not this one", and leaving a row behind
  /// for every app they considered would fill the Shield tab with entries that
  /// do nothing.
  Future<void> _set(String packageId, String name, bool blocked) async {
    HapticFeedback.lightImpact();
    final notifier = ref.read(whitelistProvider.notifier);
    if (blocked) {
      await notifier.addInstalledApp(
        packageId: packageId,
        name: name,
        tier: WhitelistTier.blocked,
      );
    } else {
      await notifier.remove('pkg:$packageId');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final query = _search.text.trim().toLowerCase();
    final installed = ref.watch(installedAppsProvider);
    final blocked = {
      for (final entry in ref.watch(blockedAppsProvider)) entry.packageId,
    };
    final apps = installed.valueOrNull ?? const [];
    final visible = query.isEmpty
        ? apps
        : apps
              .where((a) => a.name.toLowerCase().contains(query))
              .toList(growable: false);

    return StepScaffold(
      title: 'Close the apps that pull you away',
      subtitle: AppCatalog.isSupported
          ? 'These are the apps on your phone. Anything you switch on closes '
                'the moment it opens — all day, not only while a timer runs. '
                'You can change this any time from the Shield tab.'
          : 'Closing apps is an Android feature. On this build the list is '
                'empty and nothing is blocked — you can set rules from the '
                'Shield tab on a phone.',
      onPrimary: widget.onNext,
      footnote: blocked.isEmpty
          ? 'Nothing blocked — you can add apps any time from Shield.'
          : '${blocked.length} '
                '${blocked.length == 1 ? 'app' : 'apps'} will close when '
                'opened.',
      children: [
        if (installed.isLoading)
          const Stagger(
            index: 2,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: Gap.xxl),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            ),
          )
        else if (apps.isEmpty)
          Stagger(index: 2, child: _NoApps(native: AppCatalog.isSupported))
        else ...[
          Stagger(
            index: 2,
            child: AppTextField(
              controller: _search,
              hint: 'Search your apps…',
              icon: Icons.search_rounded,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: Gap.xl),
          if (visible.isEmpty)
            Stagger(
              index: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.xl),
                child: Text(
                  'No app is called “${_search.text.trim()}”.',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            )
          else
            Stagger(
              index: 3,
              child: Card.filled(
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                  child: Column(
                    children: [
                      for (var i = 0; i < visible.length; i++) ...[
                        if (i > 0) Divider(color: cs.outlineVariant, height: 1),
                        _AppRow(
                          packageId: visible[i].packageId,
                          name: visible[i].name,
                          selected: blocked.contains(visible[i].packageId),
                          onChanged: (value) => _set(
                            visible[i].packageId,
                            visible[i].name,
                            value,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Shown when the platform will not hand over an app list.
///
/// The two reasons are worth separating: a device that cannot be asked at all
/// is a different problem from a phone that answered with nothing, and only
/// one of them is worth retrying.
class _NoApps extends StatelessWidget {
  const _NoApps({required this.native});

  final bool native;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stagger(
      index: 3,
      child: Card.filled(
        child: Padding(
          padding: const EdgeInsets.all(Gap.xl),
          child: Column(
            children: [
              IconBadge(
                icon: native
                    ? Icons.search_off_rounded
                    : Icons.phone_android_rounded,
                color: cs.onSurfaceVariant,
                size: 48,
                radius: 16,
              ),
              const SizedBox(height: Gap.md),
              Text(
                native ? 'No apps to show' : 'Needs a phone',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: Gap.xs),
              Text(
                native
                    ? 'Android returned an empty app list. You can still add '
                          'rules later from the Shield tab.'
                    : 'The app list is only readable on Android. Carry on — '
                          'you can set rules later from the Shield tab.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.packageId,
    required this.name,
    required this.selected,
    required this.onChanged,
  });

  final String packageId;
  final String name;
  final bool selected;
  final ValueChanged<bool> onChanged;

  void _toggle() => onChanged(!selected);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      leading: AppIconAvatar(
        packageId: packageId,
        fallbackIcon: Icons.android_rounded,
        fallbackColor: cs.primary,
        size: 36,
        radius: Radii.tile,
      ),
      title: Text(name, style: Theme.of(context).textTheme.bodyLarge),
      subtitle: Text(
        selected ? 'Closes when opened' : 'Opens normally',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      // The switch's own semantics are excluded so a screen reader hears one
      // labelled switch, not a bare "switch, on" in a list of a hundred.
      trailing: Semantics(
        toggled: selected,
        enabled: true,
        label: 'Block $name',
        onTap: _toggle,
        excludeSemantics: true,
        child: Switch.adaptive(value: selected, onChanged: (_) => _toggle()),
      ),
    );
  }
}
