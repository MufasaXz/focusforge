import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';

import 'package:focusforge/core/providers/app_update_providers.dart';
import 'package:focusforge/core/services/app_update_service.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/shared/widgets/app_update_gate.dart';

Map<String, dynamic> release({String tag = '1.0.8', int build = 3004}) {
  final version = tag.replaceFirst(RegExp(r'^v'), '').split('+').first;
  final name = 'FocusForge-$version.apk';
  return {
    'tag_name': tag,
    'draft': false,
    'prerelease': false,
    'html_url': 'https://github.com/MufasaXz/focusforge/releases/tag/$tag',
    'body':
        '## Changes\n- Better focus.\n[Details](https://example.org)\n<!-- hidden -->\n<!-- focusforge-build: $build -->',
    'assets': [
      {
        'name': name,
        'size': 40000000,
        'state': 'uploaded',
        'browser_download_url':
            'https://github.com/MufasaXz/focusforge/releases/download/$tag/$name',
      },
    ],
  };
}

class _Browser extends UrlLauncherPlatform {
  @override
  LinkDelegate? get linkDelegate => null;
  String? opened;
  bool succeed = true;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened = url;
    return succeed;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
    await store.clearAll();
  });

  test(
    'compares numeric versions and Android build codes without downgrades',
    () {
      expect(AppRelease.compareVersions('1.0.10', '1.0.9'), greaterThan(0));
      expect(AppRelease.parse(release())?.id, '1.0.8+3004');
      expect(AppRelease.parse(release(tag: '1.0.7+3004'))?.id, '1.0.7+3004');
      expect(AppRelease.parse(release(tag: '1.0.7', build: 3003)), isNull);
      expect(AppRelease.parse(release(tag: '1.0.6', build: 4000)), isNull);
      expect(AppRelease.parse(release(tag: '1.0.8', build: 3001)), isNull);
      expect(AppRelease.parse(release(tag: '1.0.8-beta')), isNull);
      expect(AppRelease.parse(release(tag: '1.0.7+3005', build: 3004)), isNull);
      expect(AppRelease.parse(release(tag: 'v1.0.8'))?.version, '1.0.8');
    },
  );

  test(
    'only published releases with a real APK from our repository are eligible',
    () {
      for (final field in ['draft', 'prerelease']) {
        expect(AppRelease.parse(release()..[field] = true), isNull);
      }
      expect(
        AppRelease.parse(
          release()..['html_url'] = 'https://evil.example/download',
        ),
        isNull,
      );
      expect(AppRelease.parse(release()..['assets'] = []), isNull);
      final badAsset = release();
      (badAsset['assets'] as List).first['browser_download_url'] =
          'https://github.com/other/repo/app.apk';
      expect(AppRelease.parse(badAsset), isNull);
      final notes = AppRelease.parse(release())!.notes;
      expect(notes, contains('Details'));
      expect(notes, isNot(contains('https://example.org')));
      expect(notes, isNot(contains('hidden')));
      expect(notes, isNot(contains('focusforge-build')));
    },
  );

  test('clean APK names require one valid build marker; legacy names still work', () {
    expect(AppRelease.parse(release()..['body'] = 'No build metadata'), isNull);
    expect(
      AppRelease.parse(
        release()
          ..['body'] =
              '<!-- focusforge-build: 3004 --><!-- focusforge-build: 3005 -->',
      ),
      isNull,
    );
    expect(
      AppRelease.parse(
        release()..['body'] = '<!-- focusforge-build: 9999999999 -->',
      ),
      isNull,
    );
    final legacy = release()..['body'] = 'Old asset naming';
    final asset = (legacy['assets'] as List).single as Map;
    asset['name'] = 'focusforge-1.0.8-3004.apk';
    asset['browser_download_url'] = 'https://github.com/MufasaXz/focusforge/releases/download/1.0.8/focusforge-1.0.8-3004.apk';
    expect(AppRelease.parse(legacy)?.id, '1.0.8+3004');
  });

  test('checks at most daily, shares concurrent requests and remembers exact builds', () async {
    var now = DateTime.utc(2026, 11, 15);
    var calls = 0;
    final service = AppUpdateService(
      store,
      now: () => now,
      clientFactory: () => MockClient((request) async {
        calls++;
        expect(request.url.host, 'api.github.com');
        expect(request.headers.containsKey('authorization'), isFalse);
        expect(request.body, isEmpty);
        return http.Response(jsonEncode(release()), 200);
      }),
    );
    final results = await Future.wait([service.check(), service.check()]);
    expect(calls, 1);
    final newer = results.first!;
    await service.markShown(newer);
    expect(service.wasShown(newer), isTrue);
    expect(service.wasShown(AppRelease.parse(release(build: 3005))!), isFalse);
    expect(await service.check(), newer);
    expect(calls, 1);
    final restarted = AppUpdateService(
      store,
      now: () => now,
      clientFactory: () => throw StateError('must not connect'),
    );
    expect((await restarted.check())?.id, newer.id);
    expect(restarted.wasShown(newer), isTrue);
    now = now.add(const Duration(hours: 25));
    await service.check();
    expect(calls, 2);
    await service.check(force: true);
    expect(calls, 3);
  });

  test('an unseen release is restored within the daily cooldown', () async {
    var requests = 0;
    final now = DateTime.utc(2026, 11, 18);
    AppUpdateService launch() => AppUpdateService(
      store,
      now: () => now,
      clientFactory: () => MockClient((_) async {
        requests++;
        return http.Response(jsonEncode(release()), 200);
      }),
    );

    final first = await launch().check();
    expect(first?.id, '1.0.8+3004');
    final restarted = launch();
    final cached = await restarted.check();
    expect(cached?.id, first!.id);
    expect(cached?.page, first.page);
    expect(cached?.notes, first.notes);
    expect(restarted.wasShown(cached!), isFalse);
    expect(requests, 1);
  });

  testWidgets('deferred updates appear after leaving a settings route', (
    tester,
  ) async {
    var requests = 0;
    final response = Completer<http.Response>();
    final service = AppUpdateService(
      store,
      clientFactory: () => MockClient((_) {
        requests++;
        return response.future;
      }),
    );
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => AppUpdateGate(child: shell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/profile',
                  builder: (context, _) => Scaffold(
                    body: TextButton(
                      onPressed: () => context.push('/profile/permissions'),
                      child: const Text('Open permissions'),
                    ),
                  ),
                  routes: [
                    GoRoute(
                      path: 'permissions',
                      builder: (context, _) => Scaffold(
                        body: TextButton(
                          onPressed: () => context.pop(),
                          child: const Text('Return to profile'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appUpdateServiceProvider.overrideWithValue(service),
          appUpdatePromptAllowedProvider.overrideWithValue(true),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests, 1);
    await tester.tap(find.text('Open permissions'));
    await tester.pumpAndSettle();
    response.complete(http.Response(jsonEncode(release()), 200));
    await tester.pumpAndSettle();
    final prompt = find.text('A new FocusForge is ready');
    expect(prompt, findsNothing);
    expect(store.getString(AppUpdateService.shownReleaseKey), isNull);

    await tester.tap(find.text('Return to profile'));
    await tester.pumpAndSettle();
    expect(prompt, findsOneWidget);
    expect(requests, 1);
  });

  test('disabled checks make no network requests even when forced', () async {
    final service = AppUpdateService(
      store,
      enabled: false,
      clientFactory: () => throw StateError('must not connect'),
    );
    expect(await service.check(force: true), isNull);
    expect(store.getInt(AppUpdateService.lastCheckKey), isNull);
  });

  test(
    'offline, rate limits, malformed and oversized bodies fail quietly',
    () async {
      for (final response in [
        http.Response('limited', 403),
        http.Response('{', 200),
        http.Response('x' * (AppUpdateService.maxBytes + 1), 200),
      ]) {
        final service = AppUpdateService(
          store,
          clientFactory: () => MockClient((_) async => response),
        );
        expect(await service.check(force: true), isNull);
      }
      final service = AppUpdateService(
        store,
        clientFactory: () =>
            MockClient((_) async => throw http.ClientException('offline')),
      );
      expect(await service.check(force: true), isNull);
      final streamed = AppUpdateService(
        store,
        clientFactory: () => MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            Stream.value(List.filled(AppUpdateService.maxBytes + 1, 32)),
            200,
          ),
        ),
      );
      expect(await streamed.check(force: true), isNull);
    },
  );

  testWidgets(
    'automatic popup defers during focus and is dismissed once per build',
    (tester) async {
      var checks = 0;
      final allowed = StateProvider<bool>((ref) => false);
      final service = AppUpdateService(
        store,
        clientFactory: () => MockClient((_) async {
          checks++;
          return http.Response(jsonEncode(release()), 200);
        }),
      );
      final container = ProviderContainer(
        overrides: [
          appUpdateServiceProvider.overrideWithValue(service),
          appUpdatePromptAllowedProvider.overrideWith(
            (ref) => ref.watch(allowed),
          ),
        ],
      );
      addTearDown(container.dispose);
      final widget = UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: AppUpdateGate(child: Text('Study'))),
        ),
      );
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();
      expect(checks, 0);
      container.read(allowed.notifier).state = true;
      await tester.pumpAndSettle();
      expect(find.text('A new FocusForge is ready'), findsOneWidget);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('Study'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();
      expect(find.text('A new FocusForge is ready'), findsNothing);
      expect(checks, 1);
    },
  );

  testWidgets(
    'update link opens the trusted release page and errors stay dismissible',
    (tester) async {
      final oldBrowser = UrlLauncherPlatform.instance;
      final browser = _Browser()..succeed = false;
      UrlLauncherPlatform.instance = browser;
      addTearDown(() => UrlLauncherPlatform.instance = oldBrowser);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    showAppUpdateDialog(context, AppRelease.parse(release())!),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View update'));
      await tester.pumpAndSettle();
      expect(
        browser.opened,
        'https://github.com/MufasaXz/focusforge/releases/tag/1.0.8',
      );
      expect(
        find.text('Could not open GitHub. Try again later.'),
        findsOneWidget,
      );
      browser.succeed = true;
      await tester.tap(find.text('View update'));
      await tester.pumpAndSettle();
      expect(find.text('A new FocusForge is ready'), findsNothing);
    },
  );
}
