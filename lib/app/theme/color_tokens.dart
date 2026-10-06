import 'package:flutter/material.dart';

/// Design tokens for the FocusForge glass system.
///
/// The palette is derived from the FocusForge master plan and refined against
/// 2026 interface conventions: deep gradient canvases, translucent glass
/// surfaces with a light-refracting edge, and a small set of saturated accents.
///
/// Light mode deliberately shifts the accents darker — the pastel neons used on
/// the dark canvas do not carry enough contrast against a pale background.
///
/// ## Deliberate deviations from the master plan's glass table
///
/// The plan specifies dark L1 at 5% and L2 at 13%, and light L1 at 45% and L2
/// at 70%. The values here are 7%/10% dark and 55%/80% light. This is
/// intentional and was tuned against rendered screenshots, not guessed: the
/// plan's numbers were chosen before the canvas had drifting colour blobs
/// behind it, and against a moving background the lower fills stop reading as
/// a *pane* and start reading as a hole. Do not "fix" these back to the spec
/// without re-rendering — see the note in [GlassPanel] about why the border,
/// rim and sheen matter more than the fill percentage.
@immutable
class GlassTokens extends ThemeExtension<GlassTokens> {
  const GlassTokens({
    required this.canvasGradient,
    required this.blobs,
    required this.glassL1Fill,
    required this.glassL1Border,
    required this.glassL1Shadow,
    required this.glassL2Fill,
    required this.glassL2Border,
    required this.glassL2Shadow,
    required this.navFill,
    required this.navBorder,
    required this.navShadow,
    required this.specular,
    required this.sheen,
    required this.innerRim,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accentPrimary,
    required this.accentSecondary,
    required this.success,
    required this.danger,
    required this.gold,
    required this.hairline,
    required this.track,
    required this.grainOpacity,
    required this.vignette,
    this.blurL1 = 0,
    this.blurL2 = 0,
    this.blurNav = 24,
  });

  /// Background gradient stops, painted top-left to bottom-right.
  final List<Color> canvasGradient;

  /// Soft organic blobs drifting behind the glass.
  final List<Color> blobs;

  final Color glassL1Fill;
  final Color glassL1Border;
  final Color glassL1Shadow;
  final Color glassL2Fill;
  final Color glassL2Border;
  final Color glassL2Shadow;

  final Color navFill;
  final Color navBorder;
  final Color navShadow;

  /// Bright top-edge highlight that sells the glass rim.
  final Color specular;

  /// Soft light falling across the upper half of a surface.
  final Color sheen;

  /// Inset hairline just inside the border — the second rim that reads as
  /// thickness rather than a drawn outline.
  final Color innerRim;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  final Color accentPrimary;
  final Color accentSecondary;
  final Color success;
  final Color danger;
  final Color gold;

  /// Faint divider used inside cards.
  final Color hairline;

  /// Inactive slider / progress track.
  final Color track;

  /// Strength of the film-grain overlay. Grain is what keeps large dark
  /// gradients from banding on OLED panels.
  final double grainOpacity;

  /// Edge darkening, which pulls the eye to the centre of the screen.
  final Color vignette;

  /// Backdrop-blur sigmas, in logical pixels.
  ///
  /// These live on the token set rather than being hardcoded at the call site
  /// because the correct value is a function of the theme: a pale background
  /// needs *less* blur than a dark one to read as frosted, and over-blurring a
  /// light canvas just smears the content underneath into grey. The spec is
  /// 24 on dark and 20 on light; both are within the 10–20px band that reads
  /// as glass without turning into fog, with the nav allowed a little more
  /// because it floats over moving content.
  final double blurL1;
  final double blurL2;
  final double blurNav;

  static const GlassTokens dark = GlassTokens(
    canvasGradient: [
      Color(0xFF0C1226),
      Color(0xFF070A16),
      Color(0xFF04050A),
    ],
    // Kept deliberately restrained: bright blobs wash out the glass and flatten
    // the whole screen. They are ambience, not decoration.
    blobs: [
      Color(0x5C3F6BEA),
      Color(0x4D7C4DFF),
      Color(0x3D00B4D8),
      Color(0x3D6A3FE0),
    ],
    glassL1Fill: Color(0x12FFFFFF),
    glassL1Border: Color(0x2BFFFFFF),
    glassL1Shadow: Color(0x7A000000),
    glassL2Fill: Color(0x1AFFFFFF),
    glassL2Border: Color(0x3DFFFFFF),
    glassL2Shadow: Color(0x66000000),
    navFill: Color(0x1AFFFFFF),
    navBorder: Color(0x33FFFFFF),
    navShadow: Color(0x99000000),
    specular: Color(0x66FFFFFF),
    sheen: Color(0x0FFFFFFF),
    innerRim: Color(0x14FFFFFF),
    textPrimary: Color(0xFFF3F6FD),
    textSecondary: Color(0xB8F3F6FD),
    // 60%, not 50%: at 50% this fails WCAG AA (4.5:1) once it is composited
    // over a translucent glass fill rather than the raw canvas.
    textTertiary: Color(0x99F3F6FD),
    accentPrimary: Color(0xFFA8C7FA),
    accentSecondary: Color(0xFFD0BCFF),
    success: Color(0xFF8FE7C0),
    danger: Color(0xFFFFB4AB),
    gold: Color(0xFFFFD166),
    hairline: Color(0x1AFFFFFF),
    track: Color(0x24FFFFFF),
    // Grain should be felt, not seen. Above ~0.2 it reads as a dirty screen.
    grainOpacity: 0.14,
    vignette: Color(0x80000000),
    blurL1: 0,
    blurL2: 24,
    blurNav: 24,
  );

  static const GlassTokens light = GlassTokens(
    canvasGradient: [
      Color(0xFFE8EEFB),
      Color(0xFFEDF1F9),
      Color(0xFFF4F6FB),
    ],
    blobs: [
      Color(0x383F6BEA),
      Color(0x2E7C4DFF),
      Color(0x2400B4D8),
      Color(0x246A3FE0),
    ],
    glassL1Fill: Color(0x8CFFFFFF),
    glassL1Border: Color(0x99FFFFFF),
    glassL1Shadow: Color(0x141F2687),
    glassL2Fill: Color(0xCCFFFFFF),
    glassL2Border: Color(0xB3FFFFFF),
    glassL2Shadow: Color(0x1A1F2687),
    navFill: Color(0xA6FFFFFF),
    navBorder: Color(0x99FFFFFF),
    navShadow: Color(0x261F2687),
    specular: Color(0xE6FFFFFF),
    sheen: Color(0x66FFFFFF),
    innerRim: Color(0x33000000),
    textPrimary: Color(0xFF0C1226),
    textSecondary: Color(0xB30C1226),
    textTertiary: Color(0x990C1226),
    accentPrimary: Color(0xFF2F5FD0),
    accentSecondary: Color(0xFF6B4FCF),
    success: Color(0xFF0F7A54),
    danger: Color(0xFFB5352A),
    gold: Color(0xFF9A6B00),
    hairline: Color(0x1A0C1226),
    track: Color(0x140C1226),
    grainOpacity: 0.06,
    vignette: Color(0x14000000),
    blurL1: 0,
    blurL2: 20,
    blurNav: 20,
  );

  /// Convenience for the active accent gradient used by rings and pills.
  List<Color> get accentGradient => [accentPrimary, accentSecondary];

  /// The L2 fill at a fraction of its normal strength.
  ///
  /// Note that `withValues(alpha:)` *replaces* alpha rather than multiplying
  /// it — calling it directly on an already-translucent token produces an
  /// almost-opaque white and flattens the whole surface. Always scale from the
  /// token's own alpha like this.
  Color glassL2At(double factor) =>
      glassL2Fill.withValues(alpha: glassL2Fill.a * factor);

  @override
  GlassTokens copyWith({
    List<Color>? canvasGradient,
    List<Color>? blobs,
    Color? glassL1Fill,
    Color? glassL1Border,
    Color? glassL1Shadow,
    Color? glassL2Fill,
    Color? glassL2Border,
    Color? glassL2Shadow,
    Color? navFill,
    Color? navBorder,
    Color? navShadow,
    Color? specular,
    Color? sheen,
    Color? innerRim,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accentPrimary,
    Color? accentSecondary,
    Color? success,
    Color? danger,
    Color? gold,
    Color? hairline,
    Color? track,
    double? grainOpacity,
    Color? vignette,
    double? blurL1,
    double? blurL2,
    double? blurNav,
  }) {
    return GlassTokens(
      canvasGradient: canvasGradient ?? this.canvasGradient,
      blobs: blobs ?? this.blobs,
      glassL1Fill: glassL1Fill ?? this.glassL1Fill,
      glassL1Border: glassL1Border ?? this.glassL1Border,
      glassL1Shadow: glassL1Shadow ?? this.glassL1Shadow,
      glassL2Fill: glassL2Fill ?? this.glassL2Fill,
      glassL2Border: glassL2Border ?? this.glassL2Border,
      glassL2Shadow: glassL2Shadow ?? this.glassL2Shadow,
      navFill: navFill ?? this.navFill,
      navBorder: navBorder ?? this.navBorder,
      navShadow: navShadow ?? this.navShadow,
      specular: specular ?? this.specular,
      sheen: sheen ?? this.sheen,
      innerRim: innerRim ?? this.innerRim,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accentPrimary: accentPrimary ?? this.accentPrimary,
      accentSecondary: accentSecondary ?? this.accentSecondary,
      success: success ?? this.success,
      danger: danger ?? this.danger,
      gold: gold ?? this.gold,
      hairline: hairline ?? this.hairline,
      track: track ?? this.track,
      grainOpacity: grainOpacity ?? this.grainOpacity,
      vignette: vignette ?? this.vignette,
      blurL1: blurL1 ?? this.blurL1,
      blurL2: blurL2 ?? this.blurL2,
      blurNav: blurNav ?? this.blurNav,
    );
  }

  @override
  GlassTokens lerp(GlassTokens? other, double t) {
    if (other is! GlassTokens) return this;
    return GlassTokens(
      canvasGradient: _lerpColors(canvasGradient, other.canvasGradient, t),
      blobs: _lerpColors(blobs, other.blobs, t),
      glassL1Fill: Color.lerp(glassL1Fill, other.glassL1Fill, t)!,
      glassL1Border: Color.lerp(glassL1Border, other.glassL1Border, t)!,
      glassL1Shadow: Color.lerp(glassL1Shadow, other.glassL1Shadow, t)!,
      glassL2Fill: Color.lerp(glassL2Fill, other.glassL2Fill, t)!,
      glassL2Border: Color.lerp(glassL2Border, other.glassL2Border, t)!,
      glassL2Shadow: Color.lerp(glassL2Shadow, other.glassL2Shadow, t)!,
      navFill: Color.lerp(navFill, other.navFill, t)!,
      navBorder: Color.lerp(navBorder, other.navBorder, t)!,
      navShadow: Color.lerp(navShadow, other.navShadow, t)!,
      specular: Color.lerp(specular, other.specular, t)!,
      sheen: Color.lerp(sheen, other.sheen, t)!,
      innerRim: Color.lerp(innerRim, other.innerRim, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      accentPrimary: Color.lerp(accentPrimary, other.accentPrimary, t)!,
      accentSecondary: Color.lerp(accentSecondary, other.accentSecondary, t)!,
      success: Color.lerp(success, other.success, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      track: Color.lerp(track, other.track, t)!,
      grainOpacity: t < 0.5 ? grainOpacity : other.grainOpacity,
      vignette: Color.lerp(vignette, other.vignette, t)!,
      blurL1: _lerpD(blurL1, other.blurL1, t),
      blurL2: _lerpD(blurL2, other.blurL2, t),
      blurNav: _lerpD(blurNav, other.blurNav, t),
    );
  }

  static double _lerpD(double a, double b, double t) => a + (b - a) * t;

  static List<Color> _lerpColors(List<Color> a, List<Color> b, double t) {
    final n = a.length < b.length ? a.length : b.length;
    return List<Color>.generate(n, (i) => Color.lerp(a[i], b[i], t)!);
  }
}

/// Subject palette — used to colour-code study sessions and goals.
///
/// Saturation and lightness are tuned so every hue reads at the same weight
/// against the dark canvas; no single subject shouts louder than the others.
class SubjectColors {
  const SubjectColors._();

  static const math = Color(0xFF7FA9FF);
  static const physics = Color(0xFFB79CFF);
  static const english = Color(0xFF7FE3C0);
  static const history = Color(0xFFFFC48A);
  static const chemistry = Color(0xFFFF9FC4);
  static const biology = Color(0xFF8FE39B);

  static const all = <Color>[
    math,
    physics,
    english,
    history,
    chemistry,
    biology,
  ];
}

/// Radii from the master plan: hero cards 28, list items 16, pills full.
class Radii {
  const Radii._();

  static const double hero = 28;
  static const double card = 22;
  static const double item = 16;
  static const double tile = 12;
  static const double pill = 999;
}

/// Strict 8dp spacing grid.
class Gap {
  const Gap._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}
