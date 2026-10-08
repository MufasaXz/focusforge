// Fictional data only. Run: flutter test --no-pub tool/capture_refinement_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/social.dart';
import 'package:focusforge/core/models/parent.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/parent_providers.dart';
import 'package:focusforge/core/providers/social_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/study_group_service.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/features/settings/study_groups_screen.dart';
import 'package:focusforge/features/parent/parent_control_screen.dart';
import 'package:focusforge/features/shield/breath_gate.dart';

class _CaptureGroups extends UnavailableStudyGroupService {
  const _CaptureGroups();
  @override
  bool get available => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('capture groups, parent connection and breathing phases', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final family in ['Inter', 'InterDisplay']) {
      final loader = FontLoader(family);
      for (final weight in [
        if (family == 'Inter') ...['Regular', 'Medium'],
        'SemiBold',
        'Bold',
      ]) {
        loader.addFont(rootBundle.load('assets/fonts/$family-$weight.ttf'));
      }
      await loader.load();
    }
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    final now = DateTime.utc(2026, 10, 8, 12);
    final group = StudyGroup(
      id: 'circle',
      name: 'The quiet corner',
      icon: Icons.groups_rounded,
      targetHours: 20,
      createdAt: now,
      inviteCode: 'STUDY23456',
      ownerUid: 'alex',
      memberIds: const ['alex', 'riley', 'maya'],
    );
    final c = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        shieldServiceProvider.overrideWithValue(RecordingShieldService()),
        studyGroupServiceProvider.overrideWithValue(const _CaptureGroups()),
        cloudGroupsProvider.overrideWith((ref) => Stream.value([group])),
        groupClockProvider.overrideWith((ref) => Stream.value(now)),
        groupMembersProvider('circle').overrideWith(
          (ref) => Stream.value([
            GroupMember(
              uid: 'alex',
              name: 'Alex Morgan',
              week: '2026-10-05',
              minutes: 180,
            ),
            GroupMember(
              uid: 'riley',
              name: 'Riley Chen',
              week: '2026-10-05',
              minutes: 240,
              focusUntil: now.add(const Duration(minutes: 20)),
            ),
            GroupMember(
              uid: 'maya',
              name: 'Maya Patel',
              week: '2026-10-05',
              minutes: 150,
            ),
          ]),
        ),
        guardianProvider.overrideWith(
          (ref) => Stream.value(
            GuardianLink(
              uid: 'parent',
              name: 'Sam Morgan',
              linkedAt: now,
              code: ParentCode.of('1234'),
            ),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    c
        .read(userProvider.notifier)
        .hydrate(
          const UserProfile(
            uid: 'alex',
            displayName: 'Alex Morgan',
            isAnonymous: false,
          ),
        );
    final boundary = GlobalKey();
    Widget page(Widget child, bool dark) => UncontrolledProviderScope(
      container: c,
      child: RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          home: child,
        ),
      ),
    );
    Future<void> capture(String name) async {
      expect(tester.takeException(), isNull);
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/ui-review/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    Future<void> showPage(Widget child, bool dark) async {
      // A fresh navigator is essential: a pushed group route must not survive
      // into a later screen capture under the same MaterialApp element.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(page(child, dark));
    }

    for (final dark in [true, false]) {
      final mode = dark ? 'dark' : 'light';
      await showPage(const StudyGroupsScreen(), dark);
      await tester.pumpAndSettle();
      await capture('groups-$mode');
      await tester.ensureVisible(find.text('The quiet corner'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('The quiet corner'));
      await tester.pumpAndSettle();
      await capture('group-detail-$mode');
      await showPage(const ParentControlScreen(), dark);
      await tester.pumpAndSettle();
      await capture('parent-link-$mode');
      await showPage(
        const BreathGateScreen(args: BreathGateArgs(appName: 'YouTube')),
        dark,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await capture('breathing-$mode');
      await tester.pump(const Duration(seconds: 56));
      await tester.pumpAndSettle();
      await capture('breathing-complete-$mode');
      await tester.pumpWidget(const SizedBox());
    }
  });
}
