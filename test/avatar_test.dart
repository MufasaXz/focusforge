// The avatar editor (lib/features/profile/widgets/avatar_sheet.dart).
//
// WHAT INVARIANT: choosing a mark or a colour writes the profile immediately,
// the preview shows the same disc the profile header will, and the initials
// are always one tap away — including after a mark has been chosen.
//
// WHY IT MATTERS: the avatar is the one piece of profile data with no text
// field behind it, so a wrong write is invisible in any diff and only shows up
// as an avatar that does not change. The clear path is the subtle one: "no
// glyph" means "use my initials", which `copyWith` cannot express with a null
// argument unless the caller says so explicitly.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/features/profile/widgets/avatar_sheet.dart';
import 'package:focusforge/core/services/profile_photo.dart';
import 'package:image/image.dart' as img;

import 'dart:typed_data';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStore store;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
  });

  setUp(() async {
    await store.clearAll();
  });

  ProviderContainer freshContainer() {
    final container = ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    return container;
  }

  Widget wrap(ProviderContainer container, Widget child) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: child),
        ),
      );

  /// Opens the sheet the way the profile does, over a plain page.
  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
  }

  Widget host(ProviderContainer container) => wrap(
    container,
    Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => showAvatarSheet(context),
        child: const Text('open'),
      ),
    ),
  );

  testWidgets('a mark is written as it is tapped, with no save step', (
    tester,
  ) async {
    final container = freshContainer();
    await container
        .read(userProvider.notifier)
        .save(const UserProfile(displayName: 'Sam Rivera'));

    await tester.pumpWidget(host(container));
    await openSheet(tester);
    expect(find.text('Your avatar'), findsOneWidget);

    // The initials tile comes first, then the glyphs in table order.
    final glyphs = find.byType(Icon);
    expect(glyphs, findsWidgets);
    await tester.tap(find.byIcon(Icons.star_rounded).first);
    await tester.pumpAndSettle();

    expect(
      container.read(userProvider).avatarIcon,
      'star',
      reason: 'the tap is the write',
    );
    expect(
      store.getMap(StoreKeys.user)?['avatarIcon'],
      'star',
      reason: 'and it is persisted, not just held in memory',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the initials can be taken back after a mark is chosen', (
    tester,
  ) async {
    final container = freshContainer();
    await container
        .read(userProvider.notifier)
        .save(const UserProfile(displayName: 'Sam Rivera', avatarIcon: 'star'));

    await tester.pumpWidget(host(container));
    await openSheet(tester);

    // The initials tile is the one that draws text rather than a glyph.
    await tester.tap(find.text('SR').first);
    await tester.pumpAndSettle();

    expect(
      container.read(userProvider).avatarIcon,
      isNull,
      reason: '"use my initials" has to be reachable, not just the default',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a colour is written without disturbing the mark', (
    tester,
  ) async {
    final container = freshContainer();
    await container
        .read(userProvider.notifier)
        .save(const UserProfile(displayName: 'Sam Rivera', avatarIcon: 'book'));

    await tester.pumpWidget(host(container));
    await openSheet(tester);

    final before = container.read(userProvider).avatarColor;
    // The colour row is the second Wrap; its dots are the only tappable
    // circles on it.
    final dots = find.byType(AnimatedContainer);
    expect(dots, findsWidgets);
    await tester.tap(dots.last);
    await tester.pumpAndSettle();

    final after = container.read(userProvider);
    expect(after.avatarColor, isNotNull);
    expect(after.avatarColor, isNot(before));
    expect(
      after.avatarIcon,
      'book',
      reason: 'picking a colour must not clear the mark',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'changing colour preserves a chosen photo until explicit removal',
    (tester) async {
      final container = freshContainer();
      final photo = ProfilePhoto.encode(
        Uint8List.fromList(img.encodePng(img.Image(width: 128, height: 128))),
      );
      await container
          .read(userProvider.notifier)
          .save(UserProfile(displayName: 'Sam Rivera', avatarPhoto: photo));
      await tester.pumpWidget(host(container));
      await openSheet(tester);
      final dot = find.byType(AnimatedContainer).last;
      await tester.ensureVisible(dot);
      await tester.tap(dot);
      await tester.pumpAndSettle();
      expect(container.read(userProvider).avatarColor, isNotNull);
      expect(container.read(userProvider).avatarPhoto, photo);
      expect(store.getMap(StoreKeys.user)?['avatarPhoto'], photo);
      final remove = find.text('Remove photo');
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(container.read(userProvider).avatarPhoto, isNull);
      expect(store.getMap(StoreKeys.user)?['avatarPhoto'], isNull);
    },
  );
}
