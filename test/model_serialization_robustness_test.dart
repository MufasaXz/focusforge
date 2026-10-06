// Pins the decoding contract for every model that reads persisted JSON.
//
// WHAT INVARIANT: a malformed stored value must degrade to a safe default —
// it must never throw.
//
// WHY IT MATTERS: these readers run inside bootstrap(), before the first
// frame, so one unguarded cast on one bad entry aborts the whole launch
// instead of the entry degrading. The wrong-typed cases below are not
// hypothetical: `walkedAway` used to be read as `as bool? ?? true`, which
// passed null through the cast but threw on `"yes"` and killed the launch
// (lib/core/models/shield.dart:318-327).
//
// The whitelist round-trips at the bottom cover the other half of the
// contract: whatever the app writes must decode back into the same value,
// including for entries the seed catalogue does not know about.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focusforge/core/data/seed.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/shield_providers.dart';
import 'package:focusforge/core/services/local_store.dart';

/// Values a corrupt store could hand a `fromJson` reader: nulls, wrong
/// primitives, non-finite numbers, and container types.
const _malformed = <Object?>[
  null,
  'x',
  5,
  5.5,
  true,
  <int>[],
  <String, dynamic>{},
  // `jsonDecode('1e999')` yields these rather than throwing, so a corrupt
  // store really can hand them over.
  double.infinity,
  double.negativeInfinity,
  double.nan,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('BreathEvent.fromJson', () {
    test('an empty map degrades to a blank event, never throws', () {
      final event = BreathEvent.fromJson(const {});
      expect(event.appName, isEmpty);
      expect(
        event.at.millisecondsSinceEpoch,
        0,
        reason: 'the epoch is the sentinel for a missing timestamp; "now" '
            'would fabricate recent activity on the impulse chart',
      );
      expect(event.walkedAway, isTrue, reason: 'the compatible default');
    });

    test('a wrong-typed walkedAway is ignored, not cast', () {
      // Regression: `as bool? ?? true` threw on this exact payload.
      final event = BreathEvent.fromJson(const {'walkedAway': 'yes'});
      expect(event.walkedAway, isTrue);
    });

    test('an out-of-range timestamp degrades to the epoch', () {
      // DateTime rejects an epoch outside ±8.64e15 ms; 1e16 is just past it.
      for (final at in <num>[1e16, -1e16]) {
        final event = BreathEvent.fromJson({'at': at});
        expect(event.at.millisecondsSinceEpoch, 0, reason: 'at=$at');
        expect(event.appName, isEmpty);
        expect(event.walkedAway, isTrue);
      }
    });

    test('a non-finite timestamp degrades to the epoch', () {
      for (final at in <double>[
        double.infinity,
        double.negativeInfinity,
        double.nan,
      ]) {
        expect(
          BreathEvent.fromJson({'at': at}).at.millisecondsSinceEpoch,
          0,
          reason: 'at=$at',
        );
      }
    });

    test('the infinity a corrupt store holds is reachable from JSON text', () {
      // jsonDecode('1e999') returns double.infinity instead of throwing,
      // which is how a corrupt store can hold it at all.
      final at = jsonDecode('1e999');
      expect(at, double.infinity);
      expect(BreathEvent.fromJson({'at': at}).at.millisecondsSinceEpoch, 0);
    });

    test('every field survives null, wrong-typed and container values', () {
      for (final field in const ['appName', 'at', 'walkedAway']) {
        for (final value in _malformed) {
          expect(
            () => BreathEvent.fromJson({field: value}),
            returnsNormally,
            reason: 'BreathEvent.fromJson({$field: $value})',
          );
        }
      }
    });
  });

  group('StrictModeConfig.fromJson', () {
    test('an empty map falls back to the documented defaults', () {
      final config = StrictModeConfig.fromJson(const {});
      expect(config.enabled, isFalse);
      expect(config.durationMinutes, 120);
      expect(config.allowCalls, isTrue);
      expect(config.allowEmergency, isTrue);
      expect(config.allowMaps, isFalse);
      expect(config.cooldownSeconds, 60);
    });

    test('a non-finite duration or cooldown falls back to its default', () {
      for (final bad in <double>[
        double.infinity,
        double.negativeInfinity,
        double.nan,
      ]) {
        final config = StrictModeConfig.fromJson({
          'durationMinutes': bad,
          'cooldownSeconds': bad,
        });
        expect(config.durationMinutes, 120, reason: 'durationMinutes=$bad');
        expect(config.cooldownSeconds, 60, reason: 'cooldownSeconds=$bad');
      }
    });

    test('every field survives null, wrong-typed and container values', () {
      const fields = [
        'enabled',
        'durationMinutes',
        'allowCalls',
        'allowEmergency',
        'allowMaps',
        'cooldownSeconds',
      ];
      for (final field in fields) {
        for (final value in _malformed) {
          expect(
            () => StrictModeConfig.fromJson({field: value}),
            returnsNormally,
            reason: 'StrictModeConfig.fromJson({$field: $value})',
          );
        }
      }
    });
  });

  group('YoutubeRules.fromJson', () {
    test('an empty map turns every surface off', () {
      final rules = YoutubeRules.fromJson(const {});
      expect(rules.shorts, isFalse);
      expect(rules.feed, isFalse);
      expect(rules.any, isFalse);
    });

    test('a wrong-typed switch is ignored, not cast', () {
      // Same failure mode the BreathEvent regression covers: `as bool?` would
      // pass a null through and throw on the string, aborting bootstrap.
      final rules = YoutubeRules.fromJson(const {
        'shorts': 'yes',
        'feed': 1,
      });
      expect(rules.shorts, isFalse);
      expect(rules.feed, isFalse);
    });

    test('every field survives null, wrong-typed and container values', () {
      for (final field in const ['shorts', 'feed']) {
        for (final value in _malformed) {
          expect(
            () => YoutubeRules.fromJson({field: value}),
            returnsNormally,
            reason: 'YoutubeRules.fromJson({$field: $value})',
          );
        }
      }
    });

    test('a written value decodes back to the same rules', () {
      const rules = YoutubeRules(shorts: true, feed: false);
      final restored = YoutubeRules.fromJson(rules.toJson());
      expect(restored.shorts, isTrue);
      expect(restored.feed, isFalse);
    });
  });

  group('Subject.fromJson', () {
    test('an empty map degrades to a blank subject', () {
      final subject = Subject.fromJson(const {});
      expect(subject.id, isEmpty);
      expect(subject.name, 'Subject');
      expect(subject.weekTarget, 0);
    });

    test('a non-finite counter or colour degrades to its default', () {
      final subject = Subject.fromJson(const {
        'minutesToday': double.infinity,
        'color': double.infinity,
      });
      expect(subject.minutesToday, 0);
      expect(subject.color, const Color(0xFFB0BEC5));
    });

    test('every field survives null, wrong-typed and container values', () {
      const fields = [
        'id',
        'name',
        'icon',
        'color',
        'minutesToday',
        'weekDone',
        'weekTarget',
      ];
      for (final field in fields) {
        for (final value in _malformed) {
          expect(
            () => Subject.fromJson({field: value}),
            returnsNormally,
            reason: 'Subject.fromJson({$field: $value})',
          );
        }
      }
    });
  });

  group('UserProfile avatar round-trip', () {
    test('a chosen mark and colour survive being stored', () {
      const profile = UserProfile(
        displayName: 'Sam',
        avatarIcon: 'star',
        avatarColor: 0xFF4285F4,
      );
      final restored = UserProfile.fromJson(
        jsonDecode(jsonEncode(profile.toJson())) as Map<String, dynamic>,
      );
      expect(restored.avatarIcon, 'star');
      expect(restored.avatarColor, 0xFF4285F4);
    });

    test('initials are a choice, so clearing the mark sticks', () {
      const profile = UserProfile(avatarIcon: 'star', avatarColor: 0xFF4285F4);
      final cleared = profile.copyWith(clearAvatar: true);
      expect(
        cleared.avatarIcon,
        isNull,
        reason: 'a null icon means "use my initials", not "unchanged"',
      );
      expect(
        cleared.avatarColor,
        0xFF4285F4,
        reason: 'the colour outlives the mark it was chosen with',
      );
    });

    test('a malformed avatar degrades instead of throwing', () {
      for (final value in _malformed) {
        expect(
          () => UserProfile.fromJson({'avatarIcon': value}),
          returnsNormally,
          reason: 'avatarIcon: $value',
        );
        expect(
          () => UserProfile.fromJson({'avatarColor': value}),
          returnsNormally,
          reason: 'avatarColor: $value',
        );
      }
      final profile = UserProfile.fromJson(const {
        'avatarIcon': 7,
        'avatarColor': 'blue',
      });
      expect(profile.avatarIcon, isNull);
      expect(profile.avatarColor, isNull);
    });
  });

  group('FocusSession.fromJson', () {
    test('an empty map degrades to an epoch session', () {
      final session = FocusSession.fromJson(const {});
      expect(session.startedAt.millisecondsSinceEpoch, 0);
      expect(session.minutes, 0);
      expect(
        session.completed,
        isTrue,
        reason: 'entries written before the field existed were completed',
      );
      expect(session.subjectId, isEmpty);
    });

    test('a non-finite or out-of-range timestamp degrades to the epoch', () {
      for (final startedAt in <num>[
        1e16,
        double.infinity,
        double.negativeInfinity,
        double.nan,
      ]) {
        final session = FocusSession.fromJson({'startedAt': startedAt});
        expect(
          session.startedAt.millisecondsSinceEpoch,
          0,
          reason: 'startedAt=$startedAt',
        );
      }
    });

    test('non-finite minutes degrade to zero', () {
      for (final minutes in <double>[
        double.infinity,
        double.negativeInfinity,
        double.nan,
      ]) {
        expect(
          FocusSession.fromJson({'minutes': minutes}).minutes,
          0,
          reason: 'minutes=$minutes',
        );
      }
    });

    test('every field survives null, wrong-typed and container values', () {
      const fields = [
        'id',
        'subjectId',
        'startedAt',
        'minutes',
        'completed',
        'label',
      ];
      for (final field in fields) {
        for (final value in _malformed) {
          expect(
            () => FocusSession.fromJson({field: value}),
            returnsNormally,
            reason: 'FocusSession.fromJson({$field: $value})',
          );
        }
      }
    });
  });

  group('whitelist persistence round-trips', () {
    late LocalStore store;

    setUpAll(() async {
      store = await LocalStore.open();
    });

    setUp(() async {
      await store.clearAll();
    });

    ProviderContainer newContainer() {
      final container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      return container;
    }

    /// Applies a mutation through the notifier.
    ///
    /// The notifier persists and then pushes the new state to the platform
    /// service. `syncShield` reads the providers the caller is *not* inside —
    /// the calling notifier passes its own value in — so no self-dependency
    /// assertion is reachable from here.
    Future<void> applyMutation(Future<void> Function() mutation) async {
      await mutation();
    }

    test('a fresh install starts with no rules at all', () {
      final container = newContainer();
      expect(
        container.read(whitelistProvider),
        isEmpty,
        reason: 'a catalogue the user never chose is a list of apps that '
            'close without being asked to',
      );
    });

    test('an added app survives a relaunch with its package id', () async {
      var container = newContainer();
      await applyMutation(
        () => container.read(whitelistProvider.notifier).addInstalledApp(
          packageId: 'com.example.roundtrip',
          name: 'Round Trip',
          tier: WhitelistTier.budgeted,
          budgetMinutes: 17,
        ),
      );

      // Relaunch: a fresh container hydrates from what was written.
      container = newContainer();
      container
          .read(whitelistProvider.notifier)
          .hydrate(store.getList(StoreKeys.whitelistTiers));
      final restored = container.read(whitelistProvider).single;

      expect(restored.name, 'Round Trip');
      expect(
        restored.packageId,
        'com.example.roundtrip',
        reason: 'the package is what the engine matches on — an entry that '
            'loses it is a rule that can never fire',
      );
      expect(restored.tier, WhitelistTier.budgeted);
      expect(restored.budgetMinutes, 17);
      expect(restored.enforceable, isTrue);
    });

    test('adding the same package twice moves it instead of duplicating', () async {
      final container = newContainer();
      final notifier = container.read(whitelistProvider.notifier);

      await applyMutation(
        () => notifier.addInstalledApp(
          packageId: 'com.example.twice',
          name: 'Twice',
          tier: WhitelistTier.blocked,
        ),
      );
      await applyMutation(
        () => notifier.addInstalledApp(
          packageId: 'com.example.twice',
          name: 'Twice',
          tier: WhitelistTier.alwaysAllowed,
        ),
      );

      final entries = container.read(whitelistProvider);
      expect(entries, hasLength(1));
      expect(entries.single.tier, WhitelistTier.alwaysAllowed);
    });

    test('a removed app stays removed across a relaunch', () async {
      final container = newContainer();
      final notifier = container.read(whitelistProvider.notifier);
      await applyMutation(
        () => notifier.addInstalledApp(
          packageId: 'com.example.gone',
          name: 'Gone',
        ),
      );
      await applyMutation(() => notifier.remove('pkg:com.example.gone'));
      expect(container.read(whitelistProvider), isEmpty);

      final relaunched = newContainer();
      relaunched
          .read(whitelistProvider.notifier)
          .hydrate(store.getList(StoreKeys.whitelistTiers));
      expect(
        relaunched.read(whitelistProvider),
        isEmpty,
        reason: 'a removed entry must not come back on the next launch',
      );
    });

    test('moving into the budget tier gives it an allowance', () async {
      final container = newContainer();
      final notifier = container.read(whitelistProvider.notifier);
      await applyMutation(
        () => notifier.addInstalledApp(
          packageId: 'com.example.budget',
          name: 'Budget',
        ),
      );

      await applyMutation(
        () => notifier.setTier('pkg:com.example.budget', WhitelistTier.budgeted),
      );
      expect(
        container.read(whitelistProvider).single.budgetMinutes,
        WhitelistNotifier.defaultBudgetMinutes,
        reason: 'a budget with no allowance is a rule that can never fire',
      );

      await applyMutation(
        () => notifier.setTier(
          'pkg:com.example.budget',
          WhitelistTier.alwaysAllowed,
        ),
      );
      expect(
        container.read(whitelistProvider).single.budgetMinutes,
        isNull,
        reason: 'leaving the tier clears the allowance with it',
      );
    });

    test('a budget is clamped to a usable range', () async {
      final container = newContainer();
      final notifier = container.read(whitelistProvider.notifier);
      await applyMutation(
        () => notifier.addInstalledApp(
          packageId: 'com.example.clamp',
          name: 'Clamp',
          tier: WhitelistTier.budgeted,
        ),
      );

      await applyMutation(() => notifier.setBudget('pkg:com.example.clamp', 0));
      expect(container.read(whitelistProvider).single.budgetMinutes, 5);

      await applyMutation(
        () => notifier.setBudget('pkg:com.example.clamp', 100000),
      );
      expect(
        container.read(whitelistProvider).single.budgetMinutes,
        24 * 60,
      );
    });

    test('a stored row with no readable package is kept but not enforced', () {
      final container = newContainer();
      container.read(whitelistProvider.notifier).hydrate([
        {'id': 'legacy.row', 'name': 'Legacy', 'tier': 2},
      ]);

      final entry = container.read(whitelistProvider).single;
      expect(entry.name, 'Legacy');
      expect(entry.tier, WhitelistTier.blocked);
      expect(
        entry.enforceable,
        isFalse,
        reason: 'the user can still see and remove it, but a rule with '
            'nothing to match must not be counted as armed',
      );
      expect(container.read(blockedAppsProvider), isEmpty);
    });

    test('a corrupt row degrades instead of aborting hydration', () {
      final container = newContainer();
      container.read(whitelistProvider.notifier).hydrate([
        {'id': 'corrupt.row', 'tier': 'blocked', 'budgetMinutes': double.nan},
      ]);

      final entry = container.read(whitelistProvider).single;
      expect(entry.tier, WhitelistTier.alwaysAllowed);
      expect(entry.budgetMinutes, isNull);
    });
  });
}
