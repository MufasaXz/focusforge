import 'dart:math' as math;

/// A bounded arithmetic/degree-two polynomial parser. No eval, execution,
/// external packages, model, or network is used. Unsupported expressions
/// produce a useful limitation instead of a guessed answer.
abstract final class OfflineMath {
  static final _number = r'(-?(?:\d+(?:\.\d+)?|\.\d+))';

  static bool recognizes(String input) {
    final text = _clean(input);
    if (RegExp(r'^(calculate|compute|evaluate|solve|simplify|convert)\b')
        .hasMatch(text)) {
      // A request to explain a concept is handled by the knowledge library.
      return RegExp(r'\d|[=+*/^]|\bx\b').hasMatch(text);
    }
    if (RegExp(r'^(mean|median|mode|range|average|percentage change)\b')
            .hasMatch(text) &&
        RegExp(r'\d').hasMatch(text)) {
      return true;
    }
    if (RegExp(r'^(increase|decrease)\s+-?\d').hasMatch(text)) return true;
    if (RegExp(r'\d\s*%\s*of\s*-?\d').hasMatch(text)) return true;
    final expression = _prefix(text);
    return RegExp(r'\d').hasMatch(expression) &&
        RegExp(r'^[\dxpisqrtab\.\s()+*/^=:%-]+$').hasMatch(expression);
  }

  static String answer(String input) {
    if (input.length > 240) {
      return 'Please use a maths expression of at most 240 characters.';
    }
    final text = _clean(input);
    final percentage = RegExp(
      '^(?:what is |calculate )?$_number\\s*%\\s*of\\s*$_number\$',
    ).firstMatch(text);
    if (percentage != null) {
      final p = double.parse(percentage[1]!);
      final n = double.parse(percentage[2]!);
      return _result(
        '${format(p)}% of ${format(n)} = '
        '${format(p)} ÷ 100 × ${format(n)}',
        p / 100 * n,
      );
    }
    final change = RegExp(
      '^(increase|decrease)\\s+$_number\\s+by\\s+$_number\\s*%\$',
    ).firstMatch(text);
    if (change != null) {
      final n = double.parse(change[2]!);
      final p = double.parse(change[3]!);
      final delta = n * p / 100;
      final result = change[1] == 'increase' ? n + delta : n - delta;
      return _result(
        'Change = ${format(n)} × ${format(p)} ÷ 100 = '
        '${format(delta)}. New value',
        result,
      );
    }
    final percentChange = RegExp(
      '^percentage change from $_number to $_number\$',
    ).firstMatch(text);
    if (percentChange != null) {
      final before = double.parse(percentChange[1]!);
      final after = double.parse(percentChange[2]!);
      if (before <= 0) {
        return 'For percentage change, use a positive starting value. '
            'A change from zero has no defined percentage.';
      }
      return _result(
        'Percentage change = (new − old) ÷ old × 100',
        (after - before) / before * 100,
        suffix: '%',
      );
    }
    final statistics = RegExp(
      r'^(mean|median|mode|range|average)(?: of)?\s+([\d.,\s-]+)$',
    ).firstMatch(text);
    if (statistics != null) return _statistics(statistics);
    final conversion = RegExp(
      '^(?:convert )?$_number\\s*([a-z°]+)\\s+(?:to|in)\\s+([a-z°]+)\$',
    ).firstMatch(text);
    if (conversion != null) return _convert(conversion);
    final ratio = RegExp(r'^(?:simplify\s+)?(?:ratio\s+)?(\d+)\s*:\s*(\d+)$')
        .firstMatch(text);
    if (ratio != null) {
      final a = int.tryParse(ratio[1]!);
      final b = int.tryParse(ratio[2]!);
      if (a == null || b == null || a > 1000000000 || b > 1000000000) {
        return 'Use ratio terms between 0 and 1,000,000,000.';
      }
      if (a == 0 && b == 0) return 'The ratio 0:0 cannot be simplified.';
      final divisor = a.gcd(b);
      return 'Divide both terms by their greatest common divisor, $divisor: '
          '$a:$b = ${a ~/ divisor}:${b ~/ divisor}.';
    }
    try {
      final expression = _prefix(text);
      if (expression.length > 180) {
        throw const _MathError('Please shorten the expression.');
      }
      final sides = expression.split('=');
      if (sides.length > 2) throw const _MathError('Use just one equals sign.');
      final left = _Parser(sides.first).parse();
      if (sides.length == 1) {
        if (!left.constant) {
          return 'To solve for x, include both sides, for example '
              '“solve 2*x + 3 = 11”. I can solve linear and quadratic equations.';
        }
        return '$expression = ${format(left.c)}. '
            'Brackets and powers first, then multiplication/division, '
            'then addition/subtraction.';
      }
      final p = left - _Parser(sides[1]).parse();
      if (p.a == 0 && p.b == 0) {
        return p.c == 0
            ? 'Both sides are identical: every real x satisfies this equation '
                  'within the supported polynomial domain.'
            : 'The x terms cancel, leaving ${format(p.c)} = 0, which is false. '
                  'There is no solution.';
      }
      if (p.a == 0) {
        final root = -p.c / p.b;
        return 'Collect like terms: ${format(p.b)}*x + (${format(p.c)}) = 0. '
            'Subtract the constant and divide by ${format(p.b)}: '
            'x = ${format(root)}. Substitute this value into the original '
            'equation to check it.';
      }
      final discriminant = p.b * p.b - 4 * p.a * p.c;
      final start =
          'Collect terms: a = ${format(p.a)}, b = ${format(p.b)}, '
          'c = ${format(p.c)}. Discriminant b² − 4ac = ${format(discriminant)}. ';
      if (discriminant < 0) {
        return '${start}There are no real roots. '
            'This local solver does not expand complex roots.';
      }
      if (discriminant == 0) {
        return '${start}One repeated root: x = ${format(-p.b / (2 * p.a))}.';
      }
      // The stable form avoids losing the smaller root to cancellation.
      final q = -0.5 * (p.b + (p.b >= 0 ? 1 : -1) * math.sqrt(discriminant));
      final roots = [q / p.a, p.c / q]..sort();
      return '${start}Using x = (−b ± √discriminant) ÷ (2a): '
          'x = ${format(roots[0])} or x = ${format(roots[1])}.';
    } on _MathError catch (error) {
      return '${error.message} Try “(12 + 8) / 5”, “15% of 240”, '
          '“convert 2 km to m”, or “solve 2*x + 3 = 11”.';
    }
  }

  static String _clean(String input) => input
      .toLowerCase()
      .trim()
      .replaceAll('×', '*')
      .replaceAll('÷', '/')
      .replaceAll('−', '-')
      .replaceAll('π', 'pi')
      .replaceAll('²', '^2')
      .replaceAll('³', '^3')
      .replaceAll(RegExp(r'[?!]+$'), '')
      .trim();

  static String _prefix(String text) => text
      .replaceFirst(
        RegExp(
          r'^(?:(?:please )?(?:calculate|compute|evaluate|solve|simplify)|what is|whats)\s+',
        ),
        '',
      )
      .trim();

  static String _result(String working, double value, {String suffix = ''}) =>
      value.isFinite && value.abs() <= 1e100
      ? '$working = ${format(value)}$suffix.'
      : 'That result is outside the supported numeric range. Use smaller numbers.';

  static String format(double value) {
    if (!value.isFinite) {
      throw const _MathError('The result is outside the numeric range.');
    }
    if (value == 0) return '0';
    if (value.abs() < 1e-7 || value.abs() >= 1e12) {
      return value.toStringAsPrecision(10);
    }
    return value.toStringAsFixed(8).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static String _statistics(RegExpMatch match) {
    final parts = match[2]!.trim().split(RegExp(r'[,\s]+'));
    if (parts.length > 100) {
      return 'Use at most 100 values for a local statistics calculation.';
    }
    final values = parts.map(double.tryParse).toList();
    if (values.isEmpty ||
        values.any((v) => v == null || !v.isFinite || v.abs() > 1e12)) {
      return 'Use a list of finite numbers separated by commas, such as “mean 2, 4, 6”.';
    }
    final sorted = values.cast<double>()..sort();
    switch (match[1]) {
      case 'mean' || 'average':
        final sum = sorted.fold(0.0, (a, b) => a + b);
        return 'Mean = sum ÷ count = ${format(sum)} ÷ ${sorted.length} = '
            '${format(sum / sorted.length)}.';
      case 'median':
        final middle = sorted.length ~/ 2;
        final value = sorted.length.isOdd
            ? sorted[middle]
            : (sorted[middle - 1] + sorted[middle]) / 2;
        return 'Sort the values, then take the middle '
            '${sorted.length.isOdd ? 'value' : 'pair’s average'}: median = ${format(value)}.';
      case 'range':
        return 'Range = maximum − minimum = ${format(sorted.last)} − '
            '(${format(sorted.first)}) = ${format(sorted.last - sorted.first)}.';
      default:
        final counts = <double, int>{};
        for (final value in sorted) {
          counts.update(value, (n) => n + 1, ifAbsent: () => 1);
        }
        final most = counts.values.reduce(math.max);
        if (most == 1) return 'No value repeats, so this list has no mode.';
        final modes = counts.keys
            .where((v) => counts[v] == most)
            .map(format)
            .join(', ');
        return 'Mode${counts.values.where((n) => n == most).length > 1 ? 's' : ''}: '
            '$modes (each appears $most times).';
    }
  }

  static const _units = <String, (String, double)>{
    'mm': ('length', 0.001),
    'cm': ('length', 0.01),
    'm': ('length', 1),
    'km': ('length', 1000),
    'mg': ('mass', 0.001),
    'g': ('mass', 1),
    'kg': ('mass', 1000),
    'ml': ('volume', 0.001),
    'l': ('volume', 1),
    's': ('time', 1),
    'sec': ('time', 1),
    'seconds': ('time', 1),
    'min': ('time', 60),
    'minutes': ('time', 60),
    'h': ('time', 3600),
    'hr': ('time', 3600),
    'hours': ('time', 3600),
  };

  static String _convert(RegExpMatch m) {
    final value = double.parse(m[1]!);
    final from = m[2]!.replaceAll('°', '');
    final to = m[3]!.replaceAll('°', '');
    if ({'c', 'f', 'k'}.contains(from) && {'c', 'f', 'k'}.contains(to)) {
      final c = switch (from) {
        'f' => (value - 32) * 5 / 9,
        'k' => value - 273.15,
        _ => value,
      };
      if (c < -273.15 - 1e-10) {
        return 'That temperature is below absolute zero.';
      }
      final result = switch (to) {
        'f' => c * 9 / 5 + 32,
        'k' => c + 273.15,
        _ => c,
      };
      return _result('${format(value)} $from, converted to $to', result);
    }
    final source = _units[from];
    final target = _units[to];
    if (source == null || target == null || source.$1 != target.$1) {
      return 'Use matching units: mm/cm/m/km, mg/g/kg, ml/l, s/min/h, '
          'or temperature C/F/K. Different physical quantities cannot be converted directly.';
    }
    return _result(
      '${format(value)} $from × ${format(source.$2)} ÷ '
      '${format(target.$2)}',
      value * source.$2 / target.$2,
      suffix: ' $to',
    );
  }
}

class _MathError implements Exception {
  const _MathError(this.message);
  final String message;
}

/// c + b*x + a*x², with explicit domain restrictions on division and powers.
class _Poly {
  _Poly(this.c, [this.b = 0, this.a = 0]) {
    if ([c, b, a].any((v) => !v.isFinite || v.abs() > 1e100)) {
      throw const _MathError(
        'The expression is outside the supported numeric range.',
      );
    }
  }
  final double c;
  final double b;
  final double a;
  bool get constant => b == 0 && a == 0;
  _Poly operator +(_Poly p) => _Poly(c + p.c, b + p.b, a + p.a);
  _Poly operator -(_Poly p) => _Poly(c - p.c, b - p.b, a - p.a);
  _Poly negate() => _Poly(-c, -b, -a);
  _Poly operator *(_Poly p) {
    if (a * p.a != 0 || a * p.b + b * p.a != 0) {
      throw const _MathError(
        'Only polynomials up to degree two are supported.',
      );
    }
    return _Poly(c * p.c, c * p.b + b * p.c, c * p.a + b * p.b + a * p.c);
  }

  _Poly operator /(_Poly p) {
    if (!p.constant) {
      throw const _MathError(
        'Division by an expression containing x is not supported.',
      );
    }
    if (p.c == 0) throw const _MathError('Division by zero is undefined.');
    return _Poly(c / p.c, b / p.c, a / p.c);
  }

  _Poly power(_Poly p) {
    if (!p.constant || p.c != p.c.roundToDouble() || p.c.abs() > 12) {
      throw const _MathError('Use a whole-number exponent between −12 and 12.');
    }
    if (p.c < 0 && !constant) {
      throw const _MathError('Negative powers of x are not supported.');
    }
    if (c == 0 && constant && p.c <= 0) {
      throw const _MathError(
        'Zero to a zero or negative power is undefined here.',
      );
    }
    var result = _Poly(1);
    for (var i = 0; i < p.c.abs(); i++) {
      result = result * this;
    }
    return p.c < 0 ? _Poly(1) / result : result;
  }
}

class _Parser {
  _Parser(String expression) {
    final scanner = RegExp(
      r'\s*(\d+(?:\.\d*)?|\.\d+|sqrt|abs|pi|x|[()+*/^\-])',
    );
    var offset = 0;
    var depth = 0;
    final text = expression.trim();
    while (offset < text.length) {
      final match = scanner.matchAsPrefix(text, offset);
      if (match == null) {
        throw const _MathError(
          'That expression contains unsupported notation.',
        );
      }
      final token = match[1]!;
      if (token == '(' && ++depth > 16) {
        throw const _MathError('Use fewer nested brackets.');
      }
      if (token == ')') depth--;
      _tokens.add(token);
      offset = match.end;
      if (_tokens.length > 100) {
        throw const _MathError('Please use a shorter expression.');
      }
    }
  }
  final _tokens = <String>[];
  var _at = 0;
  String? get _next => _at < _tokens.length ? _tokens[_at] : null;
  bool _take(String token) {
    if (_next != token) return false;
    _at++;
    return true;
  }

  _Poly parse() {
    final result = _sum();
    if (_next != null) {
      throw const _MathError('Check the operators and brackets.');
    }
    return result;
  }

  _Poly _sum() {
    var value = _product();
    while (true) {
      if (_take('+')) {
        value = value + _product();
      } else if (_take('-')) {
        value = value - _product();
      } else {
        return value;
      }
    }
  }

  _Poly _product() {
    var value = _unary();
    while (true) {
      if (_take('*')) {
        value = value * _unary();
      } else if (_take('/')) {
        value = value / _unary();
      } else if (const ['(', 'x', 'pi', 'sqrt', 'abs'].contains(_next)) {
        value = value * _unary();
      } else {
        return value;
      }
    }
  }

  _Poly _unary() {
    if (_take('+')) return _unary();
    if (_take('-')) return _unary().negate();
    final base = _atom();
    return _take('^') ? base.power(_unary()) : base;
  }

  _Poly _atom() {
    if (_take('(')) {
      final value = _sum();
      if (!_take(')')) throw const _MathError('A closing bracket is missing.');
      return value;
    }
    if (_take('x')) return _Poly(0, 1);
    if (_take('pi')) return _Poly(math.pi);
    if (_next == 'sqrt' || _next == 'abs') {
      final function = _tokens[_at++];
      if (!_take('(')) {
        throw const _MathError('Use brackets after sqrt or abs.');
      }
      final value = _sum();
      if (!_take(')') || !value.constant) {
        throw const _MathError(
          'Use a numeric argument inside the function brackets.',
        );
      }
      if (function == 'sqrt' && value.c < 0) {
        throw const _MathError(
          'The square root of a negative number is not real.',
        );
      }
      return _Poly(function == 'sqrt' ? math.sqrt(value.c) : value.c.abs());
    }
    final token = _next;
    final value = token == null ? null : double.tryParse(token);
    if (value == null) {
      throw const _MathError('A number or bracket is missing.');
    }
    _at++;
    return _Poly(value);
  }
}
