import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/social.dart';
import 'package:focusforge/core/models/study.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/social_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/study_group_service.dart';
import 'package:focusforge/features/settings/study_groups_screen.dart';

class FakeGroups implements StudyGroupService {
  final group = StudyGroup(
    id: 'circle',
    name: 'Sunday study circle',
    icon: Icons.groups,
    targetHours: 10,
    createdAt: DateTime(2026),
    inviteCode: 'ABCD234567',
    ownerUid: 'me',
    memberIds: const ['me', 'friend'],
  );
  final calls = <String>[];
  Completer<void>? pending;
  bool fail = false;
  @override
  bool get available => true;
  @override
  Stream<List<StudyGroup>> watchGroups(String uid) => Stream.value([group]);
  @override
  Stream<List<GroupMember>> watchMembers(String groupId) => Stream.value([
    GroupMember(uid: 'me', name: 'Alex', week: '2026-10-05', minutes: 30),
    GroupMember(
      uid: 'friend',
      name: 'A friend with a long display name',
      week: '2026-10-05',
      minutes: 90,
      focusUntil: DateTime.utc(2026, 10, 8, 13),
    ),
  ]);
  @override
  Future<void> create(String name, int targetHours, String displayName) async {
    calls.add('create:$name@$targetHours');
  }

  @override
  Future<void> join(String code, String displayName) async {
    calls.add('join:$code');
  }

  @override
  Future<void> leave(StudyGroup group) async {
    calls.add('leave');
  }

  @override
  Future<void> publish(
    String groupId,
    String week,
    int minutes,
    String displayName,
    DateTime? focusUntil,
  ) async {
    calls.add('publish:$minutes');
    if (pending != null) await pending!.future;
    if (fail) throw const GroupException('offline');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore store;
  final time = DateTime.utc(2026, 10, 8, 12);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
  });
  ProviderContainer container(FakeGroups service) {
    final c = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        studyGroupServiceProvider.overrideWithValue(service),
        groupClockProvider.overrideWith((ref) => Stream.value(time)),
      ],
    );
    c
        .read(userProvider.notifier)
        .hydrate(
          const UserProfile(
            uid: 'me',
            displayName: 'Alex',
            isAnonymous: false,
            onboardingComplete: true,
          ),
        );
    addTearDown(c.dispose);
    return c;
  }

  test('weekly shared totals use UTC Monday and exclude future or unfinished sessions', () async {
    final c = container(FakeGroups());
    await c.read(groupClockProvider.future);
    c
        .read(sessionsProvider.notifier)
        .hydrate(
          [
            FocusSession(
              id: 'before',
              subjectId: 'math',
              startedAt: DateTime.utc(2026, 10, 4, 23, 59),
              minutes: 25,
            ),
            FocusSession(
              id: 'monday',
              subjectId: 'math',
              startedAt: DateTime.utc(2026, 10, 5),
              minutes: 50,
            ),
            FocusSession(
              id: 'future',
              subjectId: 'math',
              startedAt: time.add(const Duration(hours: 1)),
              minutes: 25,
            ),
            FocusSession(
              id: 'unfinished',
              subjectId: 'math',
              startedAt: time,
              minutes: 25,
              completed: false,
            ),
          ].map((s) => s.toJson()).toList(),
        );
    expect(c.read(groupWeekProvider), '2026-10-05');
    expect(c.read(groupWeekMinutesProvider), 50);
  });
  test('publishing queues a newer total behind an in-flight write and avoids duplicate writes', () async {
    final service = FakeGroups()..pending = Completer<void>();
    final c = container(service);
    await c.read(cloudGroupsProvider.future);
    await c.read(groupClockProvider.future);
    c.read(groupPublisherProvider);
    await Future<void>.delayed(Duration.zero);
    c.read(sessionsProvider.notifier).hydrate([
      FocusSession(
        id: 'done',
        subjectId: 'math',
        startedAt: time,
        minutes: 25,
      ).toJson(),
    ]);
    service.pending!.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(service.calls, ['publish:0', 'publish:25']);
    c
        .read(userProvider.notifier)
        .hydrate(
          const UserProfile(
            uid: 'me',
            displayName: 'Alex',
            isAnonymous: false,
            onboardingComplete: true,
          ),
        );
    await Future<void>.delayed(Duration.zero);
    expect(service.calls, hasLength(2));
  });
  testWidgets('group progress and detail fit 320dp with 2x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = container(FakeGroups());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const StudyGroupsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Sunday study circle'), 200);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sunday study circle'));
    await tester.pumpAndSettle();
    expect(find.text('Sunday study circle').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Sunday study circle'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('A friend with a long display name'),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Focusing now'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Create group'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
