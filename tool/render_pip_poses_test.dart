// Renders Pip large, in a row of poses, on a light and a pure black page:
//   flutter test tool/render_pip_poses_test.dart
// Writes build/pip-poses/{light,amoled}.png, for reviewing Pip's look.
// PIP_WIDTH sets each figure's width in pixels (240 by default).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/features/assistant/mascot/mascot.dart';
import 'package:focusforge/features/assistant/mascot/mascot_rig.dart';

/// A rig that holds one pose.
class _Still extends MascotRig {
  _Still(this._pose);
  final MascotPose _pose;
  @override
  MascotPose get pose => _pose;
}

const _poses = <(String, MascotPose)>[
  ('stand', MascotPose()),
  ('wave', MascotPose(rightArm: MascotRig.waveArm, squint: 1, mouth: 0.5)),
  ('look', MascotPose(lookX: -0.8, lookY: 0.4, tilt: -0.12)),
  ('think', MascotPose(think: 1, antenna: 1, lookX: 0.6, lookY: -0.7)),
  ('surprise', MascotPose(surprise: 1, leftArm: 1.2, rightArm: 1.2)),
  ('sit', MascotPose(sit: 1, kick: 0.25, mouth: 0.3)),
  ('sleep', MascotPose(sit: 1, sleep: 1, tilt: 0.1)),
];

void main() {
  for (final (label, theme) in [
    ('light', AppTheme.light()),
    ('amoled', AppTheme.dark(amoled: true)),
  ]) {
    testWidgets('render Pip poses on $label', (tester) async {
      // PIP_WIDTH=600 renders each figure larger, for a closer look.
      final figure =
          double.tryParse(Platform.environment['PIP_WIDTH'] ?? '') ?? 240.0;
      final width = figure * (_poses.length + 1) + 40;
      final height = Mascot.heightFor(figure) + 60;
      tester.view.physicalSize = Size(width, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final rigs = [for (final (_, pose) in _poses) _Still(pose)];
      final head = _Still(const MascotPose());
      addTearDown(() {
        for (final rig in [...rigs, head]) {
          rig.dispose();
        }
      });
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          debugShowCheckedModeBanner: false,
          home: RepaintBoundary(
            key: boundary,
            child: ColoredBox(
              color: theme.colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final rig in rigs) Mascot(rig: rig, width: figure),
                    Mascot(rig: head, width: figure * 0.8, headOnly: true),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/pip-poses/$label.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    });
  }
}
