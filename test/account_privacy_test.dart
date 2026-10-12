import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/social_providers.dart';
import 'package:focusforge/core/services/local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('changing identity requires fresh leaderboard consent while retaining device history', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await store.clearAll();
    final container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    await container
        .read(userProvider.notifier)
        .save(const UserProfile(uid: 'first', onboardingComplete: true));
    await store.setList(StoreKeys.sessions, [
      {'id': 'local-history'},
    ]);
    await container.read(boardOptInProvider.notifier).set(true);
    await container
        .read(userProvider.notifier)
        .save(const UserProfile(uid: 'second', onboardingComplete: true));
    expect(container.read(boardOptInProvider), isFalse);
    expect(store.getBool(StoreKeys.boardOptIn), isFalse);
    expect(store.getList(StoreKeys.sessions), [
      {'id': 'local-history'},
    ]);
  });

  test(
    'returning to the same identity preserves existing board consent',
    () async {
      final store = await LocalStore.open();
      await store.clearAll();
      final container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      await container
          .read(userProvider.notifier)
          .save(const UserProfile(uid: 'first'));
      await container.read(boardOptInProvider.notifier).set(true);
      await container
          .read(userProvider.notifier)
          .save(const UserProfile(uid: 'first', displayName: 'Sam'));
      expect(container.read(boardOptInProvider), isTrue);
    },
  );
}
