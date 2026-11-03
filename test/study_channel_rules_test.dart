import 'package:flutter_test/flutter_test.dart';
import 'package:focusforge/core/models/shield.dart';

void main() {
  test(
    'retired study-only settings do not arm hidden filters after an upgrade',
    () {
      final rules = YoutubeRules.fromJson({
        'shorts': true,
        'focusOnly': true,
        'studyOnly': true,
        'studyChannels': [' @teacher ', '', 42, '@Teacher', 'Open   Science'],
      });
      expect(rules.any, isTrue);
      final restored = YoutubeRules.fromJson(rules.toJson());
      expect(restored.shorts, isTrue);
      expect(restored.focusOnly, isTrue);
      expect(restored.toJson().containsKey('studyOnly'), isFalse);
      expect(restored.toJson().containsKey('studyChannels'), isFalse);
      expect(YoutubeRules.fromJson({'studyOnly': true}).any, isFalse);
    },
  );
}
