import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/services/local_store.dart';
import 'package:focusforge/features/assistant/assistant_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'either consent choice persists and stays isolated across accounts',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      await store.clearAll();
      ProviderContainer open() => ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      var c = open();
      expect(c.read(assistantMemoryProvider).aiConsent, isNull);
      await c.read(assistantMemoryProvider.notifier).setAiConsent(false);
      expect(store.getBool('pip_cloud_consent'), isFalse);
      c.dispose();
      c = open();
      expect(c.read(assistantMemoryProvider).aiConsent, isFalse);
      await c.read(assistantMemoryProvider.notifier).setAiConsent(true);
      await c
          .read(assistantMemoryProvider.notifier)
          .switchAccount('student-a', 'student-b');
      expect(c.read(assistantMemoryProvider).aiConsent, isNull);
      expect(store.getBool('pip_cloud_consent'), isNull);
      await c.read(assistantMemoryProvider.notifier).setAiConsent(false);
      await c
          .read(assistantMemoryProvider.notifier)
          .switchAccount('student-b', 'student-a');
      expect(c.read(assistantMemoryProvider).aiConsent, isTrue);
      expect(store.getBool('pip_cloud_consent'), isTrue);
      c.dispose();
    },
  );
}
