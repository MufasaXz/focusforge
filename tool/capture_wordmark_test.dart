// Captures the login wordmark fill at a few moments into build/wordmark.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/features/onboarding/fill_wordmark.dart';

void main() {
  testWidgets('capture the wordmark fill', (tester) async {
    tester.view.physicalSize = const Size(360, 120);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
    final key = GlobalKey();
    final theme = AppTheme.dark();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: Container(
                color: theme.colorScheme.surface,
                padding: const EdgeInsets.all(16),
                child: FillWordmark(
                  text: 'FocusForge',
                  style: theme.textTheme.headlineLarge!.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                  ),
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    var elapsed = 0;
    for (final ms in [0, 500, 900, 1300, 1800, 2600, 3500]) {
      await tester.pump(Duration(milliseconds: ms - elapsed));
      elapsed = ms;
      final render =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/wordmark/fill-$ms.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpAndSettle();
  });
}
