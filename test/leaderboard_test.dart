import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/social.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/social_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/services/leaderboard_service.dart';
import 'package:focusforge/features/settings/leaderboard_screen.dart';

class _Board implements LeaderboardService {
  @override
  bool get available => true;
  @override
  String? get uid => 'me';
  @override
  Stream<List<BoardRow>> watch(String week, {int limit = 100}) =>
      Stream.value(const []);
  @override
  Future<void> publish({
    required String week,
    required String uid,
    required String name,
    required int minutes,
  }) async {}
  @override
  Future<void> withdraw(String week, String uid) async {}
  @override
  void dispose() {}
}

void main() {
  for (final dark in [false, true]) {
    testWidgets('weekly glass summary fits 320dp at 2x, dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      final container = ProviderContainer(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          leaderboardServiceProvider.overrideWithValue(_Board()),
          leaderboardWeekHoursProvider.overrideWithValue(2),
          previousWeekHoursProvider.overrideWithValue(4),
          weekSessionCountProvider.overrideWithValue(3),
          leaderboardProvider.overrideWithValue(const [
            LeaderboardEntry(name: 'Alexandria Morgan Rivera', hours: 6),
            LeaderboardEntry(name: 'Alex', hours: 2, isMe: true),
          ]),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(userProvider.notifier)
          .hydrate(
            const UserProfile(
              uid: 'me',
              displayName: 'Alex',
              isAnonymous: false,
            ),
          );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: dark ? AppTheme.dark(amoled: true) : AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: const LeaderboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('leaderboard-week')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('leaderboard-week')),
          matching: find.text('2h'),
        ),
        findsOneWidget,
      );
      expect(find.text('−2h'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.label == 'This week against last week' &&
              w.properties.value == '50 percent',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Alex (you)'), 160);
      expect(find.text('Alex (you)'), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(
              find.ancestor(
                of: find.text('Alex (you)'),
                matching: find.byType(ListTile),
              ),
            )
            .tileColor,
        (dark ? AppTheme.dark(amoled: true) : AppTheme.light())
            .colorScheme
            .primaryContainer,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
