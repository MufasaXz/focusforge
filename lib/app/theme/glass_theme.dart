import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'color_tokens.dart';
import 'typography.dart';

/// Builds the Material theme for a given glass token set.
class GlassTheme {
  const GlassTheme._();

  static ThemeData dark() => _build(GlassTokens.dark, Brightness.dark);

  static ThemeData light() => _build(GlassTokens.light, Brightness.light);

  static ThemeData _build(GlassTokens t, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: t.accentPrimary,
      brightness: brightness,
    ).copyWith(
      primary: t.accentPrimary,
      secondary: t.accentSecondary,
      surface: t.canvasGradient.last,
      onSurface: t.textPrimary,
      error: t.danger,
    );

    final text = AppType.build(t);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: text,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      dividerColor: t.hairline,
      extensions: <ThemeExtension<dynamic>>[t],
      iconTheme: IconThemeData(color: t.textSecondary, size: 22),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: t.accentPrimary,
        inactiveTrackColor: t.track,
        thumbColor: t.accentPrimary,
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : t.textTertiary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? t.accentPrimary
              : t.track,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Ergonomic access to the active token set.
extension GlassTokensX on BuildContext {
  GlassTokens get glass => Theme.of(this).extension<GlassTokens>()!;
  TextTheme get type => Theme.of(this).textTheme;
}
