import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme/app_theme.dart';
import '../../core/localization/app_strings.dart';
import '../../core/models/user.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/app_segmented_control.dart';

/// Everything about how the app looks: light/dark/system, the seed palette,
/// true black for OLED panels and the timer's clock face.
///
/// It used to be a tall card in the middle of the You tab, which pushed every
/// other setting a screen further down. One row there now says what is chosen
/// and opens this page, the way a phone's own settings app does.
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).colorScheme;
    final settings = ref.watch(themeSettingsProvider);
    final notifier = ref.read(themeSettingsProvider.notifier);

    // The *resolved* brightness, not the preference: with `system` selected,
    // the true-black switch has to follow what the device is actually doing.
    // Offering it in light mode would be a control that cannot do anything.
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppPage(
      title: context.tr("Appearance"),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSection(
            title: context.tr("Theme"),
            children: [
              Padding(
                padding: const EdgeInsets.all(Gap.lg),
                child: AppSegmentedControl<ThemePreference>(
                  options: {
                    for (final p in ThemePreference.values)
                      p: context.tr(p.label),
                  },
                  selected: settings.mode,
                  onChanged: notifier.setMode,
                ),
              ),
              if (isDark) ...[
                Divider(
                  height: 1,
                  color: t.outlineVariant.withValues(alpha: .4),
                ),
                // A SwitchListTile names the switch with its title, so
                // TalkBack reads "True black, switch, off" as one control.
                SwitchListTile(
                  value: settings.amoled,
                  onChanged: notifier.setAmoled,
                  secondary: const Icon(Icons.contrast_rounded),
                  title: Text(context.tr("True black")),
                  subtitle: Text(
                    context.tr("Use a black background in dark mode."),
                  ),
                ),
              ],
              Divider(height: 1, color: t.outlineVariant.withValues(alpha: .4)),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(context.tr("Clock face")),
                subtitle: Text(context.tr(ref.watch(clockFaceProvider).label)),
                trailing: const AppChevron(),
                onTap: () => context.goNamed(AppRoutes.clockFace),
              ),
            ],
          ),
          AppSection(
            title: context.tr("Accent color"),
            children: [
              Padding(
                padding: const EdgeInsets.all(Gap.sm),
                // An even grid rather than a centred wrap: a wrap spreads a
                // short last line across the row, so its swatches stop
                // lining up with the ones above. The column count follows
                // the width, so a 320dp phone still shows every choice.
                child: LayoutBuilder(
                  builder: (context, box) {
                    final columns = (box.maxWidth / 76).floor().clamp(
                      3,
                      AppPalette.values.length,
                    );
                    final cell = box.maxWidth / columns;
                    return Wrap(
                      runSpacing: Gap.xs,
                      children: [
                        for (final p in AppPalette.values)
                          SizedBox(
                            width: cell,
                            child: Center(
                              child: _PaletteSwatch(
                                palette: p,
                                selected: p == settings.palette,
                                onTap: () => notifier.setPalette(p),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One palette in the picker — the seed every colour in the app derives from.
///
/// Drawn as the *light* seed: the two seeds are the same hue, so showing both
/// would be two circles pretending to be one choice.
class _PaletteSwatch extends StatelessWidget {
  const _PaletteSwatch({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).colorScheme;
    final color = palette.lightSeed;

    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.base;
    return Semantics(
      label: context.tr(palette.label),
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.tile),
        child: Padding(
          padding: const EdgeInsets.all(Gap.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: duration,
                curve: Motion.decelerate,
                width: 48,
                height: 48,
                padding: const EdgeInsets.all(Gap.xs),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(selected ? 18 : 24),
                  border: Border.all(
                    color: selected ? t.onSurface : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: AnimatedContainer(
                  duration: duration,
                  curve: Motion.decelerate,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(selected ? 12 : 20),
                  ),
                  child: selected
                      ? Icon(
                          Icons.check_rounded,
                          size: 18,
                          color:
                              ThemeData.estimateBrightnessForColor(color) ==
                                  Brightness.dark
                              ? Colors.white
                              : Colors.black,
                        )
                      : null,
                ),
              ),
              const SizedBox(height: Gap.xs),
              Text(
                context.tr(palette.label),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
