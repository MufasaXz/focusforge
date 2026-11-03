import 'package:flutter_test/flutter_test.dart';

import 'package:focusforge/core/providers/usage_stats_providers.dart';
import 'package:focusforge/core/services/app_catalog.dart';

void main() {
  InstalledApp app(String id, {int? category, bool system = false}) =>
      InstalledApp(
        packageId: id,
        name: id,
        isSystem: system,
        category: category,
      );

  final classifier = UsageClassifier(
    apps: {
      'com.example.game': app('com.example.game', category: 0),
      'com.example.notes': app('com.example.notes', category: 7),
      'com.example.chat': app('com.example.chat'),
      'com.google.android.youtube': app(
        'com.google.android.youtube',
        system: true,
      ),
      'com.example.ruled': app('com.example.ruled', category: 7),
      'com.android.launcher': app('com.android.launcher', system: true),
    },
    shielded: const {'com.example.ruled'},
    launchable: const {
      'com.example.game',
      'com.example.notes',
      'com.example.chat',
      'com.google.android.youtube',
      'com.example.ruled',
    },
  );

  test(
    'apps are grouped by Shield rule, known list, then Android category',
    () {
      expect(
        classifier.categoryOf('com.example.game'),
        UsageCategory.distracting,
      );
      expect(
        classifier.categoryOf('com.example.notes'),
        UsageCategory.productive,
      );
      expect(classifier.categoryOf('com.example.chat'), UsageCategory.other);
      expect(
        classifier.categoryOf('com.google.android.youtube'),
        UsageCategory.distracting,
      );
      // The user's own Shield rule outranks the developer's category.
      expect(
        classifier.categoryOf('com.example.ruled'),
        UsageCategory.distracting,
      );
    },
  );

  test(
    'only launchable apps count, so the launcher never inflates the day',
    () {
      final day = {
        'com.example.game': 30,
        'com.example.notes': 20,
        'com.example.chat': 10,
        'com.android.launcher': 90,
      };
      expect(
        classifier.select(day).keys,
        isNot(contains('com.android.launcher')),
      );
      expect(classifier.split(day), {
        UsageCategory.distracting: 30,
        UsageCategory.productive: 20,
        UsageCategory.other: 10,
      });
      expect(classifier.select(day, UsageCategory.productive), {
        'com.example.notes': 20,
      });
    },
  );

  test('without a launchable list, system apps are left out', () {
    final fallback = UsageClassifier(
      apps: classifier.apps,
      shielded: const {},
      launchable: const {},
    );
    expect(fallback.counts('com.example.chat'), isTrue);
    expect(fallback.counts('com.android.launcher'), isFalse);
  });

  test('weeks start on Monday', () {
    expect(weekStart(DateTime(2026, 11, 3, 15)), DateTime(2026, 11, 2));
    expect(weekStart(DateTime(2026, 11, 8, 23)), DateTime(2026, 11, 2));
    expect(weekStart(DateTime(2026, 11, 9)), DateTime(2026, 11, 9));
  });
}
