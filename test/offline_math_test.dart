import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:focusforge/features/assistant/brain/offline_math.dart';

void main() {
  group('arithmetic, precedence, domains and worked equations', () {
    const cases = {
      'calculate (12 + 8) / 5': '= 4.',
      '2 + 3 * 4': '= 14.',
      '-2^2': '= -4.',
      '(-2)^2': '= 4.',
      '2^3^2': '= 512.',
      '2^-3': '= 0.125.',
      'sqrt(81) + abs(-4)': '= 13.',
      '3(2 + 4)': '= 18.',
      'π * 2': '= 6.28318531.',
      '15% of 240': '= 36.',
      'what is 12.5% of 80?': '= 10.',
      'increase 200 by 15%': '= 230.',
      'decrease 200 by 15%': '= 170.',
      'percentage change from 80 to 100': '= 25%.',
      'mean 2, 4, 6': '= 4.',
      'median 1, 4, 2, 9': '= 3.',
      'mode 1, 1, 2, 2, 3': 'Modes: 1, 2',
      'mode 1, 2, 3': 'no mode',
      'range -3, 8, 2': '= 11.',
      'convert 2 km to m': '= 2000 m.',
      'convert 90 min to h': '= 1.5 h.',
      'convert 32 f to c': '= 0.',
      'convert 273.15 k to c': '= 0.',
      'simplify 18:24': '= 3:4.',
      'solve 2*x + 3 = 11': 'x = 4.',
      'solve x/2 + 3 = 7': 'x = 8.',
      'solve 4(2x-1)=3x+11': 'x = 3.',
      'solve x²-5x+6=0': 'x = 2 or x = 3.',
      'solve x²-6x+9=0': 'x = 3.',
      'solve x*x+1=0': 'no real roots',
      'solve 2x+1=2x+1': 'every real x',
      'solve 2x+1=2x+2': 'no solution',
    };
    for (final entry in cases.entries) {
      test(entry.key, () {
        expect(OfflineMath.recognizes(entry.key), isTrue);
        expect(OfflineMath.answer(entry.key), contains(entry.value));
      });
    }
  });

  group('reject malformed, unsupported and abusive expressions safely', () {
    const cases = {
      '1/0': 'Division by zero',
      'sqrt(-4)': 'not real',
      '0^0': 'undefined',
      '2^99': 'exponent',
      'solve x^3=8': 'degree two',
      'solve 1/x=2': 'containing x',
      'solve x=x=3': 'one equals',
      'calculate (2+3': 'bracket',
      'calculate 2 3': 'operators',
      'calculate sin(2)': 'unsupported',
      'calculate import(secret)': 'unsupported',
      'convert 2 kg to km': 'Different physical quantities',
      'convert -1 k to c': 'absolute zero',
      'simplify 0:0': 'cannot be simplified',
      'percentage change from 0 to 5': 'no defined percentage',
    };
    for (final entry in cases.entries) {
      test(
        entry.key,
        () => expect(OfflineMath.answer(entry.key), contains(entry.value)),
      );
    }
    test('deep nesting and long text are bounded', () {
      expect(
        OfflineMath.answer('${'(' * 20}2${')' * 20}'),
        contains('fewer nested'),
      );
      expect(OfflineMath.answer('2+' * 200), contains('at most 240'));
    });
  });

  test(
    '200 independently constructed linear equations recover their roots',
    () {
      final random = math.Random(729);
      for (var i = 0; i < 200; i++) {
        final coefficient = random.nextInt(39) + 1;
        final root = random.nextInt(101) - 50;
        final offset = random.nextInt(31) - 15;
        final right = coefficient * root + offset;
        final answer = OfflineMath.answer(
          'solve $coefficient*x+($offset)=$right',
        );
        expect(answer, contains('x = $root.'), reason: answer);
      }
    },
  );

  test('100 factored quadratics retain both roots, including zero', () {
    for (var i = -5; i < 5; i++) {
      for (var j = 1; j <= 10; j++) {
        final answer = OfflineMath.answer('solve (x-($i))*(x-($j))=0');
        expect(answer, contains('x = $i'), reason: answer);
        expect(answer, contains('x = $j'), reason: answer);
      }
    }
  });
}
