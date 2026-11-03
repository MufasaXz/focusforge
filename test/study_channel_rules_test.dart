import 'package:flutter_test/flutter_test.dart';
import 'package:focusforge/core/models/shield.dart';

void main() {
  test(
    'the retired study-only flag never arms Study mode after an upgrade',
    () {
      final rules = YoutubeRules.fromJson({
        'shorts': true,
        'focusOnly': true,
        'studyOnly': true,
        'studyChannels': [' @teacher ', '', 42, '@Teacher', 'Open   Science'],
      });
      expect(rules.any, isTrue);
      expect(rules.study, isFalse);
      // Channels saved by the old filter are kept as a starting list.
      expect(rules.studyChannels, ['@teacher', 'Open   Science']);
      final restored = YoutubeRules.fromJson(rules.toJson());
      expect(restored.shorts, isTrue);
      expect(restored.focusOnly, isTrue);
      expect(restored.toJson().containsKey('studyOnly'), isFalse);
      expect(YoutubeRules.fromJson({'studyOnly': true}).any, isFalse);
    },
  );

  test('Study mode sends subject names as keywords only when chosen', () {
    const rules = YoutubeRules(study: true, studyKeywords: ['calculus']);
    expect(rules.forEngine(['Physics', 'Ar', ' Chemistry ']).studyKeywords, [
      'calculus',
      'Physics',
      'Chemistry',
    ]);
    expect(
      rules.copyWith(useSubjects: false).forEngine(['Physics']).studyKeywords,
      ['calculus'],
    );
    final restored = YoutubeRules.fromJson(rules.toJson());
    expect(restored.study, isTrue);
    expect(restored.useSubjects, isTrue);
  });
}
