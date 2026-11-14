import 'package:flutter/widgets.dart';

/// Tightens type on narrow phones.
///
/// The app's type scale was set on 390–412 dp phones. On a 360 dp phone the
/// same sizes fill the width: headings wrap, labels crowd their controls and
/// a card holds half the words it does elsewhere. Below [narrowWidth] every
/// text size is multiplied by a small factor *on top of* the user's own font
/// size setting, so a person who asked for large text still gets text larger
/// than the default — just in proportion to the screen they actually have.
class CompactScale extends StatelessWidget {
  const CompactScale({super.key, required this.child});

  final Widget child;

  /// Phones narrower than this get the compact scale.
  static const double narrowWidth = 380;

  /// The multiplier for a given logical width; 1 means unchanged.
  static double factorFor(double width) {
    if (width <= 0 || width >= narrowWidth) return 1;
    return width < 340 ? 0.86 : 0.9;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final factor = factorFor(media.size.width);
    if (factor == 1) return child;
    return MediaQuery(
      data: media.copyWith(
        textScaler: _ScaledTextScaler(media.textScaler, factor),
      ),
      child: child,
    );
  }
}

/// [base] — which may be Android 14's non-linear scaler — times [factor].
class _ScaledTextScaler extends TextScaler {
  const _ScaledTextScaler(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  // Required by the interface; new code reads [scale].
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * factor;

  @override
  bool operator ==(Object other) =>
      other is _ScaledTextScaler &&
      other.base == base &&
      other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}
