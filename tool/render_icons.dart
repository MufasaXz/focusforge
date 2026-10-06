// Icon generator. Renders the FocusForge mark to every launcher, splash and
// PWA asset the project ships, from one geometry — so the launcher icon, the
// native splash and the in-app mark cannot drift apart.
//
// Run it explicitly:
//
//     flutter test tool/render_icons.dart
//
// It lives outside `test/` on purpose: `flutter test` only scans `test/`, so
// this never runs as part of the suite and never rewrites committed assets
// behind your back.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ember the whole app is tinted from. Must stay equal to
/// `AppMark.seed` and to `@color/ic_launcher_background`.
const _seed = Color(0xFFE8672A);
const _onSeed = Colors.white;

/// Geometry shared with `lib/shared/widgets/app_mark.dart`.
const _cornerRatio = 0.235;
const _gapRatio = 0.155;
const _ringRadius = 0.285;
const _ringStroke = 0.085;
const _coreRadius = 0.115;

/// Paints the mark into a square canvas of [size].
///
/// [inset] is the fraction of the side left clear on every edge — adaptive and
/// maskable icons need it so the launcher's own crop cannot clip the ring.
/// [plate] draws the rounded ember square behind the mark; the Android
/// adaptive foreground and the splash mark leave it off and stay transparent.
Future<Uint8List> _render(
  double size, {
  double inset = 0,
  bool plate = true,
  Color mark = _onSeed,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final s = size;

  if (plate) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, s, s),
        Radius.circular(s * _cornerRatio),
      ),
      Paint()..color = _seed,
    );
  }

  canvas.save();
  canvas.translate(s * inset, s * inset);
  canvas.scale(1 - inset * 2);

  final centre = Offset(s / 2, s / 2);
  final gap = 2 * math.pi * _gapRatio;
  canvas.drawArc(
    Rect.fromCircle(center: centre, radius: s * _ringRadius),
    -math.pi / 2 + gap / 2,
    2 * math.pi - gap,
    false,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * _ringStroke
      ..strokeCap = StrokeCap.round
      ..color = mark,
  );
  canvas.drawCircle(centre, s * _coreRadius, Paint()..color = mark);
  canvas.restore();

  final image = await recorder.endRecording().toImage(s.round(), s.round());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<void> _write(String path, Uint8List bytes) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
  stdout.writeln('wrote $path (${bytes.length} bytes)');
}

/// The five Android densities, as (bucket, launcher size, adaptive canvas).
const _densities = {
  'mdpi': (48.0, 108.0, 96.0),
  'hdpi': (72.0, 162.0, 144.0),
  'xhdpi': (96.0, 216.0, 192.0),
  'xxhdpi': (144.0, 324.0, 288.0),
  'xxxhdpi': (192.0, 432.0, 384.0),
};

void main() {
  test('render launcher, splash and PWA icons', () async {
    for (final entry in _densities.entries) {
      final (launcher, adaptive, splash) = entry.value;

      // The legacy bitmap, still what pre-API-26 devices and the Play Store
      // listing use.
      await _write(
        'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
        await _render(launcher),
      );

      // Adaptive foreground: a 108dp canvas whose safe zone is the central
      // 66dp, so the mark is drawn at 61% and centred.
      await _write(
        'android/app/src/main/res/drawable-${entry.key}/ic_launcher_foreground.png',
        await _render(adaptive, inset: 0.195, plate: false),
      );

      // The native splash mark: ember on a transparent ground, so the launch
      // background colour shows through and the two themes each get their own.
      await _write(
        'android/app/src/main/res/drawable-${entry.key}/ff_launch_mark.png',
        await _render(splash, mark: _seed, plate: false),
      );
    }

    // Maskable PWA icons are cropped to a circle by the launcher, so the mark
    // is inset into the safe zone instead of running to the edge.
    const maskableInset = 0.12;
    await _write('web/icons/Icon-192.png', await _render(192));
    await _write('web/icons/Icon-512.png', await _render(512));
    await _write(
      'web/icons/Icon-maskable-192.png',
      await _render(192, inset: maskableInset),
    );
    await _write(
      'web/icons/Icon-maskable-512.png',
      await _render(512, inset: maskableInset),
    );
    await _write('web/favicon.png', await _render(32));
  });
}
