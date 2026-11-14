import 'dart:math' as math;

import 'offline_knowledge.dart';
import 'offline_math.dart';

/// Parameterised practice has computed answer keys. The seed is an ephemeral
/// question number, never a user identifier. Non-numeric topics stop at the
/// end of their authored bank rather than fabricating further questions.
abstract final class OfflinePractice {
  static OfflineQuestion? question(
    OfflineLesson lesson,
    int sequence,
    int difficulty,
  ) {
    final suitable = lesson.questions
        .where((q) => q.difficulty >= difficulty)
        .toList();
    final bank = suitable.isEmpty
        ? lesson.questions.reversed.toList()
        : suitable;
    if (sequence < bank.length) return bank[sequence];
    final seed = lesson.id.codeUnits.fold(0, (a, b) => a * 31 + b) & 0x7fffffff;
    final random = math.Random(seed + sequence * 7919);
    final a = 2 + random.nextInt(difficulty >= 3 ? 15 : 6);
    final b = 2 + random.nextInt(6);
    final c = 1 + random.nextInt(5);
    final n = 2 + random.nextInt(3);
    if (difficulty >= 3) {
      final challenge = _challenge(lesson.id, a, b, c, n, random);
      if (challenge != null) return challenge;
    }
    switch (lesson.id) {
      case 'fractions':
        final denominator = b * (b + 1);
        final numerator = a * (b + 1) + c * b;
        final gcd = numerator.gcd(denominator);
        final answer = '${numerator ~/ gcd}/${denominator ~/ gcd}';
        return _choices(
          'Add $a/$b + $c/${b + 1}, giving a simplified fraction.',
          answer,
          [
            answer,
            '${numerator + 1}/$denominator',
            '${a + c}/${2 * b + 1}',
            '${numerator + denominator}/$denominator',
          ],
          'Use denominator $denominator, then simplify.',
          'The numerator is $a×${b + 1} + $c×$b = $numerator. '
              'Divide numerator and denominator by $gcd to get $answer.',
          random,
          difficulty,
        );
      case 'percentages':
        final percent = 5 * b;
        final base = a * 20;
        return _numeric(
          'What is $percent% of $base?',
          base * percent / 100,
          'Convert percent to a fraction of 100.',
          '$base × $percent ÷ 100 = ${base * percent / 100}.',
          random,
          difficulty,
        );
      case 'ratios':
        final total = (a + b) * c;
        return _numeric(
          'Share $total in the ratio $a:$b. What is the first share?',
          (a * c).toDouble(),
          'Divide by the sum of the ratio terms first.',
          'Each part is $total ÷ ${a + b} = $c, so the first share is ${a * c}.',
          random,
          difficulty,
        );
      case 'linear-equations':
        final right = a * b + c;
        return _numeric(
          'Solve $a*x + $c = $right.',
          b.toDouble(),
          'Subtract $c, then divide by $a.',
          '$a*x = ${a * b}; x = $b.',
          random,
          difficulty,
        );
      case 'quadratics':
        final small = c;
        final big = c + b;
        return _numeric(
          'What is the smaller real root of x² − ${small + big}x + ${small * big} = 0?',
          small.toDouble(),
          'Find two numbers with sum ${small + big} and product ${small * big}.',
          'Factor as (x − $small)(x − $big). Roots are $small and $big; the smaller is $small.',
          random,
          3,
        );
      case 'exponents':
        return _numeric(
          'Simplify $b^$n × $b^${n - 1}.',
          math.pow(b, 2 * n - 1).toDouble(),
          'The bases match, so add the exponents.',
          '$b^($n + ${n - 1}) = $b^${2 * n - 1} = ${math.pow(b, 2 * n - 1).toInt()}.',
          random,
          difficulty,
        );
      case 'derivatives':
        final slope = a * n * math.pow(c, n - 1).toDouble();
        return _numeric(
          'For f(x) = $a*x^$n, what is f′($c)?',
          slope,
          'Use the power rule, then substitute x = $c.',
          'f′(x) = ${a * n}*x^${n - 1}; f′($c) = ${OfflineMath.format(slope)}.',
          random,
          3,
        );
      case 'integrals':
        final value = math.pow(b, n).toDouble();
        return _numeric(
          'Evaluate the definite integral from 0 to $b of $n*x^${n - 1} dx.',
          value,
          'An antiderivative is x^$n.',
          '[x^$n] from 0 to $b is $b^$n = ${OfflineMath.format(value)}.',
          random,
          3,
        );
      case 'vectors':
        return _numeric(
          'Find the dot product of ($a, $b) and ($c, ${b + 1}).',
          (a * c + b * (b + 1)).toDouble(),
          'Multiply matching components, then add.',
          '$a×$c + $b×${b + 1} = ${a * c + b * (b + 1)}.',
          random,
          difficulty,
        );
      case 'matrices':
        return _numeric(
          'Find det([[$a,$b],[$c,${b + 1}]]).',
          (a * (b + 1) - b * c).toDouble(),
          'For a 2×2 matrix, use ad − bc.',
          '$a×${b + 1} − $b×$c = ${a * (b + 1) - b * c}.',
          random,
          3,
        );
      case 'newton':
        return _numeric(
          'A $b kg object has net force ${a * b} N. What is its acceleration in m/s²?',
          a.toDouble(),
          'Rearrange F = ma.',
          'a = F/m = ${a * b}/$b = $a m/s².',
          random,
          difficulty,
        );
      case 'kinematics':
        final distance = 0.5 * a * b * b;
        return _numeric(
          'Starting from rest, an object accelerates uniformly at $a m/s² for $b s. Displacement in metres?',
          distance,
          'Use s = ut + ½at², with u = 0.',
          's = ½ × $a × $b² = ${OfflineMath.format(distance)} m.',
          random,
          3,
        );
      case 'energy':
        return _numeric(
          'A $a kg object moves at $b m/s. What is its kinetic energy in joules?',
          0.5 * a * b * b,
          'Use KE = ½mv².',
          '½ × $a × $b² = ${OfflineMath.format(0.5 * a * b * b)} J.',
          random,
          difficulty,
        );
      case 'ohm':
        return _numeric(
          'A $b Ω ohmic resistor carries $a A. Its power in watts is:',
          (a * a * b).toDouble(),
          'Use P = I²R.',
          '$a² × $b = ${a * a * b} W.',
          random,
          3,
        );
      case 'waves':
        return _numeric(
          'A wave has speed ${a * b} m/s and frequency $a Hz. Wavelength in metres?',
          b.toDouble(),
          'Use λ = v/f.',
          '${a * b}/$a = $b m.',
          random,
          difficulty,
        );
      case 'moles':
        return _numeric(
          'For 2H₂ + O₂ → 2H₂O, how many moles of H₂O can form from ${2 * a} mol H₂ with excess O₂?',
          (2 * a).toDouble(),
          'Read the H₂:H₂O coefficient ratio.',
          'The ratio is 2:2, so ${2 * a} mol H₂ forms ${2 * a} mol H₂O.',
          random,
          difficulty,
        );
      default:
        return null;
    }
  }

  static OfflineQuestion? _challenge(
    String id,
    int a,
    int b,
    int c,
    int n,
    math.Random random,
  ) {
    switch (id) {
      case 'percentages':
        final p = b * 5;
        final q = c * 5;
        final change = ((1 + p / 100) * (1 - q / 100) - 1) * 100;
        return _numeric(
          'A price increases by $p% and then decreases by $q%. '
              'What is the signed overall percentage change (negative means a decrease)?',
          change,
          'Multiply the two change factors, then compare with 1.',
          'The factor is (1 + $p/100)(1 − $q/100). Subtract 1 and multiply by 100: '
              '${OfflineMath.format(change)}%.',
          random,
          3,
        );
      case 'linear-equations':
        if (a == c) return null;
        final right = a * (b - c) - c * b;
        return _numeric(
          'Solve $a*(x-$c)=$c*x+($right).',
          b.toDouble(),
          'Expand the bracket, move x terms to one side, and constants to the other.',
          '${a - c}*x = ${right + a * c}, so x = $b.',
          random,
          3,
        );
      case 'derivatives':
        final inner = a * c * c + b;
        final slope = 6.0 * a * c * inner * inner;
        return _numeric(
          'For f(x) = ($a*x² + $b)³, what is f′($c)?',
          slope,
          'Use the chain rule: differentiate the outer cube and then its inner expression.',
          'f′(x) = 3($a*x² + $b)² × ${2 * a}x. At x = $c: '
              '${OfflineMath.format(slope)}.',
          random,
          3,
        );
      case 'integrals':
        final upper = b * b + c;
        final result =
            math.pow(upper, n).toDouble() - math.pow(c, n).toDouble();
        return _numeric(
          'Evaluate ∫ from 0 to $b of ${2 * n}*x*(x²+$c)^${n - 1} dx.',
          result,
          'Set u = x² + $c, so du = 2x dx. Transform both bounds.',
          'The integral becomes ∫ from $c to $upper of $n*u^${n - 1} du. '
              '[u^$n] gives $upper^$n − $c^$n = ${OfflineMath.format(result)}.',
          random,
          3,
        );
      case 'vectors':
        final answer = -a * b - c * (b + 1);
        return _numeric(
          'For which k are ($a, k, $c) and ($b, 1, ${b + 1}) perpendicular?',
          answer.toDouble(),
          'Set the dot product equal to zero.',
          '$a×$b + k + $c×${b + 1} = 0, giving k = $answer.',
          random,
          3,
        );
      case 'kinematics':
        final speed = a * b;
        final result = 0.5 * speed * (b + c);
        return _numeric(
          'A vehicle starts from rest, accelerates uniformly at $a m/s² '
              'for $b s, then slows uniformly to rest in $c s. Total distance in metres?',
          result,
          'Find the peak speed, then add the two triangular areas on the velocity–time graph.',
          'Peak speed = $a×$b = $speed m/s. Distance = ½×$speed×($b+$c) '
              '= ${OfflineMath.format(result)} m.',
          random,
          3,
        );
      case 'ohm':
        final resistance = a + b / 2;
        final current = c * 2;
        final voltage = resistance * current;
        final power = current * current * resistance;
        return _numeric(
          'Two $b Ω resistors in parallel are in series with $a Ω. '
              'An ideal ${OfflineMath.format(voltage)} V supply powers the network. Total power in watts?',
          power,
          'Simplify the parallel pair, add the series resistance, then use P = V²/R.',
          'Equivalent resistance = $b/2 + $a = ${OfflineMath.format(resistance)} Ω. '
              'I = V/R = $current A, so P = VI = ${OfflineMath.format(power)} W.',
          random,
          3,
        );
      case 'moles':
        final nitrogen = a;
        final hydrogen = b * 3;
        final ammonia = 2 * math.min(nitrogen, b);
        return _numeric(
          'For N₂ + 3H₂ → 2NH₃, start with $nitrogen mol N₂ and '
              '$hydrogen mol H₂. Maximum moles of NH₃?',
          ammonia.toDouble(),
          'Divide each starting amount by its reaction coefficient to find the limiting extent.',
          'The extent is min($nitrogen, $hydrogen/3) = ${math.min(nitrogen, b)} mol. '
              'Multiply by 2 to get $ammonia mol NH₃.',
          random,
          3,
        );
      default:
        return null;
    }
  }

  static OfflineQuestion _numeric(
    String prompt,
    double result,
    String hint,
    String explanation,
    math.Random random,
    int difficulty,
  ) {
    final answer = OfflineMath.format(result);
    return _choices(
      prompt,
      answer,
      [
        answer,
        OfflineMath.format(result + 1),
        OfflineMath.format(result - 1),
        OfflineMath.format(result + 2),
      ],
      hint,
      explanation,
      random,
      difficulty,
    );
  }

  static OfflineQuestion _choices(
    String prompt,
    String answer,
    List<String> candidates,
    String hint,
    String explanation,
    math.Random random,
    int difficulty,
  ) {
    final values = candidates.toSet().toList();
    // All generators provide four distinct choices; retaining this check makes
    // content mistakes fail during testing rather than silently misgrade.
    if (values.length != 4) {
      throw StateError('Practice choices must be distinct');
    }
    values.shuffle(random);
    return OfflineQuestion(
      prompt,
      List.unmodifiable(values),
      values.indexOf(answer),
      hint,
      explanation,
      difficulty: difficulty,
    );
  }
}
