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

      // Flat, hairline-ruled cards.
      //
      // Three of the reference apps arrived at the same treatment from
      // different directions — zero elevation, no tonal fill, and a 1dp
      // `outlineVariant` border at roughly 40% — and it is the better answer
      // here than a tonal surface. A container fill has to be re-tuned for
      // every surface it sits on, and this app nests cards inside sheets inside
      // pages; a border says "this is a group" once and stays legible on all of
      // them. It also survives the light/dark switch without a second guess.
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
        color: cs.surface,
        surfaceTintColor: Colors.transparent,
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

/// How the app moves.
///
/// Named by intent rather than by number so a screen asks for "the emphasised
/// entrance" instead of guessing at 400ms and 0.2/0/0/1 for the fortieth time.
/// Two curves cover everything: [standard] for anything the user caused
/// directly, [emphasized] for anything that changes what is on screen — a
/// section appearing, a state flipping, a value committing. The spring is for
/// the things that should feel physical: a bar growing, a tile settling, a
/// press releasing.
class Motion {
  const Motion._();

  /// Material 3's emphasised easing. Slow out, slow in, decisive through the
  /// middle — the curve that makes a transition read as deliberate rather than
  /// as a jump cut with a fade on it.
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);

  /// For direct manipulation: a tap, a hover, a toggle. Symmetric, so the
  /// return trip looks like the outbound one.
  static const Curve standard = Curves.easeInOutCubic;

  /// A bar that grows, a ring that fills — anything with momentum.
  static const Curve decelerate = Curves.easeOutCubic;

  /// A tile settling into place. Damped enough to stop, loose enough that the
  /// overshoot is visible.
  static const SpringDescription settle = SpringDescription(
    mass: 1,
    stiffness: 350,
    damping: 0.7,
  );

  /// How far a pressable shrinks under a finger. Small: a control that visibly
  /// collapses reads as broken, not as responsive.
  static const double pressScale = 0.94;

  /// The quickest motion in the app — a state that has to acknowledge a tap
  /// inside a frame budget.
  static const Duration quick = Duration(milliseconds: 150);

  /// The default for anything that changes content in place.
  static const Duration base = Duration(milliseconds: 220);

  /// For a screen-level change: a section appearing, a sheet settling.
  static const Duration emphasizedDuration = Duration(milliseconds: 400);

  /// For the one or two moments that should be noticed — a chart drawing
  /// itself for the first time.
  static const Duration deliberate = Duration(milliseconds: 550);
}

/// Rotates a categorical colour into the live theme's temperature.
///
/// Some colours in the app are *data*, not chrome: a subject's hue, a
/// whitelist tier's green/amber/red, a persona's tint. Those need to stay
/// distinguishable from each other, so they cannot simply become scheme roles —
/// but left raw they are six saturated hues from a palette that no longer
/// exists, sitting next to a generated ember scheme. Harmonising keeps the
/// distinction and drops the clash.
Color harmonize(Color design, Color primary) =>
    Color(mcu.Blend.harmonize(design.toARGB32(), primary.toARGB32()));

/// Subject colours, pulled toward the seed's hue.
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
    for (final c in all) harmonize(c, primary),
  ];
}
