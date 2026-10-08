import 'package:flutter/material.dart';

/// Material 3 type scale rendered in Inter / Inter Display.
///
/// Inter Display is used for the largest sizes — it has tighter spacing and
/// holds up better at display sizes than the text-optimised Inter cut.
///
/// Colours come from the scheme rather than being baked in: the same scale has
/// to render on a light and a dark surface, and a literal colour here would
/// survive a theme switch and go unreadable.
class AppType {
  const AppType._();

  static const _text = 'Inter';
  static const _display = 'InterDisplay';

  static TextTheme build(ColorScheme cs) {
    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: _display,
        fontSize: 57,
        height: 64 / 57,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
        color: cs.onSurface,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      displayMedium: TextStyle(
        fontFamily: _display,
        fontSize: 42,
        height: 50 / 42,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        color: cs.onSurface,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      displaySmall: TextStyle(
        fontFamily: _display,
        fontSize: 36,
        height: 44 / 36,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.6,
        color: cs.onSurface,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      headlineLarge: TextStyle(
        fontFamily: _display,
        fontSize: 32,
        height: 40 / 32,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        color: cs.onSurface,
      ),
      headlineMedium: TextStyle(
        fontFamily: _display,
        fontSize: 28,
        height: 36 / 28,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        color: cs.onSurface,
      ),
      headlineSmall: TextStyle(
        fontFamily: _display,
        fontSize: 24,
        height: 32 / 24,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: cs.onSurface,
      ),
      titleLarge: TextStyle(
        fontFamily: _text,
        fontSize: 20,
        height: 28 / 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: cs.onSurface,
      ),
      titleMedium: TextStyle(
        fontFamily: _text,
        fontSize: 16,
        height: 24 / 16,
        fontWeight: FontWeight.w600,
        color: cs.onSurface,
      ),
      titleSmall: TextStyle(
        fontFamily: _text,
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w600,
        color: cs.onSurface,
      ),
      bodyLarge: TextStyle(
        fontFamily: _text,
        fontSize: 16,
        height: 24 / 16,
        fontWeight: FontWeight.w400,
        color: cs.onSurface,
      ),
      bodyMedium: TextStyle(
        fontFamily: _text,
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w400,
        color: cs.onSurfaceVariant,
      ),
      bodySmall: TextStyle(
        fontFamily: _text,
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w400,
        color: cs.onSurfaceVariant,
      ),
      labelLarge: TextStyle(
        fontFamily: _text,
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: cs.onSurface,
      ),
      labelMedium: TextStyle(
        fontFamily: _text,
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        color: cs.onSurfaceVariant,
      ),
      labelSmall: TextStyle(
        fontFamily: _text,
        fontSize: 11,
        height: 16 / 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.4,
        color: cs.onSurfaceVariant,
      ),
    );
  }
}
