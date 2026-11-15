import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/models/study_avatar.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/leaderboard_service.dart';
import 'package:focusforge/features/profile/widgets/avatar_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalStore store;
  late ProviderContainer container;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
    await store.clearAll();
    container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
  });
  tearDown(() => container.dispose());
  Future<void> mount(WidgetTester tester, {double scale = 1}) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: AvatarSheet()),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('a starter and every five-level milestone have distinct stable IDs', () {
    expect(StudyAvatar.values.map((a) => a.unlockLevel), [
      1,
      5,
      10,
      15,
      20,
      25,
      30,
      35,
      40,
      45,
      50,
    ]);
    expect(StudyAvatar.values.map((a) => a.id).toSet().length, 11);
    for (final avatar in StudyAvatar.values) {
      expect(avatar.unlockedAt(avatar.unlockLevel), isTrue);
      expect(avatar.unlockedAt(avatar.unlockLevel - 1), isFalse);
      expect(BoardRow.validIcon(avatar.id), avatar.id);
    }
    expect(StudyAvatar.forProfile(StudyAvatar.zenith.id, 1), StudyAvatar.scout);
    expect(StudyAvatar.fromId('arbitrary'), isNull);
  });
  test(
    'locked selection is rejected by the notifier and unlocked choice persists',
    () async {
      await expectLater(
        container.read(userProvider.notifier).setStudyAvatar(StudyAvatar.ember),
        throwsStateError,
      );
      expect(store.getMap(StoreKeys.user), isNull);
      container
          .read(statsProvider.notifier)
          .hydrate(const GamificationStats(level: 5));
      await container
          .read(userProvider.notifier)
          .save(const UserProfile(avatarColor: 0xFF008800));
      await container
          .read(userProvider.notifier)
          .setStudyAvatar(StudyAvatar.ember);
      final saved = UserProfile.fromJson(store.getMap(StoreKeys.user)!);
      expect(saved.avatarIcon, StudyAvatar.ember.id);
      expect(saved.avatarColor, isNull);
    },
  );
  testWidgets('picker shows level locks and no old icon or colour controls', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('Your avatar'), findsOneWidget);
    expect(find.text('Level 5'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey(StudyAvatar.ember.id)));
    await tester.pumpAndSettle();
    expect(container.read(userProvider).avatarIcon, isNull);
    await tester.tap(find.byKey(ValueKey(StudyAvatar.scout.id)));
    await tester.pumpAndSettle();
    expect(container.read(userProvider).avatarIcon, StudyAvatar.scout.id);
    expect(find.text('Colour'), findsNothing);
    expect(find.text('Icon'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'reaching level five enables the fox without reopening the picker',
    (tester) async {
      await mount(tester);
      container
          .read(statsProvider.notifier)
          .hydrate(const GamificationStats(level: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(StudyAvatar.ember.id)));
      await tester.pumpAndSettle();
      expect(store.getMap(StoreKeys.user)?['avatarIcon'], StudyAvatar.ember.id);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'large-text picker scrolls to the final reward without overflow',
    (tester) async {
      await mount(tester, scale: 2);
      await tester.scrollUntilVisible(
        find.byKey(ValueKey(StudyAvatar.zenith.id)),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Level 50'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
