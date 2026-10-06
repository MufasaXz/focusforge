import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart' as mcu;

import 'typography.dart';

/// The app's Material 3 theme.
///
/// One warm seed generates the entire palette, light and dark. Nothing here
/// hardcodes a surface colour: a literal would survive a theme switch and go
/// unreadable, which is exactly what the previous hand-tuned token set kept
/// doing. Reach for a role — `colorScheme.primary`, `surfaceContainerLow` —
/// rather than a hex value.
class AppTheme {
  const AppTheme._();

  /// Warm Ember. The single input the whole palette derives from.
  static const seed = Color(0xFFE8672A);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final cs = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: cs,
      fontFamily: 'Inter',
      textTheme: AppType.build(cs),
      scaffoldBackgroundColor: cs.surface,
      canvasColor: cs.surface,
      iconTheme: IconThemeData(color: cs.onSurfaceVariant, size: 22),

      // The indicator is a stadium, per M3 Expressive. The bar is 80 so a
      // destination's label never clips at the larger Inter sizes.
      navigationBarTheme: NavigationBarThemeData(
        indicatorShape: const StadiumBorder(),
        height: 80,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        backgroundColor: cs.surfaceContainer,
        elevation: 0,
      ),

      // Elevation 0 with a tonal fill: M3 expresses hierarchy through surface
      // tone, and a drop shadow on a card that already sits on a tinted
      // surface reads as a mistake.
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        color: cs.surfaceContainerLow,
      ),

      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide.none,
        backgroundColor: cs.surfaceContainerHigh,
        selectedColor: cs.secondaryContainer,
        labelStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: cs.onSurface,
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.hero)),
        ),
        backgroundColor: cs.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: cs.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.hero),
        ),
      ),

      // The check inside the thumb is M3 Expressive's selected-state tell.
      switchTheme: SwitchThemeData(
        thumbIcon: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Icon(Icons.check, size: 16);
          }
          return null;
        }),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
        shape: const CircleBorder(),
        elevation: 1,
      ),

      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: cs.primary,
        inactiveTrackColor: cs.surfaceContainerHighest,
        thumbColor: cs.primary,
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: cs.onSurfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.tile),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.tile),
        ),
      ),

      dividerTheme: DividerThemeData(color: cs.outlineVariant, space: 1),

      // One transition for every platform. The app is a single visual language
      // and a platform-swapped page transition was the only place that was not
      // true — and it dragged `flutter/cupertino.dart` in for one line.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
          TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Corner radii. Named by role rather than by size, so a card and a hero can
/// move independently of whatever number they happen to share today.
class Radii {
  const Radii._();

  static const double hero = 28;
  static const double card = 16;
  static const double item = 16;
  static const double tile = 12;
  static const double pill = 999;
}

/// The spacing scale. Every gap in the app is one of these — a stray literal
/// is how a layout drifts out of rhythm.
class Gap {
  const Gap._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Subject colours, pulled toward the seed's hue.
///
/// Hand-picked subject colours read as random next to a generated palette —
/// six saturated hues that share nothing with the primary. Harmonising keeps
/// each subject recognisable while rotating it into the theme's temperature,
/// which is what makes the breakdown chart look designed rather than sampled.
///
/// The raw values are exposed as `const` so they can sit in a constant seed
/// table; anything that *renders* them should go through [harmonized] so the
/// chart matches the live theme.
class SubjectPalette {
  const SubjectPalette._();

  static const math = Color(0xFF4285F4);
  static const physics = Color(0xFF9C27B0);
  static const english = Color(0xFF4CAF50);
  static const history = Color(0xFFFF9800);
  static const chemistry = Color(0xFFE91E63);
  static const biology = Color(0xFF009688);

  static const all = <Color>[
    math,
    physics,
    english,
    history,
    chemistry,
    biology,
  ];

  static int get count => all.length;

  /// [primary] is the live scheme's primary, so the set re-harmonises with the
  /// theme rather than being frozen at import time.
  static List<Color> harmonized(Color primary) => [
    for (final c in all) _harmonize(c, primary),
  ];

  static Color _harmonize(Color design, Color primary) =>
      Color(mcu.Blend.harmonize(design.toARGB32(), primary.toARGB32()));
}
