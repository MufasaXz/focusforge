import 'package:flutter_test/flutter_test.dart';
import 'package:focusforge/core/models/shield.dart';

void main() {
  test(
    'study channel rules survive persistence and malformed lists stay bounded',
    () {
      final rules = YoutubeRules.fromJson({
        'studyOnly': true,
        'studyChannels': [' @teacher ', '', 42, '@Teacher', 'Open   Science'],
      });
      expect(rules.any, isTrue);
      expect(rules.studyChannels, ['@teacher', 'Open Science']);
      final restored = YoutubeRules.fromJson(rules.toJson());
      expect(restored.studyOnly, isTrue);
      expect(restored.studyChannels, rules.studyChannels);
      expect(
        restored.copyWith(shorts: true).studyChannels,
        rules.studyChannels,
      );
      expect(
        YoutubeRules.fromJson({'studyChannels': 'bad'}).studyChannels,
        isEmpty,
      );
      expect(YoutubeRules.fromJson({'studyOnly': 'true'}).studyOnly, isFalse);
    },
  );
}
