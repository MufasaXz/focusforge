import 'package:flutter/material.dart';

import 'mascot_painter.dart';
import 'mascot_rig.dart';

/// The assistant's name. Shown as written in every language.
const String kBuddyName = 'Pip';

/// Pip, drawn at [width] and driven by [rig].
///
/// The rig belongs to the caller, which decides what Pip does; this widget
/// only lends it a ticker and keeps it told about reduce motion.
class Mascot extends StatefulWidget {
  const Mascot({
    super.key,
    required this.rig,
    required this.width,
    this.headOnly = false,
  });

  final MascotRig rig;
  final double width;

  /// Just the head, ears and antenna — the chat's profile picture.
  final bool headOnly;

  /// Height for a given [width], for callers that lay Pip out.
  static double heightFor(double width, {bool headOnly = false}) => headOnly
      ? width * MascotPainter.headBox.height / MascotPainter.headBox.width
      : width * MascotPainter.fullAspect;

  @override
  State<Mascot> createState() => _MascotState();
}

class _MascotState extends State<Mascot> with TickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    widget.rig.attach(this);
  }

  @override
  void didUpdateWidget(covariant Mascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rig != widget.rig) {
      oldWidget.rig.detach();
      widget.rig.attach(this);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.rig.reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void dispose() {
    widget.rig.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = Size(
      widget.width,
      Mascot.heightFor(widget.width, headOnly: widget.headOnly),
    );
    return RepaintBoundary(
      child: CustomPaint(
        size: size,
        painter: MascotPainter(
          rig: widget.rig,
          colors: MascotColors.of(Theme.of(context)),
          headOnly: widget.headOnly,
        ),
      ),
    );
  }
}
