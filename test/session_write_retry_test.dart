import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:focusforge/core/models/user.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/services/local_store.dart';

class FailSessionWriteOnce extends InMemorySharedPreferencesStore {
  FailSessionWriteOnce() : super.empty();
  bool fail = true;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.ff.${StoreKeys.sessions}' && fail) {
      fail = false;
      throw StateError('disk temporarily unavailable');
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'failed session persistence remains recoverable after sync retry',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      await store.clearAll();
      final platform = FailSessionWriteOnce();
      SharedPreferencesStorePlatform.instance = platform;
      final c = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(c.dispose);
      c
          .read(userProvider.notifier)
          .hydrate(const UserProfile(uid: 'alice', isAnonymous: false));
      final t = c.read(timerProvider.notifier);
      final end = DateTime.now().subtract(const Duration(seconds: 1));
      t.hydrate({
        'phase': 'focus',
        'running': true,
        'targetEnd': end.millisecondsSinceEpoch,
        'segmentStartedAt': end
            .subtract(const Duration(minutes: 25))
            .millisecondsSinceEpoch,
        'segmentOwnerUid': 'alice',
        'segmentId': 'stable-completed-block',
      });
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(sessionsProvider), hasLength(1));
      t.sync();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final durable = await platform.getAll();
      final durableSessions = jsonDecode(
        durable['flutter.ff.${StoreKeys.sessions}'] as String? ?? '[]',
      ) as List;
      final snapshot = jsonDecode(
        durable['flutter.ff.${StoreKeys.presets}'] as String,
      ) as Map;
      final journal = snapshot['pendingCompletions'] as List;
      expect(
        durableSessions.isNotEmpty || journal.isNotEmpty,
        isTrue,
        reason:
            'a retry may acknowledge a block only after its session is durable',
      );
    },
  );
}
