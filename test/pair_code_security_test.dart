import 'package:flutter_test/flutter_test.dart';
import 'package:focusforge/core/models/parent.dart';

void main() {
  test('pairing accepts human-spaced strong tokens and rejects old guessable codes', () {
    expect(PairCode.looksValid('ABCD2345EFGH6789'), isTrue);
    expect(PairCode.looksValid('abcd 2345 efgh 6789'), isTrue);
    expect(PairCode.looksValid('ABCD-2345-EFGH-6789'), isTrue);
    expect(PairCode.looksValid('123456'), isFalse);
    expect(PairCode.looksValid('ABCD2345EFGH678'), isFalse);
    expect(PairCode.looksValid('ABCD2345EFGH67890'), isFalse);
    expect(PairCode.looksValid('ABCD2345EFGH678I'), isFalse);
    expect(PairCode.normalize('abcd 2345-efgh 6789'), 'ABCD2345EFGH6789');
    expect(
      PairCode(code: 'ABCD2345EFGH6789', expiresAt: DateTime(2026)).displayCode,
      'ABCD 2345 EFGH 6789',
    );
  });
}
