// Fictional local data. Run: flutter test --no-pub tool/capture_avatars_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/study_avatar.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/features/profile/widgets/avatar_sheet.dart';
import 'package:focusforge/shared/widgets/avatars/study_portrait.dart';

void main() {
  testWidgets('review original portraits and milestone picker', (tester) async {
    tester.view.physicalSize = const Size(600, 800);
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
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    final container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    container
        .read(statsProvider.notifier)
        .hydrate(const GamificationStats(level: 15));
    await container
        .read(userProvider.notifier)
        .setStudyAvatar(StudyAvatar.sage);
    final boundary = GlobalKey();
    Future<void> capture(String name, Widget child) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.dark(),
              home: Scaffold(body: child),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/avatars/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture(
      'collection',
      GridView.count(
        crossAxisCount: 3,
        padding: const EdgeInsets.all(16),
        children: [
          for (final avatar in StudyAvatar.values)
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                StudyPortrait(avatar: avatar, size: 120),
                const SizedBox(height: 8),
                Text(avatar.label),
                Text('Level ${avatar.unlockLevel}'),
              ],
            ),
        ],
      ),
    );
    tester.view.physicalSize = const Size(360, 800);
    await capture(
      'picker',
      const Align(alignment: Alignment.bottomCenter, child: AvatarSheet()),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
