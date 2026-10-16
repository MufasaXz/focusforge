import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/services/profile_photo.dart';
import 'package:focusforge/core/services/leaderboard_service.dart';

void main() {
  test(
    'photo thumbnail is bounded and survives profile and board serialization',
    () {
      final source = img.Image(width: 600, height: 400);
      final photo = ProfilePhoto.encode(
        Uint8List.fromList(img.encodePng(source)),
      );
      expect(photo.length, lessThanOrEqualTo(ProfilePhoto.maxLength));
      final decoded = img.decodeImage(ProfilePhoto.bytes(photo)!);
      expect(decoded!.width, 128);
      expect(decoded.height, 128);
      final profile = UserProfile(displayName: 'New name', avatarPhoto: photo);
      expect(UserProfile.fromJson(profile.toJson()).avatarPhoto, photo);
      final board = BoardRow.fromJson('account', {
        'name': 'New name',
        'minutes': 60,
        'avatarPhoto': photo,
      });
      expect(board?.avatarPhoto, photo);
      expect(profile.copyWith(clearPhoto: true).avatarPhoto, isNull);
    },
  );

  test('invalid and oversized photos use initials without throwing', () {
    expect(ProfilePhoto.bytes('invalid'), isNull);
    expect(ProfilePhoto.bytes('A' * (ProfilePhoto.maxLength + 1)), isNull);
    expect(ProfilePhoto.bytes('aGVsbG8='), isNull);
    expect(
      () => ProfilePhoto.encode(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });
}
