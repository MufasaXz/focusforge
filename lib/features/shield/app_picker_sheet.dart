import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/models/shield.dart';
import '../../core/providers/shield_providers.dart';
import '../../core/providers/usage_providers.dart';
import '../../core/services/app_catalog.dart';
import '../../shared/widgets/app_icon_avatar.dart';
import '../../shared/widgets/pressable.dart';

/// Opens the picker that adds apps from the device to the rule list.
///
/// A sheet rather than a screen: the user comes here knowing which app they
/// mean, and pushing a route would cost them the context of the list they are
/// adding to. The selection is committed on the way out, so backing out of the
/// sheet is the cancel.
Future<void> showAppPickerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    // The list can be longer than the screen, and the sheet has to be able to
    // grow past the keyboard when the search field is focused.
    useSafeArea: true,
    builder: (_) => const _AppPickerSheet(),
  );
}

class _AppPickerSheet extends ConsumerStatefulWidget {
  const _AppPickerSheet();

  @override
  ConsumerState<_AppPickerSheet> createState() => _AppPickerSheetState();
}

class _AppPickerSheetState extends ConsumerState<_AppPickerSheet> {
  final _search = TextEditingController();

  /// Packages ticked in this session. Held as package ids rather than rows so
  /// the list can be filtered or reloaded underneath without losing a choice.
  final _selected = <String>{};

  WhitelistTier _tier = WhitelistTier.blocked;
  int _budgetMinutes = WhitelistNotifier.defaultBudgetMinutes;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(String packageId) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selected.remove(packageId)) _selected.add(packageId);
    });
  }

  Future<void> _commit() async {
    final apps = ref.read(installedAppsProvider).valueOrNull ?? const [];
    final byPackage = {for (final a in apps) a.packageId: a};
    final notifier = ref.read(whitelistProvider.notifier);

    // Sequential rather than `Future.wait`: every add persists the whole list,
    // and two concurrent writers would race to be the last one saved.
    for (final packageId in _selected) {
      final app = byPackage[packageId];
      await notifier.addInstalledApp(
        packageId: packageId,
        name: app?.name ?? packageId,
        tier: _tier,
        budgetMinutes: _budgetMinutes,
      );
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final query = _search.text.trim().toLowerCase();
    final installed = ref.watch(installedAppsProvider);
    final existing = {
      for (final entry in ref.watch(whitelistProvider))
        if (entry.packageId != null) entry.packageId!,
    };

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Gap.lg,
        Gap.lg,
        Gap.lg,
        Gap.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.hero),
        // A modal sheet floats over the page it was opened from, which is one
        // of the few places the design spends a real backdrop filter.
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(Radii.hero),
            ),
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                  ),
                ),
                const SizedBox(height: Gap.lg),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add apps',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Pick what you want closed',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (_selected.isNotEmpty)
                      Text(
                        '${_selected.length} selected',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: Gap.lg),
                _TierChoice(
                  tier: _tier,
                  onChanged: (next) => setState(() => _tier = next),
                ),
                if (_tier == WhitelistTier.budgeted) ...[
                  const SizedBox(height: Gap.md),
                  _BudgetStepper(
                    minutes: _budgetMinutes,
                    onChanged: (next) =>
                        setState(() => _budgetMinutes = next),
                  ),
                ],
                const SizedBox(height: Gap.lg),
                _SearchField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: Gap.md),
                Flexible(
                  child: installed.when(
                    loading: () => const _PickerLoading(),
                    error: (_, _) => const _PickerNotice(
                      icon: Icons.error_outline_rounded,
                      title: 'Could not read your apps',
                      body:
                          'Android would not return the installed app list. '
                          'Reopen the app and try again.',
                    ),
                    data: (apps) {
                      if (!AppCatalog.isSupported) {
                        return const _PickerNotice(
                          icon: Icons.phone_android_rounded,
                          title: 'Adding apps needs a phone',
                          body:
                              'The device app list is only readable on '
                              'Android. Nothing is being blocked here.',
                        );
                      }
                      final visible = query.isEmpty
                          ? apps
                          : apps
                                .where(
                                  (a) => a.name.toLowerCase().contains(query),
                                )
                                .toList(growable: false);
                      if (apps.isEmpty) {
                        return const _PickerNotice(
                          icon: Icons.apps_rounded,
                          title: 'No apps to show',
                          body:
                              'Android returned an empty app list. This '
                              'normally means the app was installed without '
                              'the package query permission.',
                        );
                      }
                      if (visible.isEmpty) {
                        return _PickerNotice(
                          icon: Icons.search_off_rounded,
                          title: 'Nothing matches',
                          body:
                              'No installed app is called '
                              '“${_search.text.trim()}”.',
                        );
                      }
                      return ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: visible.length,
                        itemBuilder: (context, i) {
                          final app = visible[i];
                          return _PickerRow(
                            app: app,
                            selected: _selected.contains(app.packageId),
                            alreadyListed: existing.contains(app.packageId),
                            onTap: () => _toggle(app.packageId),
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: Gap.md),
                FilledButton(
                  onPressed: _selected.isEmpty ? null : _commit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(
                    _selected.isEmpty
                        ? 'Select an app'
                        : 'Add ${_selected.length} '
                              '${_selected.length == 1 ? 'app' : 'apps'}',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What the picked apps will become. Two options, because "always allowed" is
/// the absence of a rule — it is what removing an app does, not a way to add
/// one.
class _TierChoice extends StatelessWidget {
  const _TierChoice({required this.tier, required this.onChanged});

  final WhitelistTier tier;
  final ValueChanged<WhitelistTier> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<WhitelistTier>(
        segments: const [
          ButtonSegment(
            value: WhitelistTier.blocked,
            icon: Icon(Icons.block_rounded, size: 18),
            label: Text('Block'),
          ),
          ButtonSegment(
            value: WhitelistTier.budgeted,
            icon: Icon(Icons.hourglass_bottom_rounded, size: 18),
            label: Text('Time budget'),
          ),
        ],
        selected: {tier},
        showSelectedIcon: false,
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

/// The daily allowance applied to everything added in this session.
///
/// A stepper rather than a slider: a slider that moves in 1-minute steps over
/// a 0–24 h range cannot be landed on 30 by thumb, and the exact number is the
/// whole point of a budget.
class _BudgetStepper extends StatelessWidget {
  const _BudgetStepper({required this.minutes, required this.onChanged});

  final int minutes;
  final ValueChanged<int> onChanged;

  static const _step = 5;
  static const _min = 5;
  static const _max = 8 * 60;

  String get _label => minutes >= 60
      ? '${minutes ~/ 60} h${minutes % 60 == 0 ? '' : ' ${minutes % 60} m'}'
      : '$minutes min';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.md,
          vertical: Gap.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Daily allowance',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    'Then the app closes until tomorrow',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            _StepperButton(
              icon: Icons.remove_rounded,
              label: 'Less time',
              enabled: minutes > _min,
              onTap: () => onChanged((minutes - _step).clamp(_min, _max)),
            ),
            Semantics(
              label: 'Daily allowance',
              value: _label,
              child: SizedBox(
                width: 62,
                child: Text(
                  _label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
            _StepperButton(
              icon: Icons.add_rounded,
              label: 'More time',
              enabled: minutes < _max,
              onTap: () => onChanged((minutes + _step).clamp(_min, _max)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      onTap: enabled ? onTap : null,
      child: ExcludeSemantics(
        child: Pressable(
          scale: 0.86,
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: Icon(
                icon,
                size: 18,
                color: enabled ? cs.onSurface : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 15),
      cursorColor: cs.primary,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: cs.surfaceContainerHigh,
        hintText: 'Search your apps…',
        hintStyle: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 18,
          color: cs.onSurfaceVariant,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.pill),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.pill),
          borderSide: BorderSide(color: cs.primary),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Gap.lg,
          vertical: Gap.md,
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.app,
    required this.selected,
    required this.alreadyListed,
    required this.onTap,
  });

  final InstalledApp app;
  final bool selected;
  final bool alreadyListed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Semantics(
      container: true,
      checked: alreadyListed ? true : selected,
      enabled: !alreadyListed,
      label: alreadyListed ? '${app.name}, already on the list' : app.name,
      onTap: alreadyListed ? null : onTap,
      child: ExcludeSemantics(
        child: Opacity(
          opacity: alreadyListed ? 0.45 : 1,
          child: Pressable(
            onTap: alreadyListed ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.sm),
              child: Row(
                children: [
                  AppIconAvatar(
                    packageId: app.packageId,
                    fallbackIcon: Icons.android_rounded,
                    fallbackColor: cs.primary,
                    size: 38,
                    radius: 11,
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Text(
                      app.name,
                      style: Theme.of(context).textTheme.bodyLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  if (alreadyListed)
                    Text(
                      'On the list',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    )
                  else
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? cs.primary : Colors.transparent,
                        border: Border.all(
                          color: selected ? cs.primary : cs.outline,
                          width: 2,
                        ),
                      ),
                      child: selected
                          ? Icon(
                              Icons.check_rounded,
                              size: 14,
                              color: cs.onPrimary,
                            )
                          : null,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerLoading extends StatelessWidget {
  const _PickerLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: Gap.xxl),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      ),
    );
  }
}

class _PickerNotice extends StatelessWidget {
  const _PickerNotice({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.xl),
      child: Column(
        children: [
          Icon(icon, size: 40, color: cs.onSurfaceVariant),
          const SizedBox(height: Gap.md),
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: Gap.xs),
          Text(
            body,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
