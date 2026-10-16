import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusforge/core/models/subject_appearance.dart';
import 'package:focusforge/core/models/icon_registry.dart';
import 'package:focusforge/core/models/study.dart';

void main() {
  test('subject names map to relevant persisted icons', () {
    for (final name in [
      'Mathematics',
      'Advanced Physics',
      'Organic Chemistry',
      'Biology',
      'Computer programming',
      'History',
      'Geography',
      'Economics',
      'Hindi',
    ]) {
      final icon = SubjectAppearance.icon(name);
      expect(AppIcons.nameOf(icon), isNotNull);
      expect(SubjectAppearance.iconName(name), isNot('book'));
    }
    expect(SubjectAppearance.iconName('Personal project'), 'book');
  });
  test('automatic colors remain unused beyond the fixed palette', () {
    final subjects = <Subject>[];
    for (var i = 0; i < 100; i++) {
      final color = SubjectAppearance.unusedColor(subjects);
      expect(subjects.any((s) => s.color == color), isFalse);
      subjects.add(
        Subject(id: 's$i', name: 'Subject $i', icon: Icons.book, color: color),
      );
    }
  });
}
