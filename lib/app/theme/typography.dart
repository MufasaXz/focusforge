import 'package:flutter/material.dart';

import 'color_tokens.dart';

/// Material 3 type scale rendered in Inter / Inter Display.
///
/// Inter Display is used for the largest sizes — it has tighter spacing and
/// holds up better at display sizes than the text-optimised Inter cut.
class AppType {
  const AppType._();

  static const _text = 'Inter';
  static const _display = 'InterDisplay';

  static TextTheme build(GlassTokens t) {
    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: _display,
        fontSize: 57,
        height: 64 / 57,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
        color: t.textPrimary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      displayMedium: TextStyle(
        fontFamily: _display,
        fontSize: 42,
        height: 50 / 42,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        color: t.textPrimary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      headlineMedium: TextStyle(
        fontFamily: _display,
        fontSize: 28,
        height: 36 / 28,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        color: t.textPrimary,
      ),
      titleLarge: TextStyle(
        fontFamily: _text,
        fontSize: 20,
        height: 28 / 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: t.textPrimary,
      ),
      titleMedium: TextStyle(
        fontFamily: _text,
        fontSize: 16,
        height: 24 / 16,
        fontWeight: FontWeight.w600,
        color: t.textPrimary,
      ),
      titleSmall: TextStyle(
        fontFamily: _text,
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w600,
        color: t.textPrimary,
      ),
      bodyLarge: TextStyle(
        fontFamily: _text,
        fontSize: 16,
        height: 24 / 16,
        fontWeight: FontWeight.w400,
        color: t.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontFamily: _text,
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w400,
        color: t.textSecondary,
      ),
      bodySmall: TextStyle(
        fontFamily: _text,
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w400,
        color: t.textSecondary,
      ),
      labelLarge: TextStyle(
        fontFamily: _text,
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: t.textPrimary,
      ),
      labelMedium: TextStyle(
        fontFamily: _text,
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        color: t.textSecondary,
      ),
      labelSmall: TextStyle(
        fontFamily: _text,
        fontSize: 11,
        height: 16 / 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.4,
        color: t.textTertiary,
      ),
    );
  }
}
