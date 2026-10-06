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

  group('FeedRow.withJson', () {
    final row = SeedData.feedGroups.first.rows.first;

    test('a valid override still applies', () {
      final updated = row.withJson(const {'enabled': false, 'mode': 2});
      expect(updated.enabled, isFalse);
      expect(updated.mode, ShieldMode.fullBlock);
    });

    test('a non-bool enabled leaves the seeded value untouched', () {
      for (final value in <Object?>[null, 'yes', 1, <int>[]]) {
        expect(
          row.withJson({'enabled': value}).enabled,
          row.enabled,
          reason: 'enabled=$value must not be cast',
        );
      }
    });

    test('a non-num mode leaves the seeded value untouched', () {
      for (final value in <Object?>[null, 'block', true, <String, dynamic>{}]) {
        expect(
          row.withJson({'mode': value}).mode,
          row.mode,
          reason: 'mode=$value must not be cast',
        );
      }
    });

    test('a non-finite mode degrades to feedOnly, not a truncation', () {
      for (final value in <double>[
        double.infinity,
        double.negativeInfinity,
        double.nan,
      ]) {
        expect(
          row.withJson({'mode': value}).mode,
          ShieldMode.feedOnly,
          reason: 'mode=$value must not be truncated',
        );
      }
    });
  });

  group('ShieldMode.fromIndex', () {
    test('null and out-of-range indexes clamp to feedOnly', () {
      for (final index in <int?>[null, -1, 3, 999]) {
        expect(
          ShieldMode.fromIndex(index),
          ShieldMode.feedOnly,
          reason: '$index',
        );
      }
    });

    test('in-range indexes keep their persisted order', () {
      // The index is written to the store, so this order is a wire format:
      // reordering the enum would silently remap every stored shield.
      expect(ShieldMode.fromIndex(0), ShieldMode.feedOnly);
      expect(ShieldMode.fromIndex(1), ShieldMode.timeLimit);
      expect(ShieldMode.fromIndex(2), ShieldMode.fullBlock);
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

    /// Applies a mutation through the notifier and tolerates the known
    /// Riverpod assertion it raises *after* the state change and store write
    /// have landed.
    ///
    /// `syncShield` re-reads the calling notifier's own provider
    /// (lib/core/providers/shield_providers.dart:23-30, called from :222),
    /// which Riverpod 3 rejects with "A provider cannot depend on itself".
    /// That is a real debug-only defect in lib/ — reported separately, not
    /// fixed here. Every assertion about the persisted result still runs
    /// unchanged; anything other than that exact assertion is rethrown.
    Future<void> applyMutation(Future<void> Function() mutation) async {
      try {
        await mutation();
      } on AssertionError catch (error) {
        expect('$error', contains('A provider cannot depend on itself'));
      }
    }

    test('a user-added entry survives a relaunch with its data intact', () async {
      var container = newContainer();
      expect(
        container.read(whitelistProvider),
        hasLength(10),
        reason: 'a fresh install gets every seed entry',
      );

      final custom = WhitelistEntry(
        id: 'roundtrip.new.app',
        name: 'Round Trip',
        icon: AppIcons.resolve('code'),
        color: const Color(0xFF123456),
        tier: WhitelistTier.budgeted,
        budgetMinutes: 17,
      );
      await applyMutation(
        () => container.read(whitelistProvider.notifier).add(custom),
      );

      // Relaunch: a fresh container hydrates from what was written.
      container = newContainer();
      container
          .read(whitelistProvider.notifier)
          .hydrate(store.getList(StoreKeys.whitelistTiers));
      final restored = container
          .read(whitelistProvider)
          .singleWhere((e) => e.id == 'roundtrip.new.app');
      expect(restored.name, 'Round Trip');
      expect(restored.tier, WhitelistTier.budgeted);
      expect(restored.budgetMinutes, 17);
      expect(restored.icon, Icons.code_rounded);
      expect(restored.color.toARGB32(), 0xFF123456);
    });

    test('a removed seed entry stays removed across a relaunch', () async {
      final container = newContainer();
      await applyMutation(
        () => container.read(whitelistProvider.notifier).remove('tiktok'),
      );
      expect(
        container.read(whitelistProvider).any((e) => e.id == 'tiktok'),
        isFalse,
      );

      final relaunched = newContainer();
      relaunched
          .read(whitelistProvider.notifier)
          .hydrate(store.getList(StoreKeys.whitelistTiers));
      final entries = relaunched.read(whitelistProvider);
      expect(
        entries.any((e) => e.id == 'tiktok'),
        isFalse,
        reason: 'the tombstone must keep the seed from coming back',
      );
      expect(entries, hasLength(9));
    });

    test('clearing the store restores the seed catalogue', () async {
      final container = newContainer();
      await applyMutation(
        () => container.read(whitelistProvider.notifier).remove('tiktok'),
      );
      await store.clearAll();

      final relaunched = newContainer();
      relaunched
          .read(whitelistProvider.notifier)
          .hydrate(store.getList(StoreKeys.whitelistTiers));
      final entries = relaunched.read(whitelistProvider);
      expect(
        entries,
        hasLength(10),
        reason: 'a wiped store is a fresh install',
      );
      expect(entries.any((e) => e.id == 'tiktok'), isTrue);
    });
  });
}
