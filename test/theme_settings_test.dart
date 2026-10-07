// The appearance settings: the palette table, the theme it generates, and the
// value that carries all three choices.
//
// WHAT INVARIANT: a missing or unknown stored value falls back to what the app
// shipped with; every palette carries a distinct seed per brightness; true
// black moves the surface family and nothing else; and the light theme stays
// light whatever the palette.
//
// WHY IT MATTERS: these three settings are read once, before the first frame,
// and then never validated again. A palette that resolved to a null or an
// empty string would take the whole scheme with it — every colour in the app
// is generated from that one value — and an AMOLED override that touched the
// accents would silently break contrast on the cards and chips that sit on the
// black.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/user.dart';

void main() {
  group('AppPalette', () {
    test('a missing or unknown name falls back to the shipped palette', () {
      expect(AppPalette.fromName(null), AppPalette.ember);
      expect(AppPalette.fromName(''), AppPalette.ember);
      expect(AppPalette.fromName('chartreuse'), AppPalette.ember);
    });

    test('round-trips by name', () {
      for (final palette in AppPalette.values) {
        expect(AppPalette.fromName(palette.name), palette);
      }
    });

    test('every palette has its own seed in each brightness', () {
      final light = {for (final p in AppPalette.values) p.lightSeed};
      final dark = {for (final p in AppPalette.values) p.darkSeed};

      expect(light.length, AppPalette.values.length);
      expect(dark.length, AppPalette.values.length);
    });

    test('the dark seed is the one dark mode uses', () {
      expect(
        AppPalette.iris.seedFor(Brightness.dark),
        AppPalette.iris.darkSeed,
      );
      expect(
        AppPalette.iris.seedFor(Brightness.light),
        AppPalette.iris.lightSeed,
      );
    });
  });

  group('AppTheme', () {
    test('the palette moves the scheme', () {
      final ember = AppTheme.light().colorScheme.primary;
      final tide = AppTheme.light(palette: AppPalette.tide).colorScheme.primary;

      expect(tide, isNot(ember));
    });

    test('true black moves the surface family and nothing else', () {
      final normal = AppTheme.dark().colorScheme;
      final amoled = AppTheme.dark(amoled: true).colorScheme;

      expect(amoled.surface, const Color(0xFF000000));
      expect(normal.surface, isNot(const Color(0xFF000000)));

      // The override is a background change, not a second theme: every accent
      // and every on-colour keeps the value the generator chose.
      expect(amoled.primary, normal.primary);
      expect(amoled.secondary, normal.secondary);
      expect(amoled.error, normal.error);
      expect(amoled.onSurface, normal.onSurface);
      expect(amoled.onSurfaceVariant, normal.onSurfaceVariant);
    });

    test('the surface ladder survives true black, so cards still separate', () {
      final cs = AppTheme.dark(amoled: true).colorScheme;

      expect(cs.surfaceContainerLowest, const Color(0xFF000000));
      expect(cs.surfaceContainer, isNot(cs.surface));
      expect(cs.surfaceContainerHighest, isNot(cs.surfaceContainer));
    });

    test('the light theme stays light, whatever the palette', () {
      for (final palette in AppPalette.values) {
        final surface = AppTheme.light(palette: palette).colorScheme.surface;
        expect(
          surface.computeLuminance(),
          greaterThan(0.8),
          reason: '${palette.name} light surface',
        );
      }
    });

    test('the palette reaches the whole scheme, not just the primary', () {
      final ember = AppTheme.dark().colorScheme;
      final grove = AppTheme.dark(palette: AppPalette.grove).colorScheme;

      expect(grove.primaryContainer, isNot(ember.primaryContainer));
      expect(grove.secondaryContainer, isNot(ember.secondaryContainer));
    });
  });

  group('ThemeSettings', () {
    test('the defaults are the ones the app ships with', () {
      const settings = ThemeSettings();

      expect(settings.mode, ThemePreference.system);
      expect(settings.palette, AppPalette.ember);
      expect(
        settings.amoled,
        isTrue,
        reason:
            'true black is the shipped look in dark mode — the switch turns '
            'it off, and a light-mode install never sees it',
      );
    });

    test('copyWith keeps the fields it is not given', () {
      const base = ThemeSettings(
        mode: ThemePreference.dark,
        palette: AppPalette.tide,
        amoled: true,
      );

      final next = base.copyWith(palette: AppPalette.grove);

      expect(next.palette, AppPalette.grove);
      expect(next.mode, ThemePreference.dark);
      expect(next.amoled, isTrue);
    });

    test('copyWith can turn a flag off, not only on', () {
      const base = ThemeSettings(amoled: true);

      expect(base.copyWith(amoled: false).amoled, isFalse);
    });
  });
}
