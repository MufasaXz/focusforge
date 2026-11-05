// "Resume" on Home's session shortcut means continuing a paused block.
//
// WHAT INVARIANT: the translations say "continue", not "curriculum vitae".
//
// WHY IT MATTERS: the word was machine-translated as the noun, so the button
// that resumes a paused block read "Lebenslauf", "CV" or "履歴書".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:focusforge/core/localization/app_strings.dart';

void main() {
  test('Resume continues the timer in every language', () {
    const expected = {
      'de': 'Fortsetzen',
      'es': 'Reanudar',
      'fr': 'Reprendre',
      'pt': 'Retomar',
      'ru': 'Продолжить',
      'ja': '再開',
      'zh': '继续',
      'hi': 'फिर शुरू करें',
    };
    for (final MapEntry(key: code, value: text) in expected.entries) {
      expect(AppStrings(Locale(code)).text('Resume'), text, reason: code);
    }
  });
}
