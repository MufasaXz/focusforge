import 'offline_lessons_school.dart';
import 'offline_text.dart';

/// Authored study notes, not generated facts. Questions have explicit answer
/// keys; the tutor never pretends to grade arbitrary essays or proofs.
class OfflineQuestion {
  const OfflineQuestion(
    this.prompt,
    this.options,
    this.correct,
    this.hint,
    this.explanation, {
    this.difficulty = 1,
  });
  final String prompt;
  final List<String> options;
  final int correct;
  final String hint;
  final String explanation;
  final int difficulty;
}

class OfflineLesson {
  const OfflineLesson(
    this.id,
    this.title,
    this.aliases,
    this.summary,
    this.example,
    this.pitfall,
    this.questions,
  );
  final String id;
  final String title;
  final List<String> aliases;
  final String summary;
  final String example;
  final String pitfall;
  final List<OfflineQuestion> questions;
}

abstract final class OfflineKnowledge {
  static OfflineLesson? byId(String? id) {
    for (final lesson in lessons) {
      if (lesson.id == id) return lesson;
    }
    return null;
  }

  /// Every word that appears in some alias. A correctly spelled topic word is
  /// never treated as a typo of a different one: "revolution" is one edit
  /// from "evolution", but it names the French Revolution, not Darwin.
  static final Set<String> _known = {
    for (final lesson in lessons)
      for (final alias in lesson.aliases)
        ...OfflineText.normalize(alias).split(' '),
  };

  /// Require a whole alias, or a single edit in a sufficiently long alias.
  /// Long phrases outrank their components (conditional probability before
  /// probability, for example). No nearest-answer fallback on unrelated text.
  static List<OfflineLesson> find(String input) {
    final text = OfflineText.normalize(input);
    if (text.length > OfflineText.maxInputLength) return const [];
    final words = text.split(' ').where((w) => w.length <= 40).toSet();
    final matches = <(OfflineLesson, int)>[];
    for (final lesson in lessons) {
      var best = 0;
      for (final raw in lesson.aliases) {
        final alias = OfflineText.normalize(raw);
        final score = OfflineText.has(text, alias)
            ? 100 + alias.length
            : !alias.contains(' ') &&
                  alias.length >= 7 &&
                  words.any(
                    (w) => !_known.contains(w) && OfflineText.close(w, alias),
                  )
            ? 60
            : 0;
        if (score > best) best = score;
      }
      if (best > 0) matches.add((lesson, best));
    }
    matches.sort((a, b) {
      final score = b.$2.compareTo(a.$2);
      return score == 0 ? a.$1.id.compareTo(b.$1.id) : score;
    });
    // A more specific alias subsumes its generic component.
    if (matches.isNotEmpty && matches.first.$2 >= 100) {
      final first = matches.first.$1;
      matches.removeWhere(
        (m) =>
            m.$1 != first &&
            first.aliases.any(
              (a) =>
                  OfflineText.has(text, a) &&
                  m.$1.aliases.any(
                    (b) =>
                        a != b && OfflineText.has(OfflineText.normalize(a), b),
                  ),
            ),
      );
    }
    return [for (final match in matches) match.$1];
  }

  static const lessons = <OfflineLesson>[..._core, ...schoolLessons];

  static const _core = <OfflineLesson>[
    OfflineLesson(
      'fractions',
      'Fractions',
      ['fraction', 'fractions', 'भिन्न'],
      'A fraction names equal parts of a whole. Add or subtract using a common denominator; multiply numerators and denominators; divide by multiplying by the reciprocal.',
      '1/2 + 1/3 = 3/6 + 2/6 = 5/6. For (2/3) ÷ (4/5), use (2/3) × (5/4) = 5/6.',
      'Do not add denominators: 1/2 + 1/3 is not 2/5. A denominator cannot be zero.',
      [
        OfflineQuestion(
          'What is 3/4 − 1/6?',
          ['2/2', '7/12', '2/12', '5/6'],
          1,
          'Use twelfths as the common denominator.',
          '9/12 − 2/12 = 7/12.',
        ),
        OfflineQuestion(
          'What is (2/3 + 1/6) ÷ (5/4)?',
          ['2/3', '25/24', '1/2', '3/2'],
          0,
          'Add first, then multiply by 4/5.',
          '(5/6) × (4/5) = 2/3.',
          difficulty: 3,
        ),
      ],
    ),
    OfflineLesson(
      'percentages',
      'Percentages',
      ['percentage', 'percentages', 'प्रतिशत'],
      'Percent means per hundred. Find p% of n using p ÷ 100 × n. A percentage change is (new − old) ÷ old × 100 when the old value is positive.',
      '15% of 240 = 0.15 × 240 = 36. A rise from 80 to 100 is 20/80 × 100 = 25%.',
      'Successive percentage changes multiply; a 20% increase followed by a 20% decrease does not return to the starting value.',
      [
        OfflineQuestion(
          'A value rises 20%, then falls 20%. The overall change is:',
          ['No change', '4% decrease', '4% increase', '40% decrease'],
          1,
          'Start with 100, multiply by 1.2 and then 0.8.',
          '100 → 120 → 96, a 4% decrease.',
          difficulty: 3,
        ),
      ],
    ),
    OfflineLesson(
      'ratios',
      'Ratios and proportions',
      ['ratio', 'ratios', 'proportion', 'अनुपात'],
      'A ratio compares quantities in the same units. Divide all terms by a common factor to simplify. In a direct proportion, multiplying one quantity by a factor multiplies the other by that factor.',
      '18:24 simplifies to 3:4. Sharing 70 in the ratio 2:5 gives 7 parts, so each part is 10; the shares are 20 and 50.',
      'Convert units first. In inverse proportion the product stays constant, not the quotient.',
      [
        OfflineQuestion(
          'Six equally fast workers take 10 days. How long do 15 workers take for the same work?',
          ['25 days', '9 days', '4 days', '6 days'],
          2,
          'The work needs 6 × 10 worker-days.',
          '60 worker-days ÷ 15 workers = 4 days, assuming equal rates.',
          difficulty: 2,
        ),
      ],
    ),
    OfflineLesson(
      'linear-equations',
      'Linear equations',
      ['linear equation', 'linear equations', 'algebra equation'],
      'Solve a linear equation by doing the same operation to both sides until the variable is alone. Expand brackets and collect like terms first.',
      '3(x − 2) = 12 → 3x − 6 = 12 → 3x = 18 → x = 6. Check: 3(6 − 2) = 12.',
      'Moving a term is shorthand for adding or subtracting on both sides. Keep negative signs attached to their terms.',
      [
        OfflineQuestion(
          'Solve 4(2x − 1) = 3x + 11.',
          ['x = 1', 'x = 2', 'x = 3', 'x = 5'],
          2,
          'Expand: 8x − 4 = 3x + 11.',
          'Subtract 3x and add 4: 5x = 15, so x = 3.',
          difficulty: 2,
        ),
      ],
    ),
    OfflineLesson(
      'quadratics',
      'Quadratic equations',
      ['quadratic', 'quadratics', 'quadratic equation', 'quadratic equations'],
      'Write a quadratic as ax² + bx + c = 0, with a ≠ 0. Factor when possible, or use x = (−b ± √(b² − 4ac)) / (2a). The discriminant tells you about the real roots.',
      'x² − 5x + 6 = (x − 2)(x − 3), so x = 2 or 3. A negative discriminant means no real roots; zero means one repeated root.',
      'Both roots matter. Dividing by x can discard x = 0 when it is a valid root.',
      [
        OfflineQuestion(
          'For what k does x² − 6x + k = 0 have a repeated real root?',
          ['6', '9', '12', '36'],
          1,
          'Set the discriminant to zero.',
          '36 − 4k = 0 gives k = 9, and the repeated root is 3.',
          difficulty: 3,
        ),
      ],
    ),
    OfflineLesson(
      'exponents',
      'Powers and exponents',
      ['exponent', 'exponents', 'indices', 'laws of powers'],
      'For the same base, multiply powers by adding exponents and divide by subtracting them. (a^m)^n = a^(mn). For nonzero a, a^0 = 1 and a^(−n) = 1/a^n.',
      '2³ × 2⁴ = 2⁷ = 128. 3^(−2) = 1/9. Brackets matter: (−2)² = 4, but −2² = −4.',
      'The rule a^m × a^n = a^(m+n) does not apply to addition. State domain restrictions for fractional powers.',
      [
        OfflineQuestion(
          'Simplify (2³ × 2⁻¹)².',
          ['8', '16', '32', '64'],
          1,
          'Add the inside exponents, then multiply by the outside exponent.',
          '(2²)² = 2⁴ = 16.',
          difficulty: 2,
        ),
      ],
    ),
    OfflineLesson(
      'logarithms',
      'Logarithms',
      ['logarithm', 'logarithms', 'log rules'],
      'A logarithm answers an exponent question: log_b(a) = c means b^c = a. For real logarithms, a > 0, b > 0, and b ≠ 1.',
      'log₂(8) = 3. Products become sums: log_b(uv) = log_b(u) + log_b(v). Change base using log_b(a) = ln(a)/ln(b).',
      'log(u + v) is not log(u) + log(v). Check the original domain after solving.',
      [
        OfflineQuestion(
          'Solve log₂(x − 1) + log₂(x + 1) = 3 over the reals.',
          ['−3 only', '3 only', '±3', '4 only'],
          1,
          'Combine logs, then check x − 1 > 0 and x + 1 > 0.',
          'x² − 1 = 8 gives x = ±3, but the domain x > 1 leaves x = 3.',
          difficulty: 3,
        ),
      ],
    ),
    OfflineLesson(
      'functions',
      'Functions and composition',
      ['function', 'functions', 'function composition'],
      'A function assigns exactly one output to each input in its domain. Composition f(g(x)) means apply g first, then f. An inverse reverses a one-to-one function on its chosen domain.',
      'If f(x) = 2x + 1 and g(x) = x², then f(g(3)) = 19, while g(f(3)) = 49.',
      'f(g(x)) and g(f(x)) are usually different. Restrict the domain before inverting a function such as x².',
      [
        OfflineQuestion(
          'If f(x) = 3x − 2, what is f⁻¹(7)?',
          ['1', '3', '5', '19'],
          1,
          'Solve 3x − 2 = 7.',
          '3x = 9, so x = 3.',
          difficulty: 2,
        ),
      ],
    ),
    OfflineLesson(
      'limits',
      'Limits and continuity',
      ['limit', 'limits', 'continuity'],
      'A limit describes what a function approaches as the input approaches a value. Continuity at a point requires the limit to exist and equal the function’s value there.',
      'As x → 2, (x² − 4)/(x − 2) = x + 2 for x ≠ 2, so its limit is 4 even though the original expression is undefined at 2.',
      'An undefined value at one point does not automatically mean the limit is absent. Compare left and right limits.',
      [
        OfflineQuestion(
          'What is lim as x → 0 of sin(x)/x, with x in radians?',
          ['0', '1', '∞', 'Does not exist'],
          1,
          'This is the standard small-angle limit in radians.',
          'sin(x) behaves like x near zero, so the ratio approaches 1.',
          difficulty: 2,
        ),
      ],
    ),
    OfflineLesson(
      'derivatives',
      'Derivatives',
      [
        'derivative',
        'derivatives',
        'differentiation',
        'calculus',
        'chain rule',
      ],
      'A derivative is an instantaneous rate of change or tangent slope. The power rule is d(x^n)/dx = n*x^(n−1). Use product, quotient, and chain rules for combined functions.',
      'For y = (3x + 1)², the chain rule gives dy/dx = 2(3x + 1) × 3 = 6(3x + 1). At x = 1 the slope is 24.',
      'For a composite function, include the inner derivative. A stationary point is not automatically a maximum or minimum.',
      [
        OfflineQuestion(
          'Differentiate x² sin(x).',
          ['2x cos(x)', '2x sin(x) + x² cos(x)', 'x² cos(x)', '2x sin(x)'],
          1,
          'Use the product rule: u′v + uv′.',
          'd(x²)/dx = 2x and d(sin x)/dx = cos x, giving 2x sin(x) + x² cos(x).',
          difficulty: 3,
        ),
        OfflineQuestion(
          'For f(x) = x³ − 3x, which x is a local maximum?',
          ['−1', '0', '1', '3'],
          0,
          'Find f′ = 0, then inspect f″.',
          'f′ = 3x² − 3 gives ±1. f″ = 6x is negative at −1, so that point is a local maximum.',
          difficulty: 3,
        ),
      ],
    ),
    OfflineLesson(
      'integrals',
      'Integrals',
      ['integral', 'integrals', 'integration', 'antiderivative'],
      'An indefinite integral is a family of antiderivatives and includes a constant C. A definite integral gives signed accumulation over an interval. For n ≠ −1, ∫x^n dx = x^(n+1)/(n+1) + C.',
      '∫₀² 3x² dx = [x³]₀² = 8. For substitution in ∫2x cos(x²) dx, set u = x²; the answer is sin(x²) + C.',
      'Signed area can cancel. Geometric area may require splitting where the function changes sign. ∫1/x dx uses ln|x| + C.',
      [
        OfflineQuestion(
          'Evaluate ∫₀¹ 6x(1 + x²)² dx.',
          ['1', '3', '7', '8'],
          2,
          'Use u = 1 + x², so 6x dx = 3 du.',
          'Bounds become 1 and 2. ∫₁² 3u² du = [u³]₁² = 7.',
          difficulty: 3,
        ),
      ],
    ),
    OfflineLesson(
      'trigonometry',
      'Trigonometry',
      [
        'trigonometry',
        'trig',
        'sine cosine',
        'trigonometric ratios',
        'त्रिकोणमिति',
      ],
      'In a right triangle, sin θ = opposite/hypotenuse, cos θ = adjacent/hypotenuse, and tan θ = opposite/adjacent. On the unit circle, coordinates are (cos θ, sin θ).',
      'For a 3–4–5 triangle with opposite side 3, sin θ = 3/5. The identity sin²θ + cos²θ = 1 holds for every real angle.',
      'Check whether angles are in degrees or radians. sin(a + b) is not sin a + sin b.',
      [
        OfflineQuestion(
          'If sin θ = 3/5 and θ is in quadrant II, what is cos θ?',
          ['4/5', '−4/5', '3/5', '−3/5'],
          1,
          'Use sin²θ + cos²θ = 1 and the quadrant’s sign.',
          '|cos θ| = 4/5, and cosine is negative in quadrant II.',
          difficulty: 3,
        ),
      ],
    ),
    OfflineLesson(
      'pythagoras',
      'Pythagoras’ theorem',
      ['pythagoras', 'pythagorean', 'right triangle'],
      'In a right triangle, a² + b² = c², where c is the hypotenuse opposite the right angle.',
      'With perpendicular sides 5 and 12, c = √(25 + 144) = 13.',
      'Use this theorem only for right triangles. The hypotenuse is the longest side, not whichever side is labelled c.',
      [
        OfflineQuestion(
          'A right triangle has hypotenuse 17 and one leg 8. What is the other leg?',
          ['9', '15', '19', '25'],
          1,
          'Subtract squared lengths before taking the square root.',
          '√(17² − 8²) = √225 = 15.',
        ),
      ],
    ),
    OfflineLesson(
      'vectors',
      'Vectors and dot products',
      ['vector', 'vectors', 'dot product'],
      'A vector has magnitude and direction. Add component by component. The dot product a·b = Σaᵢbᵢ = |a||b| cos θ measures alignment.',
      '(1, 2)·(3, 4) = 11. The magnitude of (3, 4) is 5. Nonzero perpendicular vectors have dot product zero.',
      'A dot product is a scalar. A zero dot product only implies a right angle when both vectors are nonzero.',
      [
        OfflineQuestion(
          'For which k are (2, k, 1) and (1, −1, 3) perpendicular?',
          ['−5', '−1', '1', '5'],
          3,
          'Set their dot product equal to zero.',
          '2 − k + 3 = 0 gives k = 5.',
          difficulty: 2,
        ),
      ],
    ),
    OfflineLesson(
      'matrices',
      'Matrices and determinants',
      ['matrix', 'matrices', 'determinant', 'linear algebra'],
      'Matrices represent linear transformations or systems of equations. Matrix multiplication uses row-by-column dot products. A 2×2 matrix [[a,b],[c,d]] has determinant ad − bc.',
      'For [[2,1],[1,3]], det = 6 − 1 = 5, so it is invertible. Its inverse is (1/5)[[3,−1],[−1,2]].',
      'Matrix multiplication is generally not commutative. A square matrix with determinant zero has no inverse.',
      [
        OfflineQuestion(
          'For what k is [[k,2],[3,6]] singular?',
          ['0', '1', '2', '3'],
          1,
          'A singular matrix has determinant zero.',
          '6k − 6 = 0 gives k = 1.',
          difficulty: 2,
        ),
      ],
    ),
    OfflineLesson(
      'probability',
      'Probability',
      ['probability', 'random events'],
      'Probability lies between 0 and 1. For equally likely outcomes, P(A) = favourable/total. P(not A) = 1 − P(A). For independent events, multiply their probabilities.',
      'Two fair coin tosses have four equally likely outcomes. Exactly one head occurs in HT and TH, so its probability is 2/4 = 1/2.',
      'Mutually exclusive and independent mean different things. Do not assume draws without replacement are independent.',
      [
        OfflineQuestion(
          'Two fair dice are rolled. What is the probability their sum is 9?',
          ['1/6', '1/9', '1/12', '1/18'],
          1,
          'Count ordered pairs among 36 equally likely outcomes.',
          '(3,6), (4,5), (5,4), (6,3): 4/36 = 1/9.',
          difficulty: 2,
        ),
      ],
    ),
    OfflineLesson(
      'conditional-probability',
      'Conditional probability and Bayes’ rule',
      ['conditional probability', 'bayes', 'bayes theorem'],
      'Conditional probability updates the sample space: P(A|B) = P(A∩B)/P(B), with P(B) > 0. Bayes’ rule reverses conditioning using P(A|B) = P(B|A)P(A)/P(B).',
      'A bag has 3 red and 2 blue counters. After drawing a red counter without replacement, the chance the next is red is 2/4 = 1/2.',
      'P(A|B) and P(B|A) are generally different. Include base rates when combining evidence.',
      [
        OfflineQuestion(
          'Box A is chosen with probability 1/2 and has 2 red, 1 blue counters. Box B has 1 red, 2 blue. Given a red draw, P(A|red) is:',
          ['1/3', '1/2', '2/3', '3/4'],
          2,
          'Compute each box’s contribution to a red draw.',
          '(1/2 × 2/3) / (1/2 × 2/3 + 1/2 × 1/3) = 2/3.',
          difficulty: 3,
        ),
      ],
    ),
    OfflineLesson(
      'statistics',
      'Descriptive statistics',
      ['statistics', 'mean median mode', 'standard deviation', 'variance'],
      'The mean is sum/count, the median is the middle after sorting, and the mode is the most frequent value. Variance measures squared spread around the mean; standard deviation is its square root.',
      'For 2, 4, 6, the mean and median are 4. Population variance is (4 + 0 + 4)/3 = 8/3. Sample variance divides by n − 1 instead.',
      'Outliers can move the mean strongly. State whether data are a population or sample, and remember correlation does not establish causation.',
      [
        OfflineQuestion(
          'For 1, 2, 2, 3, 12, which statement is correct?',
          [
            'Mean = median',
            'Mean = 4, median = 2',
            'Mean = 2, median = 4',
            'No mode',
          ],
          1,
          'Sort, find the middle, then divide the sum by five.',
          'The sum is 20, so mean = 4; the middle value and mode are both 2.',
          difficulty: 2,
        ),
      ],
    ),
    OfflineLesson(
      'newton',
      'Newton’s laws',
      [
        'newton',
        'newtons',
        'newtons laws',
        'newtons first law',
        'newton first law',
        'newtons 1st law',
        'force and acceleration',
      ],
      'An object maintains constant velocity unless a net external force acts. For constant mass, net force F = ma. Interaction forces come in equal and opposite pairs acting on different objects.',
      'A 3 kg trolley with net force 12 N accelerates at 12/3 = 4 m/s².',
      'Equal and opposite interaction forces do not cancel on one object because they act on different objects. Use net force, not just one force.',
      [
        OfflineQuestion(
          'A 4 kg object has 20 N right and 8 N left forces. Its acceleration is:',
          ['3 m/s² right', '5 m/s² right', '7 m/s² right', '3 m/s² left'],
          0,
          'Find the net force first.',
          '(20 − 8)/4 = 3 m/s² to the right.',
          difficulty: 2,
        ),
      ],
    ),
    OfflineLesson(
      'kinematics',
      'Constant-acceleration motion',
      ['kinematics', 'equations of motion', 'suvat'],
      'With constant acceleration, v = u + at, s = ut + ½at², and v² = u² + 2as. Choose a positive direction and keep the signs consistent.',
      'From rest at 2 m/s² for 5 s: v = 10 m/s and displacement s = 25 m.',
      'These formulas assume constant acceleration. Distance and displacement differ when direction changes.',
      [
        OfflineQuestion(
          'A car slows uniformly from 20 m/s to rest in 5 s. How far does it travel?',
          ['25 m', '50 m', '75 m', '100 m'],
          1,
          'Average velocity is (u + v)/2 for constant acceleration.',
          'Average velocity = 10 m/s; displacement = 10 × 5 = 50 m.',
          difficulty: 2,
        ),
      ],
    ),
    OfflineLesson(
      'energy',
      'Work, energy, and power',
      ['kinetic energy', 'potential energy', 'work energy', 'power formula'],
      'Work transfers energy: W = Fd cos θ for a constant force. Kinetic energy is ½mv²; near Earth, gravitational potential change is mgΔh. Power is energy transferred per unit time.',
      'A 2 kg object at 3 m/s has kinetic energy ½ × 2 × 9 = 9 J. Doubling its speed makes kinetic energy four times as large.',
      'Energy is conserved overall, but mechanical energy can transfer to thermal energy through friction.',
      [
        OfflineQuestion(
          'If speed triples while mass stays fixed, kinetic energy becomes:',
          ['3 times', '6 times', '9 times', '27 times'],
          2,
          'Kinetic energy depends on speed squared.',
          '(3v)²/v² = 9.',
          difficulty: 2,
        ),
      ],
    ),
    OfflineLesson(
      'momentum',
      'Momentum and impulse',
      ['momentum', 'impulse', 'collision'],
      'Momentum p = mv is a vector. Impulse equals change in momentum. Total momentum is conserved for a system with negligible net external impulse.',
      'A 2 kg cart moving at 3 m/s sticks to a stationary 1 kg cart. Their common speed is (2×3)/(2+1) = 2 m/s.',
      'Momentum conservation does not imply kinetic-energy conservation. In a sticking collision, some kinetic energy changes form.',
      [
        OfflineQuestion(
          'A ball of mass 0.5 kg changes velocity from +4 to −2 m/s. Its impulse is:',
          ['+1 N·s', '−1 N·s', '+3 N·s', '−3 N·s'],
          3,
          'Use m(v − u), preserving direction.',
          '0.5 × (−2 − 4) = −3 N·s.',
          difficulty: 3,
        ),
      ],
    ),
    OfflineLesson(
      'ohm',
      'Ohm’s law',
      ['ohms law', 'ohm', 'voltage current resistance'],
      'For an ohmic component under fixed physical conditions, voltage V = IR. Electrical power P = VI; substituting Ohm’s law gives I²R or V²/R.',
      'A 6 Ω resistor across 12 V carries 2 A and dissipates 24 W.',
      'Not every component is ohmic. Keep units consistent: volts, amperes, and ohms. Study circuit theory without experimenting on mains electricity.',
      [
        OfflineQuestion(
          'The voltage across a fixed resistor doubles. Its power becomes:',
          ['Half', 'Twice', 'Four times', 'Unchanged'],
          2,
          'Use P = V²/R.',
          'With fixed R, doubling V multiplies power by four.',
          difficulty: 2,
        ),
      ],
    ),
    OfflineLesson(
      'circuits',
      'Series and parallel resistors',
      [
        'series parallel',
        'parallel resistors',
        'series resistors',
        'resistor circuits',
      ],
      'Series resistors carry the same current and their resistances add. Parallel branches share the same voltage; add reciprocals of resistance to find the equivalent.',
      '6 Ω and 3 Ω in parallel give 1/R = 1/6 + 1/3 = 1/2, so R = 2 Ω.',
      'Equivalent parallel resistance is smaller than the smallest branch resistance for positive resistances. This is classroom theory, not mains wiring advice.',
      [
        OfflineQuestion(
          'A 4 Ω resistor is in series with two 6 Ω resistors in parallel. Total resistance is:',
          ['3 Ω', '7 Ω', '10 Ω', '16 Ω'],
          1,
          'Simplify the parallel pair first.',
          '6 Ω || 6 Ω = 3 Ω, then add 4 Ω to get 7 Ω.',
          difficulty: 3,
        ),
      ],
    ),
    OfflineLesson(
      'waves',
      'Waves',
      ['wave', 'waves', 'frequency wavelength'],
      'Waves transfer energy without overall transport of the medium. Wave speed v = fλ, with frequency f and wavelength λ. Frequency is fixed by the source across a stationary boundary.',
      'At 340 m/s and 170 Hz, wavelength = 340/170 = 2 m. When speed changes in a new medium, wavelength changes too.',
      'Amplitude and frequency are different. A larger amplitude does not by itself imply a higher frequency.',
      [
        OfflineQuestion(
          'A wave enters a medium where its speed halves. Its source frequency is unchanged. Its wavelength:',
          ['Doubles', 'Halves', 'Stays the same', 'Becomes zero'],
          1,
          'Rearrange v = fλ.',
          'With f fixed, λ is proportional to v, so it halves.',
          difficulty: 2,
        ),
      ],
    ),
    OfflineLesson(
      'optics',
      'Reflection and refraction',
      ['optics', 'refraction', 'snells law', 'reflection'],
      'Reflection has equal incidence and reflection angles, measured from the normal. Refraction follows n₁ sin θ₁ = n₂ sin θ₂. A larger refractive index means a lower light speed in the material.',
      'Light going from air into glass at an oblique angle bends toward the normal because the glass has a larger refractive index.',
      'Measure angles from the normal, not the surface. At normal incidence the ray does not change direction.',
      [
        OfflineQuestion(
          'Total internal reflection can occur when light travels:',
          [
            'From lower to higher index at any angle',
            'From higher to lower index above the critical angle',
            'Only in air',
            'At normal incidence',
          ],
          1,
          'Think about the direction of refraction and a 90° refracted ray.',
          'It requires travel from a higher-index medium to a lower-index medium with incidence above the critical angle.',
          difficulty: 3,
        ),
      ],
    ),
    OfflineLesson(
      'thermodynamics',
      'Thermodynamics',
      ['thermodynamics', 'first law', 'ideal gas'],
      'Using work W done by the system as positive, the first law is ΔU = Q − W. For a fixed amount of ideal gas, PV = nRT; use absolute temperature in kelvin.',
      'A gas absorbs 100 J of heat and does 40 J of work, so its internal energy rises by 60 J.',
      'State the work sign convention. Temperature and heat are different; heat is energy transferred because of a temperature difference.',
      [
        OfflineQuestion(
          'An ideal gas expands isothermally. Its internal energy depends only on temperature. What is true?',
          ['ΔU > 0', 'Q = 0', 'Q = W', 'W = 0'],
          2,
          'An isothermal process keeps temperature constant.',
          'ΔU = 0, so Q − W = 0 and Q = W in this sign convention.',
          difficulty: 3,
        ),
      ],
    ),
    OfflineLesson(
      'atomic-structure',
      'Atomic structure',
      ['atomic structure', 'proton neutron electron', 'atomic number'],
      'The nucleus contains protons and neutrons; electrons occupy quantum states around it. Atomic number counts protons. Mass number counts protons plus neutrons. Isotopes share proton count but differ in neutron count.',
      'Carbon-14 has 6 protons and 8 neutrons. A neutral carbon atom has 6 electrons.',
      'Ions change electron count, not atomic number. Electron shells are not literal miniature planetary orbits.',
      [
        OfflineQuestion(
          'An ion has atomic number 12, mass number 24, and charge +2. It has:',
          [
            '12 protons, 12 neutrons, 10 electrons',
            '10 protons, 12 neutrons, 12 electrons',
            '12 protons, 14 neutrons, 10 electrons',
            '12 protons, 12 neutrons, 14 electrons',
          ],
          0,
          'Positive charge means electrons were removed.',
          'Protons = 12, neutrons = 24 − 12 = 12, electrons = 12 − 2 = 10.',
          difficulty: 2,
        ),
      ],
    ),
    OfflineLesson(
      'periodic-table',
      'Periodic trends',
      ['periodic table', 'periodic trends', 'electronegativity'],
      'Across a typical main-group period, atomic radius generally decreases and ionisation energy generally increases. Down a group, extra shells usually increase radius. Electronegativity describes attraction for shared electrons.',
      'Sodium is generally larger than chlorine in the same period because increasing effective nuclear charge draws electrons inward.',
      'Trends have exceptions because of electron configurations. Do not treat a general trend as a substitute for all measured data.',
      [
        OfflineQuestion(
          'Which generally has the largest atomic radius?',
          ['Li', 'Na', 'K', 'F'],
          2,
          'Move down the alkali-metal group.',
          'Potassium has more occupied electron shells than sodium or lithium and is larger than fluorine.',
        ),
      ],
    ),
    OfflineLesson(
      'bonding',
      'Chemical bonding',
      ['chemical bonding', 'ionic bond', 'covalent bond', 'hydrogen bond'],
      'Ionic bonding is electrostatic attraction between oppositely charged ions. Covalent bonding involves shared electron density. Metallic bonding involves positive metal centres and delocalised electrons.',
      'In a simple water molecule, O–H bonds are polar covalent. Hydrogen bonding between water molecules is different from those internal covalent bonds.',
      'Do not confuse an intermolecular attraction with an intramolecular bond. Real bonds can have mixed ionic and covalent character.',
      [
        OfflineQuestion(
          'Which best explains why water has a relatively high boiling point for its size?',
          [
            'Ionic O–H bonds',
            'Hydrogen bonding between molecules',
            'Metallic bonding',
            'No attraction between molecules',
          ],
          1,
          'Focus on attractions between water molecules.',
          'Hydrogen bonding increases the energy needed to separate water molecules.',
          difficulty: 2,
        ),
      ],
    ),
    OfflineLesson(
      'moles',
      'Moles and stoichiometry',
      ['mole', 'moles', 'stoichiometry', 'molar mass'],
      'A mole contains exactly 6.02214076×10²³ specified entities. Convert mass to amount with n = m/M. Balanced-equation coefficients give mole ratios between substances.',
      'For 2H₂ + O₂ → 2H₂O, 4 mol H₂ needs 2 mol O₂ and can form 4 mol H₂O if oxygen is sufficient.',
      'Mass ratios are not usually coefficient ratios. Identify the limiting reactant before computing product amount.',
      [
        OfflineQuestion(
          'For N₂ + 3H₂ → 2NH₃, start with 2 mol N₂ and 3 mol H₂. Maximum NH₃ is:',
          ['1 mol', '2 mol', '3 mol', '4 mol'],
          1,
          'Which reactant runs out first?',
          'H₂ is limiting: 3 mol H₂ reacts with 1 mol N₂ to form 2 mol NH₃.',
          difficulty: 3,
        ),
      ],
    ),
    OfflineLesson(
      'balancing',
      'Balancing chemical equations',
      [
        'balance equation',
        'balance equations',
        'balancing equations',
        'balancing chemical',
      ],
      'A balanced equation conserves every element’s atom count, and charge when relevant. Adjust whole-number coefficients, keeping chemical formulas unchanged.',
      'Fe + O₂ → Fe₂O₃ balances as 4Fe + 3O₂ → 2Fe₂O₃: both sides have 4 iron and 6 oxygen atoms.',
      'Changing a subscript changes the substance. Coefficients, not formula subscripts, are your balancing tools.',
      [
        OfflineQuestion(
          'The smallest whole-number coefficients for Al + O₂ → Al₂O₃ are:',
          ['2, 3, 2', '4, 3, 2', '2, 1, 1', '1, 3, 2'],
          1,
          'Make the oxygen count a multiple of both 2 and 3.',
          '4Al + 3O₂ → 2Al₂O₃ conserves 4 Al atoms and 6 O atoms.',
          difficulty: 2,
        ),
      ],
    ),
    OfflineLesson(
      'acids-bases',
      'Acids, bases, and pH',
      ['acid base', 'acids and bases', 'ph', 'acidic basic'],
      'In the Brønsted–Lowry model, acids donate protons and bases accept them. pH = −log₁₀(aH⁺); in dilute classroom calculations, hydrogen-ion concentration approximates activity.',
      'If [H⁺] = 10⁻³ mol/L in an ideal dilute solution, pH ≈ 3. A one-unit pH change corresponds to a tenfold activity change.',
      'Strong means extensive ionisation, not high concentration. Neutral pH is 7 at about 25°C; it changes with temperature. Do not mix household chemicals.',
      [
        OfflineQuestion(
          'In dilute solutions, pH 3 has approximately how much greater [H⁺] than pH 5?',
          ['2 times', '10 times', '100 times', '1000 times'],
          2,
          'Each pH step is a factor of ten.',
          '10⁻³ / 10⁻⁵ = 100.',
          difficulty: 2,
        ),
      ],
    ),
    OfflineLesson(
      'equilibrium',
      'Chemical equilibrium',
      ['chemical equilibrium', 'le chatelier', 'equilibrium constant'],
      'At dynamic equilibrium in a closed system, forward and reverse reaction rates are equal. Concentrations remain constant but need not be equal. A disturbance can change the equilibrium composition.',
      'For an exothermic forward reaction, increasing temperature tends to favour the reverse direction. A catalyst speeds both directions and does not change the equilibrium constant at fixed temperature.',
      'Equilibrium is not a stopped reaction. Pure solids and liquids are omitted from usual equilibrium-constant expressions.',
      [
        OfflineQuestion(
          'At fixed temperature, adding a catalyst to an equilibrium mixture:',
          [
            'Increases K',
            'Decreases K',
            'Changes neither K nor equilibrium composition',
            'Stops the reverse reaction',
          ],
          2,
          'A catalyst changes the route, not the thermodynamic balance.',
          'Both directions speed up; the equilibrium constant and final composition remain unchanged.',
          difficulty: 3,
        ),
      ],
    ),
    OfflineLesson(
      'redox',
      'Oxidation and reduction',
      ['redox', 'oxidation', 'reduction', 'oxidation number'],
      'Oxidation is electron loss or an increase in oxidation number. Reduction is electron gain or a decrease. The oxidising agent is itself reduced; the reducing agent is oxidised.',
      'Zn + Cu²⁺ → Zn²⁺ + Cu: zinc loses two electrons and copper ions gain them.',
      'Oxidation numbers are bookkeeping tools, not always actual ionic charges. Balance both atoms and charge in half-equations.',
      [
        OfflineQuestion(
          'In Zn + Cu²⁺ → Zn²⁺ + Cu, the oxidising agent is:',
          ['Zn', 'Cu²⁺', 'Zn²⁺', 'Cu'],
          1,
          'The oxidising agent accepts electrons.',
          'Cu²⁺ gains electrons and is reduced, so it oxidises zinc.',
          difficulty: 2,
        ),
      ],
    ),
    OfflineLesson(
      'organic',
      'Organic functional groups',
      [
        'organic chemistry',
        'functional group',
        'functional groups',
        'isomerism',
      ],
      'Functional groups are characteristic atom arrangements that help predict properties and reactions. Examples include alcohol –OH, carboxylic acid –COOH, aldehyde –CHO, and ketone >C=O.',
      'Ethanol contains an alcohol group. Ethanoic acid contains a carboxyl group. Structural isomers have the same molecular formula but different connectivity.',
      'A hydroxyl group attached directly to an aromatic ring is classified as a phenol, not an ordinary alcohol. Study reactions on paper rather than attempting unsupervised experiments.',
      [
        OfflineQuestion(
          'Which pair are structural isomers?',
          [
            'Ethanol and dimethyl ether',
            'Methane and ethane',
            'Water and hydrogen peroxide',
            'Oxygen and ozone',
          ],
          0,
          'Look for equal molecular formulas but different connectivity.',
          'Both ethanol and dimethyl ether have formula C₂H₆O, with different atom connections.',
          difficulty: 3,
        ),
      ],
    ),
    OfflineLesson(
      'cells',
      'Cells and organelles',
      [
        'cell',
        'cells',
        'cell biology',
        'cell organelles',
        'organelles',
        'cell structure',
        'structure of cell',
        'plant cell',
        'animal cell',
        'कोशिका',
      ],
      'Cells are the basic units of life. The cell membrane regulates exchange. In eukaryotes, the nucleus contains most DNA, ribosomes make proteins, and mitochondria support aerobic respiration.',
      'A typical plant cell also has a cellulose cell wall and a large central vacuole; photosynthetic cells contain chloroplasts.',
      'Not every cell has a nucleus or chloroplasts. Bacteria lack a membrane-bound nucleus but do have DNA and ribosomes.',
      [
        OfflineQuestion(
          'Which structure occurs in both typical bacterial and animal cells?',
          [
            'Chloroplast',
            'Membrane-bound nucleus',
            'Ribosome',
            'Cellulose cell wall',
          ],
          2,
          'Both kinds of cells need to make proteins.',
          'Ribosomes make proteins and occur in both prokaryotic and eukaryotic cells.',
        ),
      ],
    ),
    OfflineLesson(
      'photosynthesis',
      'Photosynthesis',
      ['photosynthesis', 'प्रकाश संश्लेषण'],
      'Photosynthesis converts light energy into chemical energy. In plants, light-dependent reactions in thylakoid membranes make ATP and NADPH and release oxygen from water. The Calvin cycle in the stroma fixes carbon dioxide.',
      'A simplified net equation is 6CO₂ + 6H₂O + light → C₆H₁₂O₆ + 6O₂. Light, carbon dioxide, and temperature can each limit the rate.',
      'The oxygen released comes from water. Plants also respire, during both day and night.',
      [
        OfflineQuestion(
          'The oxygen released during plant photosynthesis comes directly from:',
          ['Carbon dioxide', 'Water', 'Glucose', 'Chlorophyll'],
          1,
          'Think about what is split in the light-dependent reactions.',
          'Water is split; its electrons and protons support the light reactions and oxygen is released.',
          difficulty: 2,
        ),
      ],
    ),
    OfflineLesson(
      'respiration',
      'Cellular respiration',
      ['cellular respiration', 'aerobic respiration', 'glycolysis'],
      'Cellular respiration transfers energy from fuel into usable forms such as ATP. Glycolysis occurs in the cytosol. In eukaryotic aerobic respiration, later stages involve mitochondria; oxygen is the final electron acceptor.',
      'Glycolysis splits one glucose into two pyruvate molecules, with a net gain of 2 ATP and 2 NADH before later stages.',
      'Respiration is not the same as breathing. Exact ATP yields vary with organism and conditions.',
      [
        OfflineQuestion(
          'Where does glycolysis occur in a typical eukaryotic cell?',
          ['Nucleus', 'Cytosol', 'Mitochondrial matrix only', 'Thylakoid'],
          1,
          'It occurs before mitochondrial stages.',
          'Glycolysis takes place in the cytosol and does not directly require oxygen.',
        ),
      ],
    ),
    OfflineLesson(
      'mitosis',
      'Mitosis',
      ['mitosis', 'समसूत्री विभाजन'],
      'Mitosis separates duplicated chromosomes into two nuclei, generally maintaining chromosome number. It supports growth, repair, and some forms of asexual reproduction. Cytokinesis divides the cell contents.',
      'After DNA replication, sister chromatids separate during anaphase. A typical diploid parent produces two daughter cells with the same chromosome number.',
      'DNA replication happens before mitosis, in S phase. Count chromosomes using centromeres rather than simply counting DNA strands.',
      [
        OfflineQuestion(
          'Sister chromatids separate during which stage of mitosis?',
          ['Prophase', 'Metaphase', 'Anaphase', 'Interphase'],
          2,
          'It is the stage when chromatids move toward opposite poles.',
          'During anaphase, sister chromatids separate and move to opposite poles.',
        ),
      ],
    ),
    OfflineLesson(
      'meiosis',
      'Meiosis',
      ['meiosis', 'reduction division'],
      'Meiosis uses two divisions after one round of DNA replication to reduce chromosome number. Homologous chromosomes separate in meiosis I; sister chromatids separate in meiosis II. Crossing over and independent assortment contribute to variation.',
      'A diploid cell with 2n = 8 typically forms haploid products with n = 4 after meiosis.',
      'There is no second S phase between meiosis I and II. Homologues and sister chromatids are different relationships.',
      [
        OfflineQuestion(
          'Which event distinguishes meiosis I from ordinary mitosis?',
          [
            'DNA replication during anaphase',
            'Separation of homologous chromosomes',
            'Formation of a cell membrane',
            'Sister chromatids always separating first',
          ],
          1,
          'Think about chromosome pairs, not identical copies.',
          'Homologous chromosomes separate in meiosis I; sister chromatids remain together until meiosis II.',
          difficulty: 2,
        ),
      ],
    ),
    OfflineLesson(
      'genetics',
      'Mendelian genetics',
      ['genetics', 'mendel', 'punnett square', 'inheritance'],
      'Alleles are versions of a gene. In a simple complete-dominance model, a dominant allele determines the heterozygote’s phenotype. Punnett squares track possible allele combinations, not guaranteed outcomes for individual offspring.',
      'For Aa × Aa, genotype probabilities are 1/4 AA, 1/2 Aa, 1/4 aa. With complete dominance, the phenotype ratio is 3:1.',
      'Many traits involve multiple genes and environment. Dominant does not mean common, stronger, or better.',
      [
        OfflineQuestion(
          'For AaBb × aabb, with independent assortment, P(aabb) is:',
          ['1/16', '1/4', '1/2', '3/4'],
          1,
          'Treat each gene separately, then multiply.',
          'P(aa) = 1/2 and P(bb) = 1/2; their product is 1/4.',
          difficulty: 3,
        ),
      ],
    ),
    OfflineLesson(
      'ecosystems',
      'Ecosystems and food webs',
      ['ecosystem', 'ecosystems', 'food web', 'food chain', 'ecology'],
      'An ecosystem includes organisms and their physical environment. Producers capture energy, consumers obtain it from food, and decomposers recycle nutrients. Energy flows through trophic levels while matter cycles.',
      'Grass → grasshopper → frog is a simple food chain. A food web shows many linked feeding relationships.',
      'Energy is not recycled like matter. Transfer efficiency varies; a 10% rule is an approximation, not a universal constant.',
      [
        OfflineQuestion(
          'Which statement is most accurate?',
          [
            'Energy cycles endlessly with no loss',
            'Matter cycles and energy flows through ecosystems',
            'Decomposers create energy',
            'Every food chain has the same efficiency',
          ],
          1,
          'Separate nutrient movement from energy transfer.',
          'Nutrients are recycled, while usable energy is progressively transferred and dissipated.',
        ),
      ],
    ),
    OfflineLesson(
      'evolution',
      'Evolution by natural selection',
      ['evolution', 'natural selection', 'adaptation'],
      'Natural selection occurs when heritable differences influence survival or reproduction, changing trait frequencies across generations. Mutation creates variation; selection acts on existing variation in an environment.',
      'If a heritable trait helps organisms leave more offspring in a particular environment, that trait may become more frequent over many generations.',
      'Individuals do not evolve a trait because they need it. Evolution concerns populations, and not all changes are caused by natural selection.',
      [
        OfflineQuestion(
          'Which condition is necessary for a trait to evolve through natural selection?',
          [
            'Individuals choose useful mutations',
            'Relevant variation is heritable',
            'All individuals reproduce equally',
            'The environment always improves',
          ],
          1,
          'A successful trait must be passed between generations.',
          'Heritable variation coupled with differences in reproductive success permits natural selection.',
          difficulty: 2,
        ),
      ],
    ),
    OfflineLesson(
      'complexity',
      'Algorithm complexity',
      ['algorithm complexity', 'time complexity', 'big o', 'asymptotic'],
      'Big-O describes an asymptotic upper bound on resource growth as input size increases. Common growth rates include O(1), O(log n), O(n), O(n log n), and O(n²). State what n measures and whether the bound is worst-case.',
      'A nested pair of loops, each running n times with constant work inside, usually takes O(n²). Doubling n roughly quadruples that work.',
      'Big-O is not an exact runtime. Separate input size, hidden constants, average/worst case, and extra-space usage.',
      [
        OfflineQuestion(
          'A loop halves a positive integer n each iteration until it reaches 1. Iteration count is:',
          ['O(1)', 'O(log n)', 'O(n)', 'O(n²)'],
          1,
          'How many halvings reduce n to 1?',
          'After k halvings the size is about n/2^k, so k is about log₂ n.',
          difficulty: 2,
        ),
      ],
    ),
    OfflineLesson(
      'binary-search',
      'Binary search',
      ['binary search'],
      'Binary search repeatedly halves a sorted search interval. Compare with the midpoint, retain the half that can contain the target, and preserve a clearly stated interval invariant.',
      'In [2, 5, 8, 12, 16], searching for 12 first compares with 8, then searches the right half. Its comparison count grows logarithmically.',
      'The data must be sorted under the comparison used. Check empty intervals, duplicate values, and whether endpoints are inclusive.',
      [
        OfflineQuestion(
          'For lower_bound on a sorted array, the desired result is:',
          [
            'Any equal element only',
            'The first index with value ≥ target, or the end',
            'The last value below target only',
            'Always the midpoint',
          ],
          1,
          'Think about an insertion position that preserves sorted order.',
          'The first value not less than the target is the lower bound; if none exists, return the end.',
          difficulty: 3,
        ),
      ],
    ),
    OfflineLesson(
      'recursion',
      'Recursion',
      ['recursion', 'recursive function', 'recursive functions'],
      'A recursive function solves a problem using smaller instances of itself. It needs a base case and a step that makes progress toward that base case. Each active call usually occupies stack space.',
      'For nonnegative integers, factorial(0) = 1 and factorial(n) = n × factorial(n − 1). Thus factorial(4) = 24.',
      'Repeated overlapping subproblems may need memoisation. A correct base case alone is insufficient if recursive calls do not approach it.',
      [
        OfflineQuestion(
          'The recurrence T(n) = 2T(n/2) + O(n), with a constant base case, has the standard bound:',
          ['O(log n)', 'O(n)', 'O(n log n)', 'O(n²)'],
          2,
          'Each recursion level does O(n) work; count levels.',
          'There are O(log n) levels with O(n) work per level, giving O(n log n).',
          difficulty: 3,
        ),
      ],
    ),
    OfflineLesson(
      'sql',
      'SQL and relational data',
      ['sql', 'database joins', 'relational database'],
      'SQL queries relational tables. SELECT chooses output, WHERE filters rows before grouping, GROUP BY forms groups, and HAVING filters grouped results. A JOIN relates rows using a condition.',
      'SELECT subject, SUM(minutes) FROM sessions GROUP BY subject HAVING SUM(minutes) > 60 returns subjects with more than 60 recorded minutes.',
      'NULL is checked with IS NULL, not = NULL. Joins can multiply rows; use a suitable key and check duplicates before summing.',
      [
        OfflineQuestion(
          'Which clause filters aggregated groups?',
          ['WHERE', 'ORDER BY', 'HAVING', 'FROM'],
          2,
          'The filter applies after GROUP BY.',
          'HAVING filters groups based on aggregate expressions; WHERE filters source rows.',
          difficulty: 2,
        ),
      ],
    ),
    OfflineLesson(
      'boolean',
      'Boolean logic',
      ['boolean', 'truth table', 'de morgan', 'logic gates'],
      'Boolean logic uses true/false values. AND requires both inputs, OR requires at least one, and NOT reverses a value. De Morgan’s laws connect negation with AND and OR.',
      'NOT(A AND B) = (NOT A) OR (NOT B). If A is true and B is false, both sides are true.',
      'Inclusive OR differs from exclusive OR. Add brackets when translating a sentence with several logical operators.',
      [
        OfflineQuestion(
          'Which is equivalent to NOT(A OR B)?',
          ['NOT A OR NOT B', 'NOT A AND NOT B', 'A AND B', 'A XOR B'],
          1,
          'Negate both inputs and swap OR with AND.',
          'By De Morgan’s law, NOT(A OR B) = (NOT A) AND (NOT B).',
          difficulty: 2,
        ),
      ],
    ),
    OfflineLesson(
      'essays',
      'Essay structure',
      ['essay', 'essays', 'academic writing', 'argument writing'],
      'Start with a specific thesis that answers the question. Build paragraphs around one claim, relevant evidence, explanation, and a link to the argument. Consider a fair counterargument and answer it.',
      'For a question about school gardens, one paragraph could claim that practical gardening supports science learning, cite appropriate evidence, and explain the connection to the thesis.',
      'A quotation does not explain itself. Cite sources, distinguish your analysis from borrowed ideas, and follow your school’s assessment rules.',
      [
        OfflineQuestion(
          'Which paragraph element explains why evidence supports the claim?',
          [
            'A longer quotation',
            'Analysis connecting evidence to the claim',
            'An unrelated fact',
            'Repeating the title',
          ],
          1,
          'Evidence needs an explicit link to the argument.',
          'Analysis interprets the evidence and explains its relevance.',
        ),
      ],
    ),
    OfflineLesson(
      'grammar',
      'Grammar and clear sentences',
      ['grammar', 'subject verb agreement', 'english tenses'],
      'Find the sentence’s subject and main verb. Make them agree in number and keep tense consistent with the time relationship. Use punctuation to show how ideas connect.',
      '“The list of topics is ready” uses “is” because “list” is the singular subject. The phrase “of topics” does not make the subject plural.',
      'The nearest noun is not always the subject. Prefer clear sentences over unnecessarily complicated wording.',
      [
        OfflineQuestion(
          'Which sentence has correct subject–verb agreement?',
          [
            'The box of books are heavy.',
            'The box of books is heavy.',
            'The boxes of books is heavy.',
            'The book are heavy.',
          ],
          1,
          'Identify the main subject, rather than the noun after “of”.',
          '“Box” is singular, so the verb is “is”.',
        ),
      ],
    ),
    OfflineLesson(
      'comprehension',
      'Reading comprehension',
      [
        'reading comprehension',
        'comprehension',
        'unseen passage',
        'critical reading',
      ],
      'Identify the passage’s main claim, paragraph roles, and supporting evidence. Separate what the author says from what can reasonably be inferred. Return to the text to justify an answer.',
      'If a passage says a trial “suggests” a result, an option saying it “proves the result in all cases” overstates the evidence.',
      'Do not choose an option merely because it sounds plausible outside the passage. Watch for extreme words and reversed cause and effect.',
      [
        OfflineQuestion(
          'A passage says “Some trials showed improvement.” Which inference is justified?',
          [
            'All trials proved the method works.',
            'At least some trials reported improvement.',
            'No trial improved.',
            'The method has no limitations.',
          ],
          1,
          'Keep the strength of the original statement.',
          '“Some” supports at least some, without claiming every trial or definitive proof.',
        ),
      ],
    ),
    OfflineLesson(
      'active-recall',
      'Active recall',
      [
        'active recall',
        'retrieval practice',
        'help me remember',
        'memorize',
        'memorise',
        'yaad kaise',
        'याद कैसे',
      ],
      'Retrieve an answer from memory before looking at the source. Trying, checking, and correcting reveals gaps better than simply recognising familiar notes.',
      'Close your notes and write three key ideas, check what you missed, then make a few question-and-answer cards. Review them tomorrow, in three days, and next week; bring difficult cards back sooner.',
      'Do not turn recall into rereading with the answer visible. Correct mistakes using a trusted source, and keep questions specific.',
      [
        OfflineQuestion(
          'Which activity is active recall?',
          [
            'Highlighting a page with the book open',
            'Answering a question from memory, then checking',
            'Copying a paragraph',
            'Watching the same video twice',
          ],
          1,
          'The answer should be retrieved before it is checked.',
          'Retrieval attempts followed by feedback are the key ingredients.',
        ),
      ],
    ),
    OfflineLesson(
      'spaced-repetition',
      'Spaced repetition',
      [
        'spaced repetition',
        'spaced revision',
        'forgetting',
        'i keep forgetting',
        'flashcards',
        'flashcard',
      ],
      'Space retrieval attempts over time rather than doing every review at once. Shorten the interval after a difficult or incorrect answer, and lengthen it when recall is reliable.',
      'Try a first review tomorrow, then roughly three days later and the following week. These are adjustable starting points, not a guarantee or automatic reminder.',
      'A review schedule is useful only if you test recall. Split cards with several facts into smaller questions.',
      [
        OfflineQuestion(
          'You repeatedly miss a flashcard. The most useful next step is:',
          [
            'Hide it for a month',
            'Review the explanation, simplify the card, and revisit sooner',
            'Mark it mastered',
            'Only reread its title',
          ],
          1,
          'Use errors to adjust both the card and its interval.',
          'Feedback repairs the gap; a simpler question and shorter interval support the next attempt.',
          difficulty: 2,
        ),
      ],
    ),
    OfflineLesson(
      'interleaving',
      'Interleaving',
      ['interleaving', 'mixed practice', 'mix topics'],
      'Interleaving mixes related problem types so you practise choosing a method, not just repeating one. Establish basic understanding first, then mix problems deliberately.',
      'After learning linear and quadratic methods separately, mix several unlabelled equations and explain why each chosen method fits.',
      'Randomly switching every few seconds is distraction, not interleaving. Keep enough time to complete and review each problem.',
      [
        OfflineQuestion(
          'Why can mixed problem sets help after initial learning?',
          [
            'They remove the need to think',
            'They require identifying which method applies',
            'They guarantee perfect marks',
            'They avoid feedback',
          ],
          1,
          'The problem type is not announced in advance.',
          'Choosing a method is itself a skill; mixed practice exercises that choice.',
          difficulty: 2,
        ),
      ],
    ),
    OfflineLesson(
      'feynman',
      'Explain-to-learn technique',
      ['feynman', 'teach back', 'explain to learn', 'explain like im five'],
      'Explain a concept in simple words to an imagined beginner. Notice where you become vague, return to a reliable source, then explain it again with a concrete example.',
      'For fractions, explain how equal-sized pieces combine, then show why halves and thirds need a shared piece size before adding.',
      'An analogy can help but is not a proof. State where it stops matching the real concept.',
      [
        OfflineQuestion(
          'While explaining a topic, you find a step you cannot justify. What next?',
          [
            'Add more jargon',
            'Skip it silently',
            'Check a reliable source and explain that step again',
            'Assume confidence means correctness',
          ],
          2,
          'A gap is useful feedback.',
          'Revisiting the gap and rebuilding the explanation is the learning step.',
        ),
      ],
    ),
    OfflineLesson(
      'notes',
      'Useful study notes',
      [
        'cornell notes',
        'note taking',
        'study notes',
        'make notes',
        'good notes',
        'take notes',
        'notes making',
      ],
      'Write short explanations, worked examples, and questions that will test understanding later. A cue column and brief summary can make Cornell-style notes useful for recall.',
      'For each page, keep one main idea, one worked example, one common error, and three closed-book questions.',
      'Copying everything neatly can feel productive without testing learning. Use notes to support practice, not replace it.',
      [
        OfflineQuestion(
          'Which note is most useful for later retrieval practice?',
          [
            'A copied page without questions',
            'A question cue with a checked answer and example',
            'Only coloured headings',
            'An unlabelled screenshot',
          ],
          1,
          'Choose something you can cover and test yourself on.',
          'A question cue creates a retrieval opportunity and the checked answer gives feedback.',
        ),
      ],
    ),
    OfflineLesson(
      'error-log',
      'Practice tests and error logs',
      [
        'mock test',
        'mock tests',
        'practice paper',
        'practice test',
        'past paper',
        'error log',
        'mistakes',
      ],
      'Use a timed set to diagnose learning, then classify each error: concept, recall, or rushing. Repair the specific cause before doing more of the same.',
      'Write the question type, your error, the corrected method, and a short retest date. Redo two missed questions without notes, then try a similar unfamiliar one.',
      'A high study-minute total does not prove mastery. Check current exam formats and marking rules in official notices.',
      [
        OfflineQuestion(
          'You know a method but repeatedly lose a minus sign. What should your error log include?',
          [
            'Only the final mark',
            'The exact sign-error step and a targeted checking routine',
            'A claim that the whole subject is impossible',
            'More rereading only',
          ],
          1,
          'Match the repair to the cause.',
          'Identifying the failing step makes practice and checking more specific.',
          difficulty: 2,
        ),
      ],
    ),
    OfflineLesson(
      'exam-technique',
      'Exam technique',
      [
        'exam technique',
        'exam strategy',
        'negative marking',
        'time management in exam',
      ],
      'Read instructions first, budget time by marks and difficulty, and reserve checking time. Start with questions you can handle, mark uncertain ones, and return if the format allows.',
      'For a 90-minute paper, a possible budget is 5 minutes to scan, 75 minutes answering, and 10 minutes checking; adapt it to the official format.',
      'Guessing strategy depends on the actual marking scheme. Do not assume all exams penalise wrong answers or allow section switching.',
      [
        OfflineQuestion(
          'With +4 for correct and −1 for wrong, guessing has positive expected marks when your probability p of being correct is:',
          ['p > 0.1', 'p > 0.2', 'p > 0.5', 'Any p including zero'],
          1,
          'Expected score is 4p − (1 − p).',
          '5p − 1 > 0 gives p > 1/5. This is a model, not a substitute for the real exam rules.',
          difficulty: 3,
        ),
      ],
    ),
    OfflineLesson(
      'procrastination',
      'Getting started',
      [
        'procrastination',
        'procrastinating',
        'cant get started',
        'cannot get started',
        'man nahi',
        'mood nahi',
      ],
      'Make the first action small and visible: open one topic, choose one question, and work for five minutes. Decide the action in advance rather than waiting for motivation.',
      'Use: “After I put my bag down, I will open Maths and attempt one question.” If it is too hard, start with reading and explaining the question.',
      'A missed session is information, not a verdict on you. Adjust the task, environment, or timing instead of adding punishment.',
      [
        OfflineQuestion(
          'Which is the clearest first step?',
          [
            'Study everything perfectly',
            'Be more motivated',
            'Open one page and attempt its first question for five minutes',
            'Wait until the work feels easy',
          ],
          2,
          'Choose a small action you can actually start.',
          'A concrete, short action lowers the barrier to beginning.',
        ),
      ],
    ),
    OfflineLesson(
      'distraction-habits',
      'Protecting attention',
      [
        'distraction habits',
        'stop scrolling',
        'phone distraction',
        'attention residue',
        'focus better',
        'improve focus',
        'concentrate',
        'concentration tips',
        'improve concentration',
        'lack of concentration',
      ],
      'Reduce avoidable interruptions before a block. Put distracting devices out of reach, prepare the material you need, and keep a small place to jot down unrelated thoughts.',
      'Choose one outcome, silence nonessential interruptions, and leave a note saying exactly where to restart after the break.',
      'Changing tasks repeatedly has a cost. Use FocusForge’s optional Shield controls only for apps you choose; permission is not required for offline tutoring.',
      [
        OfflineQuestion(
          'An unrelated idea appears during a focus block. A useful response is:',
          [
            'Open every related app immediately',
            'Write a short note and return to the current task',
            'Abandon the block',
            'Keep switching until it goes away',
          ],
          1,
          'Preserve the idea without changing tasks.',
          'A quick note can defer the distraction while keeping a clear current task.',
        ),
      ],
    ),
    OfflineLesson(
      'burnout',
      'Rest and sustainable study',
      ['burnout', 'burnt out', 'exhausted', 'study fatigue', 'too tired'],
      'Fatigue is a reason to adjust your workload. Take a proper break, eat and drink normally, and protect sleep. If this keeps happening, talk to a trusted adult, teacher, or qualified professional.',
      'Replace a demanding new topic with a brief familiar recap, or stop and return after rest. A repeatable plan is more useful than one unsustainable day.',
      'Study coaching cannot diagnose health conditions. Avoid treating rest as a reward you must earn.',
      [
        OfflineQuestion(
          'After repeated late nights you cannot concentrate. The most sensible adjustment is:',
          [
            'Remove every break',
            'Increase the workload again',
            'Protect rest and reduce the immediate plan',
            'Use unprescribed medication',
          ],
          2,
          'A sustainable plan responds to fatigue.',
          'Rest and a manageable plan are safer than forcing another exhausted session.',
        ),
      ],
    ),
    OfflineLesson(
      'goals',
      'Small goals and reflection',
      [
        'smart goals',
        'implementation intention',
        'weekly review',
        'study reflection',
      ],
      'Choose a specific action, a realistic amount of time, and a way to check learning. Review what helped and adjust the next plan using evidence rather than guilt.',
      '“Attempt six algebra questions, check each error, and explain one correction” is clearer than “get good at maths”.',
      'Hours and streaks measure activity, not your worth or guaranteed grades. Use a short recall check alongside your study totals.',
      [
        OfflineQuestion(
          'Which goal best includes a learning check?',
          [
            'Sit at the desk all day',
            'Read until it looks familiar',
            'Solve four questions and explain the errors',
            'Keep every streak at any cost',
          ],
          2,
          'Look for an observable demonstration of understanding.',
          'Solving and explaining errors checks more than time spent.',
        ),
      ],
    ),
  ];
}
