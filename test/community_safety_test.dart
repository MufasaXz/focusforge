import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/community_providers.dart';
import 'package:focusforge/shared/widgets/community_safety.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('blocking content is private to the active account and persists across restart', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await store.clearAll();
    final c = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    addTearDown(c.dispose);
    c.read(userProvider.notifier).hydrate(const UserProfile(uid: 'alex'));
    await c.read(blockedCommunityUsersProvider.notifier).block('reported-user');
    c.invalidate(blockedCommunityUsersProvider);
    expect(c.read(blockedCommunityUsersProvider), contains('reported-user'));
    c.read(userProvider.notifier).hydrate(const UserProfile(uid: 'sam'));
    expect(c.read(blockedCommunityUsersProvider), isEmpty);
  });
  testWidgets('community terms require explicit acceptance before sharing', (
    tester,
  ) async {
    bool? accepted;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              accepted = await confirmCommunityTerms(context);
            },
            child: const Text('Join'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    expect(find.textContaining('harassment'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(accepted, false);
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept and continue'));
    await tester.pumpAndSettle();
    expect(accepted, true);
  });
}
