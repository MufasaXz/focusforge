// The display name an account gets from its email when it has no other.
//
// WHAT INVARIANT: the name is readable words from the address's local part,
// and it fits the 60-character limit the board and group rules enforce.
//
// WHY IT MATTERS: this name is published to the weekly board and to study
// groups. One the rules refuse fails every publish and every join.

import 'package:flutter_test/flutter_test.dart';

import 'package:focusforge/core/services/firebase_auth_service.dart';

void main() {
  test('turns the local part into words', () {
    expect(
      FirebaseAuthService.nameFromEmail('sam.rivera@example.com'),
      'Sam Rivera',
    );
    expect(
      FirebaseAuthService.nameFromEmail('jo_ann-lee@example.com'),
      'Jo Ann Lee',
    );
  });

  test('fits the 60 characters the board and groups accept', () {
    // A local part may be 64 characters long.
    final name = FirebaseAuthService.nameFromEmail('${'a' * 64}@example.com');
    expect(name.length, 60);
    expect(name, 'A${'a' * 59}');
  });
}
