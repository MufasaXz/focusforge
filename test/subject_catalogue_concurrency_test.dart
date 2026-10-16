import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focusforge/core/models/study.dart';
import 'package:focusforge/core/providers/app_providers.dart';
import 'package:focusforge/core/providers/study_providers.dart';
import 'package:focusforge/core/services/local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'overlapping onboarding selection preserves the latest catalogue choice',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      final container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final subjects = container.read(subjectsProvider.notifier);
      await subjects.add(
        const Subject(
          id: 'math',
          name: 'Math',
          icon: Icons.book,
          color: Colors.blue,
        ),
      );
      final removing = subjects.remove('math');
      await Future<void>.value();
      final adding = subjects.add(
        const Subject(
          id: 'physics',
          name: 'Physics',
          icon: Icons.science,
          color: Colors.green,
        ),
      );
      await Future.wait([removing, adding]);
      expect(container.read(subjectsProvider).map((s) => s.id), ['physics']);
      expect(store.getList(StoreKeys.subjects).map((s) => s['id']), [
        'physics',
      ]);
    },
  );
}
