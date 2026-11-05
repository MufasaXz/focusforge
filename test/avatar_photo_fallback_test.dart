// What the avatar draws when its stored photo cannot be shown.
//
// WHAT INVARIANT: a photo that fails to decode falls back to the same mark as
// no photo: the initials, or a person when there is no name.
//
// WHY IT MATTERS: the fallback used to be bare, unstyled initials, which for a
// profile with no name is an empty disc with nothing on it at all.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:focusforge/app/theme/app_theme.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/features/profile/widgets/avatar_sheet.dart';

void main() {
  final photo = base64Encode(
    img.encodeJpg(img.Image(width: 64, height: 64), quality: 80),
  );

  /// Pumps the disc, then draws what its photo's error fallback would show.
  Future<void> pumpFallback(WidgetTester tester, UserProfile user) async {
    Widget app(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: Center(child: child)),
    );
    await tester.pumpWidget(app(AvatarDisc(user: user, size: 96)));
    final image = tester.widget<Image>(find.byType(Image));
    final fallback = image.errorBuilder!(
      tester.element(find.byType(Image)),
      Exception('undecodable'),
      null,
    );
    await tester.pumpWidget(app(fallback));
  }

  testWidgets('an unnamed profile shows a person, not an empty disc', (
    tester,
  ) async {
    await pumpFallback(
      tester,
      UserProfile(uid: 'u', displayName: '', avatarPhoto: photo),
    );
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
  });

  testWidgets('a named profile shows its initials', (tester) async {
    await pumpFallback(
      tester,
      UserProfile(uid: 'u', displayName: 'Sam Rivera', avatarPhoto: photo),
    );
    expect(find.text('SR'), findsOneWidget);
  });

  testWidgets('a chosen glyph is kept', (tester) async {
    await pumpFallback(
      tester,
      UserProfile(
        uid: 'u',
        displayName: 'Sam Rivera',
        avatarIcon: 'book',
        avatarPhoto: photo,
      ),
    );
    expect(find.text('SR'), findsNothing);
    expect(find.byType(Icon), findsOneWidget);
  });
}
