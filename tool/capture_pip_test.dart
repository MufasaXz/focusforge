// Design-review captures of Pip: a sheet of poses, Pip on Home, and the chat
// with its cards, in light, dark and AMOLED, with fictional local data.
// Run: flutter test tool/capture_pip_test.dart
// Writes PNGs to build/pip; never changes a user's stored data.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/app.dart';
import 'package:focusforge/app/router.dart';
import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/focus_goal.dart';
import 'package:focusforge/core/models/study.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/goal_planner_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/providers/usage_providers.dart';
import 'package:focusforge/core/services/app_catalog.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/shield_service.dart';
import 'package:focusforge/features/assistant/assistant_memory.dart';
import 'package:focusforge/features/assistant/brain/assistant_models.dart';
import 'package:focusforge/features/assistant/brain/study_snapshot.dart';
import 'package:focusforge/features/assistant/chat/chat_controller.dart';
import 'package:focusforge/features/assistant/mascot/mascot.dart';
import 'package:focusforge/features/assistant/mascot/mascot_rig.dart';

void main() {
  testWidgets('capture Pip', (tester) async {
    debugDisableShadows = false;
    tester.view.physicalSize = Platform.environment["PIP_PHONE"] == "small" ? const Size(360, 800) : const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    // Store screenshots: room for a status bar and gesture bar, rendered big.
    if (_storeScale != null) {
      tester.view.padding = const FakeViewPadding(top: 40, bottom: 20);
    }
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
    // The capture harness is a test kept outside the default suite.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await store.setBool(StoreKeys.coachSeen, true);
    await store.setMap(StoreKeys.usageCategories, {
      'com.example.social': 'distracting',
      'com.example.video': 'distracting',
    });
    final engine = RecordingShieldService();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        accountUidProvider.overrideWithValue('capture-user'),
        shieldServiceProvider.overrideWithValue(engine),
        appBlockingSupportedProvider.overrideWithValue(true),
        appListConsentProvider.overrideWith(() => AppListConsentNotifier(true)),
        installedAppsProvider.overrideWith(
          (ref) async => const [
            InstalledApp(
              packageId: 'com.example.social',
              name: 'Instagram',
              isSystem: false,
            ),
            InstalledApp(
              packageId: 'com.example.video',
              name: 'YouTube',
              isSystem: false,
            ),
            InstalledApp(
              packageId: 'com.example.notes',
              name: 'Notes',
              isSystem: false,
            ),
          ],
        ),
        appUsageTodayProvider.overrideWith(
          (ref) async => const {
            'com.example.social': 52,
            'com.example.video': 34,
            'com.example.notes': 20,
          },
        ),
        usageAccessProvider.overrideWith((ref) async => true),
        shieldEnabledProvider.overrideWith((ref) async => true),
        overlayAccessProvider.overrideWith((ref) async => true),
        appBlockingRunningProvider.overrideWith((ref) async => true),
        appBlockingPausedProvider.overrideWith((ref) async => false),
        accountUidProvider.overrideWith((ref) => 'me'),
      ],
    );
    var disposed = false;
    void close() {
      if (disposed) return;
      disposed = true;
      container.dispose();
      engine.dispose();
    }

    addTearDown(close);

    container
        .read(userProvider.notifier)
        .hydrate(
          const UserProfile(
            uid: 'me',
            displayName: 'Alex Morgan',
            onboardingComplete: true,
            isAnonymous: false,
          ),
        );
    container.read(subjectsProvider.notifier).hydrate([
      for (final (id, name, icon, color) in [
        ('math', 'Mathematics', 'calculate', SubjectPalette.math),
        ('physics', 'Physics', 'science', SubjectPalette.physics),
        ('chemistry', 'Chemistry', 'science', SubjectPalette.chemistry),
      ])
        Subject(
          id: id,
          name: name,
          icon: Icons.menu_book_rounded,
          color: color,
          weekTarget: 6,
        ).toJson()..['icon'] = icon,
    ]);
    final monday = DateTime(
      today.year,
      today.month,
      today.day - today.weekday + 1,
    );
    final sessions = <FocusSession>[];
    var n = 0;
    void log(DateTime day, String subject, int minutes, int hour) {
      if (day.isAfter(today)) return;
      sessions.add(
        FocusSession(
          id: 'pip-${n++}',
          subjectId: subject,
          startedAt: DateTime(day.year, day.month, day.day, hour),
          minutes: minutes,
        ),
      );
    }

    for (var d = 0; d < 7; d++) {
      final last = DateTime(monday.year, monday.month, monday.day - 7 + d);
      // An uneven week, like a real one: a big Tuesday, a light Friday.
      const shape = [1.0, 1.4, 0.9, 1.2, 0.5, 1.6, 0.4];
      log(last, 'chemistry', (60 * shape[d]).round(), 18);
      log(last, 'physics', (40 * shape[d]).round(), 19);
      log(last, 'math', (30 * shape[d]).round(), 20);
    }
    for (var d = 0; d < today.weekday; d++) {
      final day = DateTime(monday.year, monday.month, monday.day + d);
      log(day, 'math', 50, 18);
      log(day, 'physics', 45, 19);
      if (d.isEven) log(day, 'chemistry', 20, 20);
    }
    container
        .read(sessionsProvider.notifier)
        .hydrate(sessions.map((session) => session.toJson()).toList());
    await container
        .read(focusGoalPlannerProvider.notifier)
        .save(
          FocusGoalPlan(
            scope: FocusGoalScope.day,
            date: today,
            totalMinutes: 240,
            subjectMinutes: const {},
          ),
        );

    final boundary = GlobalKey();
    Widget scope(Widget child) => UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(key: boundary, child: child),
    );
    final only = Platform.environment['CAPTURE_ONLY'];
    Future<void> frames(Duration length) async {
      for (var t = 0; t < length.inMilliseconds; t += 16) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    Future<void> capture(String name) async {
      expect(tester.takeException(), isNull);
      if (only != null && !name.startsWith(only)) return;
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: _storeScale ?? 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/pip/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    final themes = <String, ThemeData>{
      'light': AppTheme.light(),
      'dark': AppTheme.dark(),
      'amoled': AppTheme.dark(amoled: true),
    };

    // -- Poses ----------------------------------------------------------------
    const poses = [
      'stand',
      'wave',
      'present',
      'look',
      'talk',
      'cheer',
      'think',
      'sit',
      'sleep',
      'head',
      'yawn',
      'wiggle',
      'tilt',
      'swing',
    ];
    for (final MapEntry(key: label, value: theme) in themes.entries) {
      final rigs = {for (final pose in poses) pose: MascotRig()};
      await tester.pumpWidget(
        scope(
          MaterialApp(
            theme: theme,
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(
                child: Wrap(
                  spacing: 18,
                  runSpacing: 22,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final pose in poses)
                      SizedBox(
                        width: 100,
                        child: Column(
                          children: [
                            Mascot(
                              rig: rigs[pose]!,
                              width: pose == 'head' ? 72 : 96,
                              headOnly: pose == 'head',
                            ),
                            const SizedBox(height: 6),
                            Text(pose),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      rigs['sit']!.sitDown();
      rigs['swing']!.sitDown();
      rigs['sleep']!.fallAsleep();
      rigs['look']!.lookAt(-0.9, 0.35);
      rigs['present']!.presenting = true;
      await frames(const Duration(milliseconds: 1500));
      rigs['yawn']!.yawn();
      rigs['wiggle']!.wiggle();
      rigs['tilt']!.tiltCurious(1);
      rigs['swing']!.swingFeet();
      rigs['think']!.thinking = true;
      await frames(const Duration(milliseconds: 400));
      rigs['sleep']!.puff();
      await frames(const Duration(milliseconds: 150));
      rigs['wave']!.wave(seconds: 3);
      await frames(const Duration(milliseconds: 250));
      rigs['cheer']!.cheer();
      await frames(const Duration(milliseconds: 80));
      rigs['talk']!.talk(seconds: 2);
      await frames(const Duration(milliseconds: 120));
      await capture('poses-$label');
      await tester.pumpWidget(const SizedBox.shrink());
      for (final rig in rigs.values) {
        rig.dispose();
      }
    }

    if (only?.startsWith('poses') ?? false) {
      close();
      debugDisableShadows = true;
      return;
    }

    // -- Home and chat --------------------------------------------------------
    for (final MapEntry(key: label, value: theme) in themes.entries) {
      final dark = theme.brightness == Brightness.dark;
      await container
          .read(themeSettingsProvider.notifier)
          .setMode(dark ? ThemePreference.dark : ThemePreference.light);
      await container
          .read(themeSettingsProvider.notifier)
          .setAmoled(label == 'amoled');
      await store.setMap(StoreKeys.assistant, const {});
      container.invalidate(assistantMemoryProvider);
      container.read(assistantGreetedProvider.notifier).state = false;
      await tester.pumpWidget(scope(const FocusForgeApp()));
      container.read(routerProvider).go('/dashboard');
      await frames(const Duration(milliseconds: 2600));
      await capture('home-$label');

      container.read(chatProvider.notifier).clear();
      container.read(routerProvider).push('/assistant');
      await frames(const Duration(seconds: 6));
      await capture('chat-intro-$label');
      for (final (name, action) in [
        ('report', const AssistantAction(Act.report)),
        ('plan', const AssistantAction(Act.plan)),
        ('today', const AssistantAction(Act.periodStats, arg: 'day')),
        ('month', const AssistantAction(Act.periodStats, arg: 'month')),
        ('lock', const AssistantAction(Act.distractions)),
        ('exam', const AssistantAction(Act.exam, arg: 'jee-main')),
        (
          'timetable',
          const AssistantAction(
            Act.timetable,
            said: 'physics 2 hours and biology 1 hour, 4 hours a day',
          ),
        ),
      ]) {
        container.read(chatProvider.notifier).clear();
        await frames(const Duration(milliseconds: 100));
        unawaited(container.read(chatProvider.notifier).run(action));
        if (name == 'report') {
          await frames(const Duration(milliseconds: 900));
          await capture('chat-thinking-$label');
          await frames(const Duration(milliseconds: 1250));
          await capture('chat-writein-$label');
          await frames(const Duration(milliseconds: 4850));
        } else {
          await frames(const Duration(seconds: 7));
        }
        await capture('chat-$name-$label');
      }
      for (final (name, question) in [
        ('lesson', 'explain derivatives'),
        ('quiz', 'quiz me on genetics advanced'),
        ('maths', 'solve x^2-5x+6=0'),
        ('budget', 'I have 1 hour 30 minutes for Physics'),
      ]) {
        container.read(chatProvider.notifier).clear();
        unawaited(container.read(chatProvider.notifier).send(question));
        await frames(const Duration(seconds: 7));
        await capture('chat-offline-$name-$label');
      }
      container.read(chatProvider.notifier).clear();
      container.read(routerProvider).go('/dashboard');
      await frames(const Duration(milliseconds: 600));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    close();
    await tester.pump();
    debugDisableShadows = true;
  });
}

/// Set CAPTURE_SCALE (for example 3) to render store-listing screenshots.
final double? _storeScale = double.tryParse(
  Platform.environment['CAPTURE_SCALE'] ?? '',
);
