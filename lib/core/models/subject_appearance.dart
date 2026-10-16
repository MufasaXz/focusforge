import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import 'icon_registry.dart';
import 'study.dart';

class SubjectAppearance {
  const SubjectAppearance._();
  static String iconName(String name) {
    final text = name.toLowerCase();
    final rules = <String, List<String>>{
      'math': [
        'math',
        'algebra',
        'calculus',
        'geometry',
        'statistics',
        'गणित',
        '数学',
      ],
      'physics': ['physic', 'mechanic', 'electric', 'भौतिक'],
      'chemistry': ['chem', 'रसायन'],
      'biology': ['bio', 'anatomy', 'medicine', 'zoology', 'botany', 'जीव'],
      'code': [
        'coding',
        'computer',
        'programming',
        'software',
        'python',
        'java',
        'informatics',
      ],
      'history': ['history', 'civics', 'politic', 'इतिहास'],
      'maps': ['geograph', 'geology', 'earth', 'भूगोल'],
      'planning': ['econom', 'business', 'finance', 'account', 'commerce'],
      'art': ['art', 'design', 'drawing', 'painting', 'music'],
      'english': [
        'english',
        'language',
        'literature',
        'hindi',
        'french',
        'spanish',
        'sanskrit',
        'हिंदी',
      ],
      'writing': ['writing', 'essay', 'thesis'],
    };
    for (final rule in rules.entries) {
      if (rule.value.any(text.contains)) return rule.key;
    }
    return 'book';
  }

  static IconData icon(String name) => AppIcons.resolve(iconName(name));
  static Color unusedColor(Iterable<Subject> subjects) {
    final used = subjects.map((s) => s.color.toARGB32()).toSet();
    for (final color in SubjectPalette.all) {
      if (!used.contains(color.toARGB32())) return color;
    }
    for (var i = 0; i < 10000; i++) {
      final color = HSLColor.fromAHSL(
        1,
        (i * 137.507764) % 360,
        .57,
        .48 + (i % 3) * .04,
      ).toColor();
      if (!used.contains(color.toARGB32())) return color;
    }
    return Color(0xFF000000 | (used.length * 7919 & 0xFFFFFF));
  }
}
