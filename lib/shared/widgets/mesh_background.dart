import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/theme/glass_theme.dart';

/// The app canvas: a deep gradient, slow-drifting colour blobs, a light source
/// in the top corner, a vignette and a film-grain overlay.
///
/// The blobs are drawn sharp and blurred once as a layer, rather than blurred
/// per circle with [MaskFilter]: the controller runs for 48 seconds at a time,
/// so a per-frame mask filter meant four full re-rasterisations of a 110px blur
/// every frame — the single most expensive thing on the dashboard's raster
/// thread. One [ImageFiltered] pass over the composited layer looks the same
/// and costs one filter instead of four.
///
/// The grain is generated once and tiled — it is the detail that stops large
/// dark gradients from banding on OLED panels, which is most of what separates
/// a rich dark theme from a flat one.
class MeshBackground extends StatefulWidget {
  const MeshBackground({super.key, required this.child});

  final Widget child;

  @override
  State<MeshBackground> createState() => _MeshBackgroundState();
}

class _MeshBackgroundState extends State<MeshBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 48),
  )..repeat();

  ui.Image? _grain;

  @override
  void initState() {
    super.initState();
    _makeGrain().then((img) {
      if (mounted) setState(() => _grain = img);
    });
  }

  /// Builds a tileable noise texture. Kept small and drawn once — it is tiled
  /// with [ImageRepeat.repeat], not regenerated per frame.
  static Future<ui.Image> _makeGrain() async {
    const size = 128;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rnd = math.Random(20261006);
    final paint = Paint();

    for (var i = 0; i < 6500; i++) {
      final a = (rnd.nextDouble() * 20).toInt();
      paint.color = Color.fromARGB(a, 255, 255, 255);
      canvas.drawCircle(
        Offset(rnd.nextDouble() * size, rnd.nextDouble() * size),
        rnd.nextDouble() * 0.55 + 0.12,
        paint,
      );
    }
    return recorder.endRecording().toImage(size, size);
  }

  @override
  void dispose() {
    _controller.dispose();
    _grain?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.glass;
    final grain = _grain;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: t.canvasGradient,
          stops: const [0, 0.55, 1],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 110, sigmaY: 110),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => CustomPaint(
                  painter: _MeshPainter(
                    progress: _controller.value,
                    colors: t.blobs,
                  ),
                ),
              ),
            ),
          ),
          // Corner light source.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.85, -0.9),
                  radius: 1.1,
                  colors: [
                    t.accentPrimary.withValues(alpha: 0.10),
                    t.accentPrimary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          // Vignette — pulls focus to the centre column.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.95,
                  colors: [t.vignette.withValues(alpha: 0), t.vignette],
                ),
              ),
            ),
          ),
          if (grain != null)
            IgnorePointer(
              child: Opacity(
                opacity: t.grainOpacity,
                child: RawImage(
                  image: grain,
                  repeat: ImageRepeat.repeat,
                  filterQuality: FilterQuality.none,
                  fit: BoxFit.none,
                ),
              ),
            ),
          widget.child,
        ],
      ),
    );
  }
}

class _MeshPainter extends CustomPainter {
  _MeshPainter({required this.progress, required this.colors});

  final double progress;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final shortest = math.min(size.width, size.height);
    final radius = shortest * 0.52;

    const phases = [0.0, 0.27, 0.53, 0.78];
    const orbits = [
      Offset(0.24, 0.17),
      Offset(0.21, 0.26),
      Offset(0.17, 0.19),
      Offset(0.25, 0.15),
    ];
    const anchors = [
      Offset(0.14, 0.08),
      Offset(0.88, 0.20),
      Offset(0.22, 0.80),
      Offset(0.80, 0.90),
    ];

    for (var i = 0; i < colors.length && i < anchors.length; i++) {
      final angle = (progress + phases[i]) * 2 * math.pi;
      final center = Offset(
        (anchors[i].dx + math.cos(angle) * orbits[i].dx) * size.width,
        (anchors[i].dy + math.sin(angle) * orbits[i].dy) * size.height,
      );
      // Sharp on purpose — the blur is applied once to the whole layer above.
      canvas.drawCircle(center, radius, Paint()..color = colors[i]);
    }
  }

  @override
  bool shouldRepaint(_MeshPainter old) =>
      old.progress != progress || old.colors != colors;
}
