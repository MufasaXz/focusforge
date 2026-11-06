// Renders Pip's head for the Android reminder notification:
//   flutter test tool/render_pip_head_test.dart
// Writes android/app/src/main/res/drawable-nodpi/pip_head.png. Run it again
// after changing Pip's look. Android crops a sender's picture to a circle, so
// the head sits inside the inscribed circle on a clear background.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/features/assistant/mascot/mascot.dart';
import 'package:focusforge/features/assistant/mascot/mascot_rig.dart';

void main() {
  testWidgets('render Pip head icon', (tester) async {
    const size = 256.0;
    tester.view.physicalSize = const Size(size, size);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final rig = MascotRig();
    addTearDown(rig.dispose);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        debugShowCheckedModeBanner: false,
        color: Colors.transparent,
        home: ColoredBox(
          color: Colors.transparent,
          child: Center(
            child: RepaintBoundary(
              key: boundary,
              child: SizedBox.square(
                dimension: size,
                child: Center(
                  child: Mascot(rig: rig, width: size * 0.74, headOnly: true),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await render.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('android/app/src/main/res/drawable-nodpi/pip_head.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}
